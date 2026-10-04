"""gummi_model against CONTRACT.md section 8, on a tiny synthetic cohort (no real data needed)."""
import time

import numpy as np
import pandas as pd
import pytest

from gummi_model import GlucoseModel, UserContext, permutation_test
from gummi_model import config as C
from gummi_model.train import (band_quantiles, build_samples, export_bundle, fit_cgm_only, fit_horizons,
                               predict_cgm_only, predict_horizons)


def _cohort(n_people=4, days=3, seed=1):
    """Synthetic CGM with meal bumps so meal features carry signal."""
    rng = np.random.default_rng(seed)
    cg, ml = [], []
    for p in range(n_people):
        pid = f"{p + 1:03d}"
        ts = pd.date_range("2020-03-01 00:00:00", periods=days * 288, freq="5min")
        g = np.full(len(ts), 100.0) + rng.normal(0, 2, len(ts)).cumsum() * 0.1
        meals = []
        for d in range(days):
            for hour, carbs in ((8, 50), (13, 70), (19, 60)):
                e = pd.Timestamp("2020-03-01") + pd.Timedelta(days=d, hours=hour)
                meals.append((e, carbs))
                age = (ts - e).total_seconds().to_numpy() / 60
                g += np.where(age > 0, carbs * 0.9 * (age / 55) ** 2 * np.exp(-(age - 55) / 27.5) , 0)
        cg.append(pd.DataFrame({"participant_id": pid, "ts": ts, "glucose": g, "island": 0}))
        ml.append(pd.DataFrame({"participant_id": pid, "eaten_at": [m[0] for m in meals],
                                "carbs_g": [m[1] for m in meals], "sugar_g": 10.0, "fiber_g": 2.0,
                                "protein_g": 15.0, "fat_g": 10.0}))
    return pd.concat(cg, ignore_index=True), pd.concat(ml, ignore_index=True)


FOLD_MAP = {"001": 0, "002": 0, "003": 1, "004": 1}


@pytest.fixture(scope="module")
def artifact(tmp_path_factory):
    """Full model plus 2 fold models and the participant-to-fold map, built the way gummi_pipeline builds them."""
    cgm, meals = _cohort()
    s = build_samples(cgm, meals)
    ks = list(range(C.MAX_H))
    fold_of = np.array([FOLD_MAP[p] for p in s.pid])
    resid = np.full(s.y.shape, np.nan); cresid = np.full(s.y.shape, np.nan)
    comps = {}
    for f in (0, 1):
        tr, te = s.subset(fold_of != f), s.subset(fold_of == f)
        m_f, _ = fit_horizons(tr, "cgm_meals", ks)
        c_f = fit_cgm_only(tr, ks)
        resid[fold_of == f] = te.y - predict_horizons(m_f, te, "cgm_meals")
        cresid[fold_of == f] = te.y + te.last[:, None] - predict_cgm_only(c_f, te)
        comps[f"fold{f}"] = {"models": m_f, "cgm_models": c_f, "training_participants": sorted(set(tr.pid.tolist()))}
    for f in (0, 1):
        keep = fold_of != f
        comps[f"fold{f}"].update(bands=band_quantiles(resid[keep], s.meal_known[keep]),
                                 cgm_bands=band_quantiles(cresid[keep], s.meal_known[keep]))
    models, _ = fit_horizons(s, "cgm_meals", ks)
    comps["full"] = {"models": models, "bands": band_quantiles(resid, s.meal_known), "cgm_models": fit_cgm_only(s, ks),
                     "cgm_bands": band_quantiles(cresid, s.meal_known), "training_participants": sorted(FOLD_MAP)}
    meta = {"simulate_method": "model", "cohort": {"meal_rise_sd_mg_dl": 20.0, "breakfast_rise_per_g_median": 1.0}}
    out = export_bundle(tmp_path_factory.mktemp("art") / "gummi_model_v1", comps, "cgm_meals", FOLD_MAP, meta)
    return out, cgm, meals


def _ctx(cgm, meals, now, pid="001", delay=60):
    g = cgm[cgm.participant_id == pid]
    dt = now - pd.Timedelta(minutes=delay)
    cdf = pd.DataFrame({"t": g.ts[g.ts <= dt].dt.tz_localize("UTC"), "glucose_mg_dl": g.glucose[g.ts <= dt]})
    m = meals[(meals.participant_id == pid) & (meals.eaten_at <= now)].drop(columns="participant_id").copy()
    m["eaten_at"] = m["eaten_at"].dt.tz_localize("UTC")
    return UserContext(f"p_{pid}", {"high_line_mg_dl": 140, "timezone": "UTC"}, cdf, m, None, None)


def test_estimate_gap_and_forecast_cover_the_right_window(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-02 08:30:00")
    ctx = _ctx(cgm, meals, now)
    gap = model.estimate_gap(ctx, now.tz_localize("UTC"))
    fc = model.forecast(ctx, now.tz_localize("UTC"), minutes=120)
    assert len(gap) == 12 and len(fc) == 24
    assert all(p["kind"] == "estimate" for p in gap) and all(p["kind"] == "forecast" for p in fc)
    for p in gap + fc:
        assert p["band_low_mg_dl"] <= p["glucose_mg_dl"] <= p["band_high_mg_dl"]
        assert set(p) == {"t", "glucose_mg_dl", "band_low_mg_dl", "band_high_mg_dl", "kind"}
    assert pd.Timestamp(fc[-1]["t"]) <= now.tz_localize("UTC") + pd.Timedelta(minutes=120)


def test_meal_raises_the_forecast(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-02 08:05:00").tz_localize("UTC")
    ctx = _ctx(cgm, meals, now.tz_localize(None))
    sim = model.simulate(ctx, now, {"carbs_g": 80, "sugar_g": 20, "fiber_g": 2, "protein_g": 10, "fat_g": 5})
    assert sim["peak_mg_dl"] > sim["without_food_peak_mg_dl"]
    half = [a for a in sim["alternatives"] if a["label"] == "Half portion"][0]
    assert half["peak_mg_dl"] < sim["peak_mg_dl"]
    assert sim["method"] == "model" and sim["verdict"] in {"go", "go_with_tweak", "wait"}
    assert len(sim["with_food_curve"]) == len(sim["baseline_curve"])


def test_gummi_view_fields(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-02 10:00:00")
    v = model.gummi_view(_ctx(cgm, meals, now), now.tz_localize("UTC"))
    assert set(v) >= {"glucose_mg_dl", "band_low_mg_dl", "band_high_mg_dl", "trend", "as_of",
                      "minutes_since_confirmed", "confidence"}
    assert v["minutes_since_confirmed"] >= 60
    assert v["trend"] in {"rising_fast", "rising", "flat", "falling", "falling_fast"}
    assert v["confidence"] in {"high", "medium", "low"}


def _meal_prediction(m, cgm, meals, eat):
    ctx = _ctx(cgm, meals, eat)
    e = eat.tz_localize("UTC")
    win = m.forecast(ctx, e, 120)
    cgm_only = m.cgm_only_forecast(ctx, e, 120)
    return {"prediction_id": "pr_1", "kind": "meal", "about": "lunch", "predicted_curve": win,
            "window_start": e.isoformat(), "window_end": (e + pd.Timedelta(minutes=120)).isoformat(),
            "predicted_peak_mg_dl": max(p["glucose_mg_dl"] for p in win),
            "cgm_only_peak_mg_dl": max(p["glucose_mg_dl"] for p in cgm_only), "cgm_only_curve": cgm_only,
            "last_value_peak_mg_dl": float(ctx.cgm_df.glucose_mg_dl.iloc[-1])}


def test_grade_reports_gummi_cgm_only_and_last_value(artifact):
    out, cgm, meals = artifact
    m = GlucoseModel.load(out).for_user("p_001")
    pred = _meal_prediction(m, cgm, meals, pd.Timestamp("2020-03-02 13:00:00"))
    g = cgm[cgm.participant_id == "001"]
    full = pd.DataFrame({"t": g.ts.dt.tz_localize("UTC"), "glucose_mg_dl": g.glucose})
    gr = m.grade(pred, full)
    assert gr["status"] == "graded" and gr["points"] >= 20
    for k in ("gummi_mae_mg_dl", "cgm_only_mae_mg_dl", "last_value_mae_mg_dl", "gummi_peak_error_mg_dl",
              "within_band_pct", "walk_effect_graded", "gummi_beats_cgm_only", "message"):
        assert gr[k] is not None
    assert not any(k.startswith("baseline") for k in gr)                      # D-32: last_value_* names only
    assert "CGM-only said" in gr["message"] and "last value said" in gr["message"]
    assert gr["walk_effect_graded"] is True
    walked = m.grade(pred, full, overlay_walks=[{"started_at": "2020-03-02T13:20:00Z", "minutes": 10}])
    assert walked["walk_effect_graded"] is False and "Walk effect not graded" in walked["message"]
    assert m.grade({**pred, "predicted_curve": []}, full)["status"] == "insufficient_data"


def test_for_user_never_returns_a_model_trained_on_that_participant(artifact):
    out, _, _ = artifact
    model = GlucoseModel.load(out)
    for pid, f in FOLD_MAP.items():
        assert model.fold_of(f"p_{pid}") == f
        m = model.for_user(f"p_{pid}")
        assert m is not model and m.fold == f
        assert pid not in m.training_participants                              # out-of-sample replay (D-26)
        assert m.version == f"{C.VERSION}_fold{f}"
    assert model.fold_of("u_nikhil") is None and model.for_user("u_nikhil") is model
    assert model.fold_of("p_015") is None and model.for_user("p_015") is model   # excluded: not in any fold
    assert set(model.training_participants) == set(FOLD_MAP)


def test_cgm_only_forecast_covers_the_same_window(artifact):
    out, cgm, meals = artifact
    m = GlucoseModel.load(out).for_user("p_003")
    now = pd.Timestamp("2020-03-02 08:30:00")
    ctx = _ctx(cgm, meals, now)
    nu = now.tz_localize("UTC")
    fc, co = m.forecast(ctx, nu, 120), m.cgm_only_forecast(ctx, nu, 120)
    assert [p["t"] for p in fc] == [p["t"] for p in co] and all(p["kind"] == "forecast" for p in co)
    gap = m.cgm_only_forecast(ctx, nu, 0, include_gap=True)
    assert len(gap) == 12 and all(p["kind"] == "estimate" for p in gap)
    for p in co:
        assert p["band_low_mg_dl"] <= p["glucose_mg_dl"] <= p["band_high_mg_dl"]


def test_update_personal_and_walk_effect(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-03 20:00:00")
    ctx = _ctx(cgm, meals, now, delay=0)
    p = model.update_personal(ctx, [{"status": "graded", "gummi_bias_mg_dl": 6.0, "graded_at": "2020-03-03T10:00:00Z"},
                                    {"status": "graded", "gummi_bias_mg_dl": 4.0, "graded_at": "2020-03-03T15:00:00Z"}])
    assert -25 <= p["offset_mg_dl"] <= 25 and 0.5 <= p["carb_factor"] <= 2.0 and p["n_grades"] == 2
    assert p["n_meals_used"] >= 1
    w = model.walk_effect(ctx, 10, "moderate")
    assert w["effect_source"] == "literature" and w["forecast_peak_drop_mg_dl"] == pytest.approx(14.4)
    assert model.walk_effect(ctx, 0, "sedentary")["forecast_peak_drop_mg_dl"] == 0.0
    assert model.version == C.VERSION


def test_walk_never_removes_more_than_half_the_meal(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-02 08:05:00").tz_localize("UTC")
    ctx = _ctx(cgm, meals, now.tz_localize(None))
    sim = model.simulate(ctx, now, {"carbs_g": 80, "sugar_g": 20, "fiber_g": 2, "protein_g": 10, "fat_g": 5})
    walk = [a for a in sim["alternatives"] if a["label"].startswith("Walk")][0]
    effect = sim["peak_mg_dl"] - sim["without_food_peak_mg_dl"]
    assert sim["peak_mg_dl"] - walk["peak_mg_dl"] <= 0.5 * effect + 1.0


def test_latency(artifact):
    out, cgm, meals = artifact
    model = GlucoseModel.load(out)
    now = pd.Timestamp("2020-03-02 08:30:00")
    ctx = _ctx(cgm, meals, now)
    nu = now.tz_localize("UTC")
    model.estimate_gap(ctx, nu)
    t = time.perf_counter()
    for _ in range(5):
        model.estimate_gap(ctx, nu); model.forecast(ctx, nu, 120)
    assert (time.perf_counter() - t) / 5 * 1000 < 50
    t = time.perf_counter()
    model.simulate(ctx, nu, {"carbs_g": 60})
    assert (time.perf_counter() - t) * 1000 < 100


def test_permutation_test():
    assert permutation_test([20, 25], [40, 45, 50])["status"] == "not enough data yet"
    r = permutation_test([10, 12, 9, 11, 13, 10], [40, 42, 38, 45, 41, 39])
    assert r["status"] == "significant" and r["drop_mg_dl"] > 25
    assert permutation_test([40, 42, 38], [10, 12, 9])["status"] == "not significant"


def test_fit_personal_recovers_scale_and_shrinks():
    from gummi_model.personal import fit_personal
    rng = np.random.default_rng(1)
    terms = []
    for _ in range(20):
        c = np.linspace(0, 30, 24)
        terms.append((c, 1.6 * c + 4.0 + rng.normal(0, 1, 24)))
    f, o = fit_personal(terms, with_offset=True)
    from gummi_model import config as C
    n = len(terms)                                    # true 1.6 and 4.0, pulled toward 1 and 0 by the pseudo-counts
    assert abs(f - (1.6 * n + C.CARB_FACTOR_SHRINK) / (n + C.CARB_FACTOR_SHRINK)) < 0.05
    assert abs(o - 4.0 * n / (n + C.OFFSET_SHRINK_N)) < 0.5 and 1.0 < f < 1.6 and 0.0 < o < 4.0
    f1, o1 = fit_personal(terms[:1], with_offset=True)
    assert abs(f1 - 1.0) < abs(f - 1.0) and abs(o1) < abs(o)   # one meal of evidence moves it less
    assert fit_personal([], with_offset=True) == (1.0, 0.0)
