"""The big-meal carb term is ramped out over the forecast (train.fit_horizons). Folding a blend of two ridge models
into one linear model must give the same predictions, so the saved artifact needs no new inference code."""
import numpy as np

from gummi_model import config as C
from gummi_model.train import _raw_space, fit_ridge, predict_ridge, ramp_weight


def test_raw_space_params_predict_the_same():
    rng = np.random.default_rng(0)
    X = rng.normal(5, 3, size=(200, 6))
    y = X @ rng.normal(size=6) + rng.normal(size=200)
    p = fit_ridge(X, y, 10.0)
    assert np.allclose(predict_ridge(p, X), predict_ridge(_raw_space(p), X))


def test_blend_of_two_models_is_one_linear_model():
    rng = np.random.default_rng(1)
    X = rng.normal(size=(300, 5))
    y = X[:, 0] * 2 + X[:, 4] ** 2 + rng.normal(size=300)
    a = _raw_space(fit_ridge(X, y, 10.0))
    X0 = X.copy(); X0[:, 4] = 0.0
    b = _raw_space(fit_ridge(X0, y, 10.0))
    w = 0.3
    blend = (a[0], a[1], w * a[2] + (1 - w) * b[2], w * a[3] + (1 - w) * b[3])
    assert np.allclose(predict_ridge(blend, X), w * predict_ridge(a, X) + (1 - w) * predict_ridge(b, X0))
    assert abs(b[2][4]) < 1e-12          # the zeroed column gets no weight, so raw inputs there do not matter


def test_ramp_weight():
    saved_cols, saved_ramp = list(C.MEAL_COLS), dict(C.MEAL_COL_RAMP_MIN)
    try:
        C.MEAL_COLS[:] = list(C.INPUT_MACROS) + ["carbs_big_g"]
        C.MEAL_COL_RAMP_MIN.clear(); C.MEAL_COL_RAMP_MIN["carbs_big_g"] = (120, 180)
        w = [ramp_weight(h // 5 - 1) for h in (60, 120, 150, 180, 240)]
        assert w == [1.0, 1.0, 0.5, 0.0, 0.0]
        C.MEAL_COL_RAMP_MIN.clear()
        assert ramp_weight(35) == 1.0
    finally:
        C.MEAL_COLS[:] = saved_cols
        C.MEAL_COL_RAMP_MIN.clear(); C.MEAL_COL_RAMP_MIN.update(saved_ramp)
