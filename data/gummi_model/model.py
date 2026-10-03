"""gummi_model inference: CONTRACT.md section 8. Pure Python + numpy + pandas + saved coefficients.

    from gummi_model import GlucoseModel, UserContext
    model = GlucoseModel.load(artifact_dir)          # full model, 5 fold models, participant-to-fold map (D-26)
    m = model.for_user(user_id)                      # the fold model that never saw a replay participant, else full
    ctx = UserContext(user_id, profile, cgm_df, meals_df, walks_df, personal)   # cgm_df: confirmed only
    m.forecast(ctx, now, 120); m.cgm_only_forecast(ctx, now, 120); m.grade(prediction, confirmed_df)

Data frames (times may be tz-aware or naive; naive means UTC):
    cgm_df:   t, glucose_mg_dl
    meals_df: eaten_at, carbs_g, sugar_g, fiber_g, protein_g, fat_g   (meal totals)
    walks_df: started_at, ended_at, minutes, intensity                 (optional)
Times in returned points are ISO 8601 UTC strings ("...+00:00").
Every estimate and forecast is an estimate: callers label it "Gummi's estimate".
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import numpy as np
import pandas as pd

from . import config as C
from . import kernels
from .features import add_derived, base_features, meal_features
from .grading import grade as _grade
from .personal import update_personal as _update_personal
from .walk import walk_effect as _walk_effect


@dataclass
class UserContext:
    user_id: str
    profile: dict = field(default_factory=dict)
    cgm_df: pd.DataFrame | None = None
    meals_df: pd.DataFrame | None = None
    walks_df: pd.DataFrame | None = None
    personal: dict | None = None


def _utc(ts) -> pd.Timestamp:
    t = pd.Timestamp(ts)
    return t.tz_localize("UTC") if t.tzinfo is None else t.tz_convert("UTC")


def _to_min(series) -> np.ndarray:
    s = pd.to_datetime(pd.Series(series), utc=True)
    return s.to_numpy(dtype="datetime64[s]").astype(np.int64) / 60.0 if len(s) else np.zeros(0)


def _iso(minutes: float) -> str:
    return datetime.fromtimestamp(minutes * 60.0, tz=timezone.utc).isoformat()


def _round1(x: float) -> float:
    return float(np.round(x, 1))


def _participant(user_id) -> str:
    """"p_012", "012" or 12 -> "012"."""
    s = str(user_id).strip()
    if s.lower().startswith("p_"):
        s = s[2:]
    return s.zfill(3) if s.isdigit() else s


class GlucoseModel:
    def __init__(self, arrays: dict, meta: dict, component: str = "full"):
        self.x_mean = arrays["x_mean"]
        self.x_scale = arrays["x_scale"]
        self.coef = arrays["coef"]
        self.intercept = arrays["intercept"]
        self.bands = arrays["bands"]          # (2 windows [quiet, meal], 2 quantiles, H)
        # CGM-only linear baseline (D-33), absolute glucose per horizon; None in old artifacts
        self.cgm_x_mean = arrays.get("cgm_x_mean")
        self.cgm_x_scale = arrays.get("cgm_x_scale")
        self.cgm_coef = arrays.get("cgm_coef")
        self.cgm_intercept = arrays.get("cgm_intercept")
        self.cgm_bands = arrays.get("cgm_bands")
        self.meta = meta
        self.component = component
        comp = (meta.get("components") or {}).get(component, {})
        self.fold = comp.get("fold")
        self.training_participants = list(comp.get("training_participants") or meta.get("training_participants") or [])
        self.feature_set = meta["feature_set"]
        self.max_h = self.coef.shape[0]
        self.meal_cols = list(meta.get("meal_cols", C.INPUT_MACROS))
        self._folds: dict[int, "GlucoseModel"] = {}
        self._fold_map: dict[str, int] = {_participant(k): int(v) for k, v in (meta.get("fold_map") or {}).items()}

    # ------------------------------------------------------------------ loading
    @classmethod
    def load(cls, artifact_dir: str | Path) -> "GlucoseModel":
        """The full model; its fold models and the participant-to-fold map come along (D-26)."""
        artifact_dir = Path(artifact_dir)
        with np.load(artifact_dir / "model.npz") as z:
            raw = {k: z[k] for k in z.files}
        meta = json.loads((artifact_dir / "meta.json").read_text())
        comps = sorted({k.split("__")[0] for k in raw if "__" in k})
        if not comps:                                               # single-model artifact (before v1.1)
            return cls(raw, meta)
        part = lambda c: {k.split("__", 1)[1]: v for k, v in raw.items() if k.startswith(c + "__")}
        full = cls(part("full"), meta, "full")
        for c in comps:
            if c.startswith("fold"):
                fm = cls(part(c), meta, c)
                full._folds[fm.fold] = fm
        return full

    @classmethod
    def from_fit(cls, models: dict, bands: np.ndarray, feature_set: str, meta: dict | None = None,
                 cgm_models: dict | None = None, cgm_bands: np.ndarray | None = None) -> "GlucoseModel":
        """Build an in-memory model from train.fit_horizons (and fit_cgm_only) output, for evaluation."""
        from .features import feature_names
        H = len(models)
        stack = lambda ms, i: np.stack([ms[k][i] for k in range(H)])
        arrays = {"x_mean": stack(models, 0), "x_scale": stack(models, 1), "coef": stack(models, 2),
                  "intercept": np.array([models[k][3] for k in range(H)]), "bands": bands}
        if cgm_models is not None:
            arrays.update({"cgm_x_mean": stack(cgm_models, 0), "cgm_x_scale": stack(cgm_models, 1),
                           "cgm_coef": stack(cgm_models, 2),
                           "cgm_intercept": np.array([cgm_models[k][3] for k in range(H)]),
                           "cgm_bands": cgm_bands if cgm_bands is not None else np.zeros((2, 2, H))})
        m = dict(meta or {})
        m.update({"feature_set": feature_set, "feature_names": feature_names(feature_set, C.MEAL_COLS),
                  "meal_cols": C.MEAL_COLS})
        return cls(arrays, m)

    @property
    def version(self) -> str:
        v = self.meta.get("version", C.VERSION)
        return v if self.fold is None else f"{v}_fold{self.fold}"

    # ------------------------------------------------------------------ out-of-sample replay (D-26)
    def fold_of(self, user_id) -> int | None:
        """Fold of a replay participant ("p_012"), None for teammates, the sandbox and excluded participants."""
        return self._fold_map.get(_participant(user_id)) if str(user_id).lower().startswith("p_") or str(user_id).isdigit() else None

    def for_user(self, user_id) -> "GlucoseModel":
        """The fold model that never saw this replay participant; the full model for everyone else."""
        f = self.fold_of(user_id)
        if f is None or f not in self._folds:
            return self
        return self._folds[f]

    # ------------------------------------------------------------------ core
    def _confirmed(self, ctx: UserContext, now) -> tuple[np.ndarray, np.ndarray]:
        if ctx.cgm_df is None or len(ctx.cgm_df) == 0:
            raise ValueError("no confirmed CGM readings in context")
        t = _to_min(ctx.cgm_df["t"])
        v = ctx.cgm_df["glucose_mg_dl"].to_numpy(dtype=float)
        order = np.argsort(t)
        t, v = t[order], v[order]
        keep = (t <= _to_min([now])[0]) & ~np.isnan(v)
        if not keep.any():
            raise ValueError("no confirmed readings at or before now")
        return t[keep], v[keep]

    def _local_hour(self, ctx: UserContext, minutes: float) -> float:
        tz = (ctx.profile or {}).get("timezone")
        dt = datetime.fromtimestamp(minutes * 60.0, tz=timezone.utc)
        if tz:
            try:
                dt = dt.astimezone(ZoneInfo(tz))
            except Exception:
                pass
        return dt.hour + dt.minute / 60.0

    def _meals(self, ctx: UserContext, now_min: float, extra_meals=None) -> tuple[np.ndarray, np.ndarray]:
        """Meals the model may use: logged meals eaten at or before now, plus simulated extra meals."""
        frames = []
        if ctx.meals_df is not None and len(ctx.meals_df):
            logged = ctx.meals_df.copy()
            logged = logged[_to_min(logged["eaten_at"]) <= now_min + 1e-6]
            if len(logged):
                frames.append(logged)
        if extra_meals is not None and len(extra_meals):
            frames.append(pd.DataFrame(extra_meals))
        if not frames:
            return np.zeros(0), np.zeros((0, len(self.meal_cols)))
        m = pd.concat(frames, ignore_index=True)
        e = _to_min(m["eaten_at"])
        for c in C.INPUT_MACROS:
            m[c] = pd.to_numeric(m[c], errors="coerce") if c in m.columns else 0.0
        m = add_derived(m, np.array([self._local_hour(ctx, x) for x in e]))
        A = np.column_stack([m[c].to_numpy(dtype=float) for c in self.meal_cols])
        return e, np.nan_to_num(A)

    def _origin(self, ctx: UserContext, now):
        t, v = self._confirmed(ctx, now)
        t0, last = t[-1], v[-1]
        hist = v[-C.HISTORY:]
        if len(hist) < C.HISTORY:                       # short history: pad with the earliest value
            hist = np.concatenate([np.full(C.HISTORY - len(hist), hist[0]), hist])
        mean24 = v[t >= t0 - C.MEAN_LOOKBACK_MIN].mean()
        base = base_features(hist[None, :], [self._local_hour(ctx, t0)], [mean24])[0]
        return t0, last, base

    def _predict(self, ctx: UserContext, now, ks: np.ndarray, extra_meals=None, extra_walks=None,
                 apply_personal: bool = True):
        """Absolute predictions, meal contribution, band offsets for horizon steps ks (1-based)."""
        t0, last, base = self._origin(ctx, now)
        now_min = _to_min([now])[0]
        ks = np.asarray(ks, dtype=int)
        kk = np.clip(ks, 1, self.max_h) - 1
        e, A = self._meals(ctx, now_min, extra_meals)
        H = len(ks)
        if self.feature_set != "cgm":
            age = t0 - e                                              # minutes from each meal to t0
            age_known = np.where(age <= C.MEAL_LOOKBACK_MIN, age, np.nan)[None, :]
            meal = meal_features(age_known, A[None, :, :], kk + 1, self.meal_cols)[0]
            nomeal = meal_features(np.zeros((1, 0)), np.zeros((1, 0, len(self.meal_cols))), kk + 1, self.meal_cols)[0]
            X = np.column_stack([np.repeat(base[None, :], H, 0), meal])
            X0 = np.column_stack([np.repeat(base[None, :], H, 0), nomeal])
        else:
            X = X0 = np.repeat(base[None, :], H, 0)
        z = (X - self.x_mean[kk]) / self.x_scale[kk]
        z0 = (X0 - self.x_mean[kk]) / self.x_scale[kk]
        pred = np.einsum("hf,hf->h", z, self.coef[kk]) + self.intercept[kk]
        pred0 = np.einsum("hf,hf->h", z0, self.coef[kk]) + self.intercept[kk]
        contrib = pred - pred0                                   # what the logged meals add
        personal = (ctx.personal or {}) if apply_personal else {}
        factor = float(personal.get("carb_factor", 1.0))
        offset = float(personal.get("offset_mg_dl", 0.0))
        delta = pred0 + factor * contrib + offset
        # walks: shave the meal-driven rise after the walk starts (never below the no-meal path)
        if extra_walks is not None or (ctx.walks_df is not None and len(ctx.walks_df)):
            walks = []
            for src in (ctx.walks_df, pd.DataFrame(extra_walks) if extra_walks is not None else None):
                if src is not None and len(src):
                    walks.append(src)
            w = pd.concat(walks, ignore_index=True) if walks else pd.DataFrame()
            tgt = t0 + C.STEP_MIN * (kk + 1)
            c = np.clip(factor * contrib, 0, None)
            if len(w) and c.max() > 0:
                for _, row in w.iterrows():
                    start = _to_min([row["started_at"]])[0]
                    eff = _walk_effect(self.meta, ctx, float(row.get("minutes", 10)), row.get("intensity", "moderate"))
                    drop = min(float(eff["forecast_peak_drop_mg_dl"]),
                               C.WALK["max_fraction_of_meal_effect"] * float(c.max()))
                    delta = delta - np.where(tgt >= start, drop * c / c.max(), 0.0)
        # bands: meal window if a known meal ate 0-180 min before the target
        tgt = t0 + C.STEP_MIN * (kk + 1)
        since = tgt[:, None] - e[None, :] if len(e) else np.zeros((H, 0))
        in_meal = ((since >= 0) & (since <= C.MEAL_WINDOW_MIN)).any(axis=1) if len(e) else np.zeros(H, bool)
        w_idx = in_meal.astype(int)
        lo = self.bands[w_idx, 0, kk]
        hi = self.bands[w_idx, 1, kk]
        beyond = np.clip(ks - self.max_h, 0, None)              # widen past the trained range
        lo = lo - beyond * 1.0
        hi = hi + beyond * 1.0
        return t0, last, tgt, last + delta, last + delta + lo, last + delta + hi, factor * contrib

    def _points(self, tgt, val, lo, hi, kind) -> list[dict]:
        return [{"t": _iso(t), "glucose_mg_dl": _round1(g), "band_low_mg_dl": _round1(min(a, g)),
                 "band_high_mg_dl": _round1(max(b, g)), "kind": kind}
                for t, g, a, b in zip(tgt, val, lo, hi)]

    # ------------------------------------------------------------------ contract API
    def estimate_gap(self, ctx: UserContext, now) -> list[dict]:
        """BandPoints from the step after data_through up to now (5-minute grid anchored at data_through)."""
        t, _ = self._confirmed(ctx, now)
        n = int(np.floor((_to_min([now])[0] - t[-1]) / C.STEP_MIN + 1e-9))
        if n <= 0:
            return []
        t0, last, tgt, val, lo, hi, _ = self._predict(ctx, now, np.arange(1, n + 1))
        return self._points(tgt, val, lo, hi, "estimate")

    def _forecast_arrays(self, ctx: UserContext, now, minutes: int, extra_meals=None, extra_walks=None):
        t, _ = self._confirmed(ctx, now)
        now_min = _to_min([now])[0]
        k_first = int(np.floor((now_min - t[-1]) / C.STEP_MIN + 1e-9)) + 1
        k_last = int(np.floor((now_min + minutes - t[-1]) / C.STEP_MIN + 1e-9))
        if k_last < k_first:
            return None
        _, _, tgt, val, lo, hi, _ = self._predict(ctx, now, np.arange(k_first, k_last + 1), extra_meals, extra_walks)
        return tgt, val, lo, hi

    def forecast(self, ctx: UserContext, now, minutes: int = 120, extra_meals=None, extra_walks=None) -> list[dict]:
        """BandPoints after now out to now + minutes."""
        arr = self._forecast_arrays(ctx, now, minutes, extra_meals, extra_walks)
        return [] if arr is None else self._points(*arr, "forecast")

    def gummi_view(self, ctx: UserContext, now) -> dict:
        """Gummi's estimate for now (always labeled as an estimate in the UI)."""
        t, v = self._confirmed(ctx, now)
        now_min = _to_min([now])[0]
        gap = self.estimate_gap(ctx, now)
        if gap:
            p = gap[-1]
            vals = [q["glucose_mg_dl"] for q in gap[-3:]]
            slope = (vals[-1] - vals[0]) / (C.STEP_MIN * (len(vals) - 1)) if len(vals) > 1 else 0.0
            g, lo, hi = p["glucose_mg_dl"], p["band_low_mg_dl"], p["band_high_mg_dl"]
        else:
            g = lo = hi = float(v[-1])
            slope = float((v[-1] - v[-3]) / (t[-1] - t[-3])) if len(v) >= 3 and t[-1] > t[-3] else 0.0
        th = C.TREND_THRESHOLDS
        trend = ("rising_fast" if slope >= th["rising_fast"] else "rising" if slope >= th["rising"]
                 else "falling_fast" if slope <= th["falling_fast"] else "falling" if slope <= th["falling"] else "flat")
        width = hi - lo
        conf = "high" if width < C.CONFIDENCE_BAND["high"] else "medium" if width <= C.CONFIDENCE_BAND["medium"] else "low"
        return {"glucose_mg_dl": _round1(g), "band_low_mg_dl": _round1(lo), "band_high_mg_dl": _round1(hi),
                "trend": trend, "trend_mg_dl_per_min": _round1(slope), "as_of": _iso(now_min),
                "minutes_since_confirmed": int(round(now_min - t[-1])), "confidence": conf}

    def simulate(self, ctx: UserContext, now, items_macros, eat_at=None, minutes: int = 120) -> dict:
        """Two curves (without and with the food), peak, method, and simple alternatives.

        items_macros: a dict of totals or a list of item dicts with carbs_g, sugar_g, fiber_g, protein_g, fat_g.
        method "model": the meal goes through the model's meal features (used when the meal ablation
        showed a gain). method "breakfast_response": the person's standardized-breakfast rise per gram of
        carbs (or the cohort median) shapes the added curve, and the card must say so.
        """
        items = [items_macros] if isinstance(items_macros, dict) else list(items_macros)
        totals = {c: float(sum(float(i.get(c) or 0.0) for i in items)) for c in C.INPUT_MACROS}
        now_min = _to_min([now])[0]
        eat_min = _to_min([eat_at])[0] if eat_at is not None else now_min
        method = self.meta.get("simulate_method", "model")
        base = self._forecast_arrays(ctx, now, minutes)
        if base is None:
            raise ValueError("nothing to forecast")
        tgt, b_val, b_lo, b_hi = base
        walk_eff = _walk_effect(self.meta, ctx, 10, "moderate")

        def with_food(scale: float, walk: bool = False):
            if method == "model":
                meal = {"eaten_at": _iso(eat_min), **{c: totals[c] * scale for c in C.INPUT_MACROS}}
                walks = [{"started_at": _iso(eat_min), "minutes": 10, "intensity": "moderate"}] if walk else None
                return self._forecast_arrays(ctx, now, minutes, extra_meals=[meal], extra_walks=walks)[1:]
            # breakfast_response: personal (or cohort) rise per gram of carbs on the carb kernel shape
            per_g = float((ctx.personal or {}).get("breakfast_rise_per_g")
                          or self.meta.get("cohort", {}).get("breakfast_rise_per_g_median", 0.0))
            factor = float((ctx.personal or {}).get("carb_factor", 1.0))
            rise = per_g * totals["carbs_g"] * scale * factor
            shape = kernels.rate(tgt - eat_min, C.KERNEL_PEAK_MIN["carbs_g"])
            add = rise * shape
            if walk:
                add = np.clip(add - min(walk_eff["forecast_peak_drop_mg_dl"],
                                        C.WALK["max_fraction_of_meal_effect"] * rise) * shape, 0.0, None)
            return b_val + add, b_lo + add, b_hi + add

        def peak(val):
            mask = tgt >= eat_min
            if not mask.any():
                mask = np.ones_like(tgt, bool)
            i = int(np.argmax(np.where(mask, val, -np.inf)))
            return _round1(val[i]), _iso(tgt[i])

        f_val, f_lo, f_hi = with_food(1.0)
        pk, pk_at = peak(f_val)
        half_pk, _ = peak(with_food(0.5)[0])
        walk_pk, _ = peak(with_food(1.0, walk=True)[0])
        base_pk, _ = peak(b_val)
        high = float((ctx.profile or {}).get("high_line_mg_dl", 140.0))
        alts = [{"label": "Half portion", "peak_mg_dl": half_pk},
                {"label": "Walk 10 minutes after", "peak_mg_dl": walk_pk, "effect_source": walk_eff["effect_source"]}]
        verdict = ("go" if pk < high else "go_with_tweak" if any(a["peak_mg_dl"] < high for a in alts) else "wait")
        return {"eat_at": _iso(eat_min),
                "baseline_curve": self._points(tgt, b_val, b_lo, b_hi, "forecast"),
                "with_food_curve": self._points(tgt, f_val, f_lo, f_hi, "forecast"),
                "peak_mg_dl": pk, "peak_at": pk_at, "without_food_peak_mg_dl": base_pk,
                "meal_effect_mg_dl": _round1(pk - base_pk), "verdict": verdict, "alternatives": alts,
                "method": method}

    def _cgm_only_arrays(self, ctx: UserContext, now, ks: np.ndarray):
        if self.cgm_coef is None:
            raise ValueError("this artifact has no CGM-only models (export it with train.export_bundle)")
        t, v = self._confirmed(ctx, now)
        t0 = t[-1]
        hist = v[-C.HISTORY:]
        if len(hist) < C.HISTORY:
            hist = np.concatenate([np.full(C.HISTORY - len(hist), hist[0]), hist])
        ks = np.asarray(ks, dtype=int)
        kk = np.clip(ks, 1, self.max_h) - 1
        z = (hist[None, :] - self.cgm_x_mean[kk]) / self.cgm_x_scale[kk]
        val = np.einsum("hf,hf->h", z, self.cgm_coef[kk]) + self.cgm_intercept[kk]
        tgt = t0 + C.STEP_MIN * (kk + 1)
        e, _ = self._meals(ctx, _to_min([now])[0])
        since = tgt[:, None] - e[None, :] if len(e) else np.zeros((len(ks), 0))
        w_idx = (((since >= 0) & (since <= C.MEAL_WINDOW_MIN)).any(axis=1) if len(e) else np.zeros(len(ks), bool)).astype(int)
        beyond = np.clip(ks - self.max_h, 0, None)
        lo = val + self.cgm_bands[w_idx, 0, kk] - beyond * 1.0
        hi = val + self.cgm_bands[w_idx, 1, kk] + beyond * 1.0
        return tgt, val, lo, hi

    def cgm_only_forecast(self, ctx: UserContext, now, minutes: int = 120, include_gap: bool = False) -> list[dict]:
        """The CGM-only linear baseline (D-33) as BandPoints after now out to now + minutes, from the same fold as
        this model. include_gap=True also returns the points from data_through to now (kind "estimate"), which a
        nowcast grade needs."""
        t, _ = self._confirmed(ctx, now)
        now_min = _to_min([now])[0]
        k_first = 1 if include_gap else int(np.floor((now_min - t[-1]) / C.STEP_MIN + 1e-9)) + 1
        k_last = int(np.floor((now_min + minutes - t[-1]) / C.STEP_MIN + 1e-9))
        if k_last < k_first:
            return []
        tgt, val, lo, hi = self._cgm_only_arrays(ctx, now, np.arange(k_first, k_last + 1))
        pts = self._points(tgt, val, lo, hi, "forecast")
        for p, tm in zip(pts, tgt):
            if tm <= now_min + 1e-6:
                p["kind"] = "estimate"
        return pts

    def grade(self, prediction: dict, confirmed_df: pd.DataFrame, overlay_walks=None) -> dict:
        """Gummi, CGM-only and last-value errors over the closed window. overlay_walks: phone walks shown over
        replayed glucose (D-28); a window they overlap gets walk_effect_graded false."""
        return _grade(prediction, confirmed_df, overlay_walks=overlay_walks)

    def update_personal(self, ctx: UserContext, grades: list[dict]) -> dict:
        return _update_personal(self, ctx, grades)

    def walk_effect(self, ctx: UserContext, minutes: float, intensity: str) -> dict:
        return _walk_effect(self.meta, ctx, minutes, intensity)
