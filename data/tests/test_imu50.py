"""IMU50 cadence estimator on synthetic wrist signals, and the hourly join."""
import numpy as np
import pandas as pd

from imu50.cadence import band_of, hourly_check, minute_features

FS = 128
T = np.arange(60 * FS) / FS
RNG = np.random.default_rng(0)


def _acc(mag):
    return np.column_stack([mag, np.zeros_like(mag), np.zeros_like(mag)])


def test_step_frequency_peak_reads_as_cadence():
    r = minute_features(_acc(1 + 0.3 * np.sin(2 * np.pi * 1.8 * T) + 0.02 * RNG.standard_normal(len(T))))
    assert r["walking"] and abs(r["cadence_spm"] - 108) < 3 and band_of(r["cadence_spm"]) == "moderate"


def test_arm_swing_with_harmonic_doubles():
    sig = 1 + 0.3 * np.sin(2 * np.pi * 0.9 * T) + 0.25 * np.sin(2 * np.pi * 1.8 * T)
    r = minute_features(_acc(sig + 0.02 * RNG.standard_normal(len(T))))
    assert r["walking"] and abs(r["cadence_spm"] - 108) < 3


def test_still_wrist_is_not_walking():
    r = minute_features(_acc(1 + 0.005 * RNG.standard_normal(len(T))))
    assert not r["walking"] and r["cadence_spm"] == 0.0 and band_of(r["cadence_spm"]) == "none"


def test_hourly_check_counts_bands_and_joins_mets():
    minutes = pd.DataFrame({
        "subject": "01", "minute": pd.date_range("2025-01-01 10:00", periods=120, freq="min"),
        "cadence_spm": [110.0] * 20 + [0.0] * 40 + [0.0] * 60, "walking": [True] * 20 + [False] * 100,
    })
    scoring = pd.DataFrame({"subject": "01", "Timestamp": pd.to_datetime(["2025-01-01 10:00", "2025-01-01 11:00"]),
                            "METs": [2.5, 1.1]})
    hourly, summary = hourly_check(minutes, scoring)
    assert list(hourly["moderate_min"]) == [20, 0]
    assert summary["mean_METs_by_moderate_plus_minutes"]["10+"]["mean_METs"] == 2.5
    assert summary["mean_METs_by_moderate_plus_minutes"]["0"]["mean_METs"] == 1.1
