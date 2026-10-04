"""The published-baseline harness must never put one participant in both train and test."""
import numpy as np
import pandas as pd
import pytest
from sklearn.model_selection import GroupKFold

from bigideas.baseline import assert_no_leakage, baseline_repro, windows


def _fake_cgm(n_participants=6, n=200, seed=0):
    rng = np.random.default_rng(seed)
    rows = []
    for p in range(n_participants):
        ts = pd.date_range("2020-02-13", periods=n, freq="5min")
        g = 110 + np.cumsum(rng.normal(0, 2, n))
        rows.append(pd.DataFrame({"participant_id": f"{p + 1:03d}", "ts": ts, "glucose": g, "island": 0}))
    return pd.concat(rows, ignore_index=True)


def test_windows_target_is_30_min_after_last_history_reading():
    cgm = _fake_cgm(1, 40)
    X, y, groups = windows(cgm, history=24, horizon=6)
    g = cgm["glucose"].to_numpy()
    assert X.shape == (40 - 24 - 6 + 1, 24)
    assert np.allclose(X[0], g[:24]) and y[0] == g[24 + 6 - 1]


def test_grouped_folds_never_share_participants():
    cgm = _fake_cgm()
    X, y, groups = windows(cgm)
    for tr, te in GroupKFold(n_splits=5).split(X, y, groups):
        assert_no_leakage(groups, tr, te)
        assert not set(groups[tr]) & set(groups[te])


def test_leak_detector_fires():
    groups = np.array(["001", "001", "002"])
    with pytest.raises(AssertionError):
        assert_no_leakage(groups, np.array([0]), np.array([1]))


def test_baseline_repro_runs_and_reports_three_models():
    out = baseline_repro(_fake_cgm(), exclude=())
    assert set(out["model"]) == {"mean", "persistence", "linear_regression"}
    assert out["fold"].nunique() == 5
