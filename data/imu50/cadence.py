"""Per-minute walking cadence estimated from a wrist accelerometer, and the hourly comparison with ActiGraph METs.

The estimator is a heuristic, not a validated step counter: the dominant periodicity of the acceleration magnitude in
a minute. A minute counts as walking-like when the wrist moves (SD of the magnitude above MOVING_SD_G) and most of the
0.6-3.5 Hz power sits in one narrow peak. A peak at 1.2-3.0 Hz is read as the step frequency (cadence = 60 x f); a
peak at 0.6-1.2 Hz with a clear second harmonic is read as arm swing at stride frequency (cadence = 120 x f).
Bands are Gummi's (gummi_activity, Tudor-Locke et al. 2019): light 1-99, moderate 100-129, vigorous 130+ steps/min.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

FS = 128                      # IMU50 accelerometer sampling rate (Hz)
MOVING_SD_G = 0.05            # SD of the magnitude (g) above which the wrist is moving
PEAK_SHARE_MIN = 0.25         # share of 0.6-3.5 Hz power within +-0.15 Hz of the peak for a periodic minute
HARMONIC_MIN = 0.5            # second harmonic power relative to the peak, for the arm-swing reading
SEGMENT = 10 * FS             # Welch segment: 10 s gives 0.1 Hz resolution
CADENCE_BANDS = [("light", 1, 99), ("moderate", 100, 129), ("vigorous", 130, 10_000)]


def band_of(cadence_spm: float) -> str:
    if cadence_spm is None or not np.isfinite(cadence_spm) or cadence_spm <= 0:
        return "none"
    for name, lo, hi in CADENCE_BANDS:
        if lo <= cadence_spm <= hi:
            return name
    return "vigorous"


def _welch(x: np.ndarray, fs: int = FS, seg: int = SEGMENT):
    n = len(x) // seg
    if n == 0:
        return np.zeros(0), np.zeros(0)
    w = np.hanning(seg)
    segs = x[: n * seg].reshape(n, seg)
    segs = (segs - segs.mean(axis=1, keepdims=True)) * w
    p = (np.abs(np.fft.rfft(segs, axis=1)) ** 2).mean(axis=0)
    f = np.fft.rfftfreq(seg, 1 / fs)
    return f, p


def minute_features(acc: np.ndarray, fs: int = FS) -> dict:
    """acc: (n, 3) accelerometer in g for one minute. Returns sd, peak frequency, peak share, cadence, walking flag."""
    if len(acc) < fs * 30:
        return {"sd_g": np.nan, "peak_hz": np.nan, "peak_share": np.nan, "cadence_spm": np.nan, "walking": False}
    mag = np.sqrt((acc.astype(float) ** 2).sum(axis=1))
    sd = float(mag.std())
    f, p = _welch(mag, fs)
    band = (f >= 0.6) & (f <= 3.5)
    if sd < MOVING_SD_G or not band.any() or p[band].sum() <= 0:
        return {"sd_g": sd, "peak_hz": np.nan, "peak_share": np.nan, "cadence_spm": 0.0, "walking": False}
    fb, pb = f[band], p[band]
    k = int(np.argmax(pb))
    peak = float(fb[k])
    share = float(pb[np.abs(fb - peak) <= 0.15].sum() / pb.sum())
    cadence = np.nan
    if 1.2 <= peak <= 3.0:
        cadence = 60.0 * peak
    elif 0.6 <= peak < 1.2:
        h = np.abs(f - 2 * peak) <= 0.15
        if h.any() and p[h].max() >= HARMONIC_MIN * pb[k]:
            cadence = 120.0 * peak
    walking = bool(share >= PEAK_SHARE_MIN and np.isfinite(cadence))
    return {"sd_g": sd, "peak_hz": peak, "peak_share": share, "cadence_spm": cadence if walking else 0.0,
            "walking": walking}


def hourly_check(minutes: pd.DataFrame, scoring: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """Join per-minute cadence bands with the hourly ActiGraph METs.

    minutes: subject, minute (Timestamp), cadence_spm, walking. scoring: subject, Timestamp (hour start), METs.
    Returns per-hour rows and a summary: Spearman between moderate-or-faster minutes and METs, and mean METs by the
    number of moderate-or-faster minutes in the hour.
    """
    m = minutes.copy()
    m["hour"] = m["minute"].dt.floor("h")
    m["band"] = [band_of(c) if w else "none" for c, w in zip(m["cadence_spm"], m["walking"])]
    agg = m.groupby(["subject", "hour"]).agg(
        minutes=("minute", "count"), walking_min=("walking", "sum"),
        light_min=("band", lambda b: int((b == "light").sum())),
        moderate_min=("band", lambda b: int((b == "moderate").sum())),
        vigorous_min=("band", lambda b: int((b == "vigorous").sum()))).reset_index()
    sc = scoring.rename(columns={"Timestamp": "hour"})[["subject", "hour", "METs"]]
    h = agg.merge(sc, on=["subject", "hour"], how="inner")
    h = h[h["minutes"] >= 50]                                 # full hours only
    h["moderate_plus_min"] = h["moderate_min"] + h["vigorous_min"]
    rho = float(h["moderate_plus_min"].rank().corr(h["METs"].rank())) if len(h) > 3 else float("nan")
    groups = pd.cut(h["moderate_plus_min"], [-1, 0, 9, 1_000], labels=["0", "1-9", "10+"])
    by = h.groupby(groups, observed=False)["METs"].agg(["count", "mean"]).round(2)
    summary = {
        "subjects": sorted(h["subject"].unique().tolist()), "hours": int(len(h)),
        "spearman_moderate_plus_minutes_vs_METs": None if np.isnan(rho) else round(rho, 2),
        "mean_METs_by_moderate_plus_minutes": {
            str(k): {"hours": int(v["count"]), "mean_METs": None if pd.isna(v["mean"]) else float(v["mean"])}
            for k, v in by.iterrows()},
        "walking_minutes_by_band": {b: int(h[f"{b}_min"].sum()) for b in ("light", "moderate", "vigorous")},
    }
    return h, summary
