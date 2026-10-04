"""Grade a stored prediction against confirmed readings: Gummi, CGM-only and the last-value guess (v1.1)."""
from __future__ import annotations

from datetime import datetime, timezone

import numpy as np
import pandas as pd

from .config import MATCH_TOL_MIN


def _utc(ts) -> pd.Timestamp:
    t = pd.Timestamp(ts)
    return t.tz_localize("UTC") if t.tzinfo is None else t.tz_convert("UTC")


def _match(curve: pd.DataFrame, cgm: pd.DataFrame) -> pd.DataFrame:
    return pd.merge_asof(curve.sort_values("t"), cgm[["t", "glucose_mg_dl"]].rename(columns={"glucose_mg_dl": "actual"}),
                         on="t", direction="nearest", tolerance=pd.Timedelta(minutes=MATCH_TOL_MIN))


def _curve(points, ws, we) -> pd.DataFrame:
    c = pd.DataFrame(points or [])
    if c.empty:
        return c
    c["t"] = pd.to_datetime(c["t"], utc=True).astype("datetime64[ns, UTC]")
    return c[(c["t"] >= ws) & (c["t"] <= we)]


def _overlaps(walks, ws, we) -> bool:
    """True when any walk (started_at, ended_at or minutes) overlaps the window."""
    if walks is None:
        return False
    w = pd.DataFrame(walks) if not isinstance(walks, pd.DataFrame) else walks
    for _, r in w.iterrows():
        start = _utc(r["started_at"])
        end = _utc(r["ended_at"]) if pd.notna(r.get("ended_at")) else start + pd.Timedelta(minutes=float(r.get("minutes") or 0))
        if start <= we and end >= ws:
            return True
    return False


def grade(prediction: dict, confirmed_df: pd.DataFrame, overlay_walks=None, min_points: int = 3) -> dict:
    """Grade fields (CONTRACT section 3, v1.1): Gummi, CGM-only and last-value errors over the closed window.

    prediction: Prediction dict with predicted_curve (BandPoints), window_start, window_end, kind, about,
        predicted_peak_mg_dl, last_value_peak_mg_dl (the last confirmed reading at made_at), cgm_only_peak_mg_dl,
        and cgm_only_curve (BandPoints from cgm_only_forecast at made_at; keep it with the prediction in hot
        state, it is needed for cgm_only_mae_mg_dl). baseline_peak_mg_dl from before v1.1 is read as last value.
    confirmed_df: t, glucose_mg_dl (confirmed readings that arrived later).
    overlay_walks: phone walks shown over replayed glucose (D-28): started_at plus ended_at or minutes. A window
        they overlap gets walk_effect_graded false; accuracy tables leave it out.
    Extra keys: status, gummi_bias_mg_dl (feeds the personal layer), actual_peak_mg_dl, actual_peak_at,
    gummi_beats_cgm_only (drives the proud mood), gummi_beats_last_value.
    """
    head = {"prediction_id": prediction.get("prediction_id"), "kind": prediction.get("kind"),
            "graded_at": datetime.now(timezone.utc).isoformat()}
    if not prediction.get("predicted_curve") or confirmed_df is None or len(confirmed_df) == 0:
        return {**head, "points": 0, "status": "insufficient_data", "message": "Not enough confirmed readings yet."}
    pc = pd.DataFrame(prediction["predicted_curve"])
    pc["t"] = pd.to_datetime(pc["t"], utc=True).astype("datetime64[ns, UTC]")
    ws = _utc(prediction["window_start"]) if prediction.get("window_start") else pc["t"].min()
    we = _utc(prediction["window_end"]) if prediction.get("window_end") else pc["t"].max()
    cgm = confirmed_df.assign(t=pd.to_datetime(confirmed_df["t"], utc=True).astype("datetime64[ns, UTC]")).sort_values("t")
    m = _match(_curve(prediction["predicted_curve"], ws, we), cgm).dropna(subset=["actual"])
    if len(m) < min_points:
        return {**head, "points": int(len(m)), "status": "insufficient_data",
                "message": "Not enough confirmed readings yet."}
    lv = prediction.get("last_value_peak_mg_dl", prediction.get("baseline_peak_mg_dl"))
    last_value = float(lv)
    actual_peak_row = m.loc[m["actual"].idxmax()]
    actual_peak = float(actual_peak_row["actual"])
    pred_peak = float(prediction.get("predicted_peak_mg_dl") or m["glucose_mg_dl"].max())
    gummi_mae = float((m["glucose_mg_dl"] - m["actual"]).abs().mean())
    last_value_mae = float((last_value - m["actual"]).abs().mean())
    cgm_only_mae, cgm_peak = None, prediction.get("cgm_only_peak_mg_dl")
    cc = _curve(prediction.get("cgm_only_curve"), ws, we)
    if not cc.empty:
        cm = _match(cc, cgm).dropna(subset=["actual"])
        if len(cm) >= min_points:
            cgm_only_mae = float((cm["glucose_mg_dl"] - cm["actual"]).abs().mean())
        if cgm_peak is None:
            cgm_peak = float(cc["glucose_mg_dl"].max())
    inside = (m["actual"] >= m["band_low_mg_dl"]) & (m["actual"] <= m["band_high_mg_dl"])
    walk_graded = not _overlaps(overlay_walks, ws, we)
    out = {
        **head,
        "status": "graded",
        "points": int(len(m)),
        "gummi_mae_mg_dl": round(gummi_mae, 1),
        "cgm_only_mae_mg_dl": None if cgm_only_mae is None else round(cgm_only_mae, 1),
        "last_value_mae_mg_dl": round(last_value_mae, 1),
        "gummi_peak_error_mg_dl": round(abs(pred_peak - actual_peak), 1),
        "within_band_pct": round(100.0 * float(inside.mean()), 1),
        "walk_effect_graded": walk_graded,
        "gummi_bias_mg_dl": round(float((m["actual"] - m["glucose_mg_dl"]).mean()), 1),
        "actual_peak_mg_dl": round(actual_peak, 1),
        "actual_peak_at": actual_peak_row["t"].isoformat(),
        "gummi_beats_cgm_only": None if cgm_only_mae is None else bool(gummi_mae < cgm_only_mae),
        "gummi_beats_last_value": bool(gummi_mae < last_value_mae),
    }
    if prediction.get("kind") == "meal":
        about = prediction.get("about") or "that meal"
        cgm_txt = f"CGM-only said {float(cgm_peak):.0f}, " if cgm_peak is not None else ""
        out["message"] = (f"I predicted {pred_peak:.0f} for {about}. It was {actual_peak:.0f}. "
                          f"{cgm_txt}last value said {last_value:.0f}.")
    else:
        cgm_txt = f"CGM-only was within {int(np.ceil(cgm_only_mae))}, " if cgm_only_mae is not None else ""
        out["message"] = (f"I was within {int(np.ceil(gummi_mae))} mg/dL. "
                          f"{cgm_txt}last value within {int(np.ceil(last_value_mae))}.")
    if not walk_graded:
        out["message"] += " Walk effect not graded (replayed data)."
    return out
