"""Evaluation helpers: the meal-time summary keeps every Gummi number next to the last-value guess."""
import numpy as np
import pandas as pd

from gummi_model.evaluate import summarize_meal_predictions


def test_meal_summary_signed_error_and_wins():
    mp = pd.DataFrame({
        "model": ["gummi_cgm_meals"] * 3 + ["gummi_cgm"] * 3,
        "meal_id": ["a", "b", "c"] * 2,
        "predicted_peak": [150.0, 120.0, 100.0, 130.0, 110.0, 100.0],
        "actual_peak": [160.0, 110.0, 120.0, 160.0, 110.0, 120.0],
        "peak_abs_err": [10.0, 10.0, 20.0, 30.0, 0.0, 20.0],
        "last_value_peak_abs_err": [40.0, 10.0, 30.0, 40.0, 10.0, 30.0],
        "curve_mae": [5.0, 12.0, 8.0, 9.0, 12.0, np.nan],
        "last_value_curve_mae": [10.0, 10.0, 10.0, 10.0, 10.0, 10.0],
    })
    out = summarize_meal_predictions(mp).set_index("model")
    m = out.loc["gummi_cgm_meals"]
    assert m["meals"] == 3
    assert m["peak_mae"] == round(40 / 3, 1)
    assert m["last_value_peak_mae"] == round(80 / 3, 1)
    assert m["peak_bias"] == round((-10 + 10 - 20) / 3, 1)      # negative = Gummi predicted too low
    assert m["gummi_beats_last_value_pct"] == round(200 / 3, 1)  # 2 of 3 curves beat the last-value guess
    c = out.loc["gummi_cgm"]
    assert c["gummi_beats_last_value_pct"] == round(100 / 3, 1)  # a meal without a curve never counts as a win
