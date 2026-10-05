"""The whole data path as one function, shared by the laptop script and the Databricks notebook.

run(raw_dir, out_dir, exclude) -> dict of DataFrames + paths. Nothing here is judge-facing until the human
approves the numbers.
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import numpy as np
import pandas as pd

from bigideas import build_silver_cgm, build_silver_meals, completeness_report, load_demographics, load_e4
from bigideas.baseline import baseline_repro, summarize as summarize_baseline, windows
from bigideas.explore import breakfast_response, cohort_stats, meal_responses, rise_vs_carbs_by_person
from bigideas.replay import replay_tables
from gummi_model import config as C
from gummi_model import evaluate as E
from gummi_model.train import (band_quantiles, build_samples, export_bundle, fit_cgm_only, fit_horizons,
                               predict_cgm_only, predict_horizons)


def hr_minutes(raw: Path, participants: list[str]) -> pd.DataFrame | None:
    """Per-minute mean heart rate (30-220 bpm) for the ablation. None if any HR file is missing."""
    parts = []
    for pid in participants:
        f = Path(raw) / pid / f"HR_{pid}.csv"
        if not f.exists():
            return None
        df = load_e4(f, usecols=["hr"])
        df = df[(df["hr"] >= 30) & (df["hr"] <= 220)]
        m = df.groupby(df["datetime"].dt.floor("min"))["hr"].mean().reset_index()
        m.columns = ["minute", "hr"]
        m.insert(0, "participant_id", pid)
        parts.append(m)
    return pd.concat(parts, ignore_index=True)


def run(raw_dir, out_dir, exclude=("015",), use_hr: bool = True, meal_eval: bool = True, log=print) -> dict:
    raw, out = Path(raw_dir), Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    say = lambda *a: log(f"[{time.time() - t0:6.1f}s] " + " ".join(str(x) for x in a))
    res: dict = {}

    # 1. silver
    cgm = build_silver_cgm(raw)
    meals = build_silver_meals(raw)
    demo = load_demographics(raw / "Demographics.csv")
    everyone = sorted(cgm["participant_id"].unique())
    excluded = [p for p in exclude if p in everyone]
    included = [p for p in everyone if p not in set(excluded)]
    comp = completeness_report(cgm).merge(demo, on="participant_id", how="left")
    res.update(silver_cgm_5min=cgm, silver_meals=meals, demographics=demo, completeness=comp)
    say(f"silver: {len(cgm)} readings, {len(meals)} meals, {len(everyone)} participants; excluded {excluded}")

    # 2. published baseline, with and without the exclusion
    bl = baseline_repro(cgm, exclude=tuple(excluded))
    bl_all = baseline_repro(cgm, exclude=())
    res.update(baseline_per_fold=bl, baseline_summary=summarize_baseline(bl).reset_index(),
               baseline_summary_all=summarize_baseline(bl_all).reset_index())
    say("published baseline (excluding %s):\n%s" % (excluded, res["baseline_summary"].to_string(index=False)))
    say("published baseline (all 16):\n%s" % res["baseline_summary_all"].to_string(index=False))

    # 3. samples on the same participant folds as the baseline
    cgm_inc = cgm[cgm["participant_id"].isin(included)]
    _, _, groups = windows(cgm_inc)
    folds = E.fold_map(groups)
    hr = hr_minutes(raw, included) if use_hr else None
    samples = build_samples(cgm_inc, meals, hr_minutes=hr)
    res["folds"] = folds
    say(f"samples: {len(samples)} origins; HR {'on' if hr is not None else 'off'}; folds {folds}")

    # 4. evaluation + meal ablation
    pf = E.evaluate(samples, folds, feature_sets=("cgm", "cgm_meals"))
    res.update(eval_per_fold=pf, eval_results=E.summarize(pf), ablation_results=E.ablation_table(pf))
    say("RMSE, all windows:\n%s" % res["eval_results"][res["eval_results"].window == "all"].pivot(
        index="horizon_min", columns="model", values="rmse_mean").to_string())
    say("meal ablation:\n%s" % res["ablation_results"].to_string(index=False))
    if hr is not None:
        has_hr = ~np.isnan(samples.hr).any(axis=1)
        pf_hr = E.evaluate(samples.subset(has_hr), folds, feature_sets=("cgm_meals", "cgm_meals_hr"), with_bands=False)
        res["ablation_hr"] = E.ablation_table(pf_hr, a="gummi_cgm_meals", b="gummi_cgm_meals_hr")
        say(f"HR ablation ({int(has_hr.sum())} origins with HR):\n%s" % res["ablation_hr"].to_string(index=False))

    # 5. exploration
    resp = meal_responses(cgm, meals)
    bf = breakfast_response(resp)
    cohort = cohort_stats(resp[resp["participant_id"].isin(included)], bf[bf["participant_id"].isin(included)])
    res.update(meal_responses=resp, breakfast_response=bf, rise_vs_carbs=rise_vs_carbs_by_person(resp), cohort=cohort)
    say(f"cohort: {cohort}")

    # 6. method choice from the ablation: meals must help at 30-120 min (mean and >= 4 of 5 folds)
    abl = res["ablation_results"]
    core = abl[(abl.window == "all") & (abl.horizon_min.between(30, 120))]
    meals_help = bool(len(core) and (core["diff_mean"] < 0).all() and (core["folds_b_better"] >= 4).all())
    feature_set = "cgm_meals" if meals_help else "cgm"
    simulate_method = "model" if meals_help else "breakfast_response"
    res.update(meals_help=meals_help, feature_set=feature_set, simulate_method=simulate_method)
    say(f"meals help at 30-120 min: {meals_help} -> {feature_set}, simulate={simulate_method}")

    # 7. what the app shows: meal predictions made at logging time, graded against the real peak
    meta_eval = {"simulate_method": simulate_method, "cohort": cohort}
    if meal_eval:
        # the CGM-only ridge runs next to the chosen model so the meal-time table has its CGM-only comparison
        sets = tuple(dict.fromkeys(("cgm", feature_set)))
        mp = E.meal_prediction_eval(samples, folds, cgm_inc, meals, feature_sets=sets, meta=meta_eval)
        res["meal_predictions"] = mp
        res["meal_prediction_summary"] = pd.concat([
            E.summarize_meal_predictions(mp).assign(subset="all meals"),
            E.summarize_meal_predictions(mp[mp.carbs_g >= 40]).assign(subset="meals >= 40 g carbs"),
            E.summarize_meal_predictions(mp[mp.is_standard_breakfast]).assign(subset="standardized breakfasts"),
        ], ignore_index=True)
        say("meal predictions:\n%s" % res["meal_prediction_summary"].to_string(index=False))

        # 7b. does the personal layer help? learned online from each held-out person's earlier meals
        pe = E.personal_online_eval(samples, folds, cgm_inc, meals, feature_set=feature_set, meta=meta_eval)
        res["personal_layer_eval"] = pe
        res["personal_layer_summary"] = E.summarize_personal(pe)
        say("personal layer (online):\n%s" % res["personal_layer_summary"].to_string(index=False))

    # 8. final model on all included participants; bands from 5-fold out-of-fold residuals
    all_k = list(range(C.MAX_H))
    # The fold models are the same participant-grouped folds as the evaluation (D-26): replay participant p is
    # predicted only by the fold model trained without p. Each fold's bands come from out-of-fold residuals of the
    # participants it was trained on, never from the held-out fold.
    fold_of = np.array([folds[p] for p in samples.pid])
    resid = np.full(samples.y.shape, np.nan)
    cgm_resid = np.full(samples.y.shape, np.nan)
    fold_fits = {}
    for f in sorted(set(folds.values())):
        tr, te = samples.subset(fold_of != f), samples.subset(fold_of == f)
        m_f, fill = fit_horizons(tr, feature_set, all_k)
        c_f = fit_cgm_only(tr, all_k)
        resid[fold_of == f] = te.y - predict_horizons(m_f, te, feature_set, fill)
        cgm_resid[fold_of == f] = (te.y + te.last[:, None]) - predict_cgm_only(c_f, te)
        fold_fits[f] = (m_f, c_f, sorted(set(tr.pid.tolist())))
    bands = band_quantiles(resid, samples.meal_known)
    models, _ = fit_horizons(samples, feature_set, all_k)
    components = {"full": {"models": models, "bands": bands, "cgm_models": fit_cgm_only(samples, all_k),
                           "cgm_bands": band_quantiles(cgm_resid, samples.meal_known),
                           "training_participants": included}}
    for f, (m_f, c_f, pids) in fold_fits.items():
        keep = fold_of != f
        components[f"fold{f}"] = {"models": m_f, "bands": band_quantiles(resid[keep], samples.meal_known[keep]),
                                  "cgm_models": c_f, "cgm_bands": band_quantiles(cgm_resid[keep], samples.meal_known[keep]),
                                  "training_participants": pids}
    er = res["eval_results"]
    meta = {
        "training_participants": included, "excluded_participants": excluded,
        "dataset": "BIG IDEAs Lab Glycemic Variability and Wearable Device Data v1.1.3 (PhysioNet)",
        "n_origins": int(len(samples)), "simulate_method": simulate_method, "meals_help": meals_help,
        "cohort": cohort,
        "eval_headline": er[er.horizon_min.isin([30, 60, 120])].to_dict(orient="records"),
        "status": "DRAFT: numbers not approved for judge-facing use",
    }
    res["artifact_dir"] = export_bundle(out / C.VERSION, components, feature_set, folds, meta)
    say(f"artifact -> {res['artifact_dir']}")

    # 9. replay tables: included participants only (D-37: participants excluded under D-20 are not replayed)
    rc, rm = replay_tables(cgm, meals, included)
    rc["excluded_from_training"] = rc["participant_id"].isin(excluded)
    rm["excluded_from_training"] = rm["participant_id"].isin(excluded)
    res.update(replay_cgm=rc, replay_meals=rm)
    say(f"replay: {len(rc)} CGM rows, {len(rm)} meals")

    # 10. write CSVs (participant ids stay zero-padded strings)
    for name, df in res.items():
        if isinstance(df, pd.DataFrame):
            df.to_csv(out / f"{name}.csv", index=False)
    summary = {k: v for k, v in res.items() if isinstance(v, (bool, str, dict, list)) and k != "folds"}
    summary.update(folds=folds, included=included, excluded=excluded, seconds=round(time.time() - t0, 1))
    (out / "run_summary.json").write_text(json.dumps(summary, indent=2, default=str))
    say("done")
    return res
