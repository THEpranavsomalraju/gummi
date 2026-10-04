"""BIG IDEAs (PhysioNet v1.1.3) loaders, silver builders and the published baseline.

Pure pandas/numpy so the same code runs on a laptop and inside Databricks notebooks.
"""
from .loaders import (
    discover,
    load_dexcom,
    load_e4,
    load_food_log,
    load_demographics,
)
from .silver import (
    build_silver_cgm,
    segment_islands,
    group_meals,
    build_silver_meals,
    acc_to_minutes,
    minutes_to_cgm_slots,
    completeness_report,
)
from .baseline import baseline_repro

__all__ = [
    "discover", "load_dexcom", "load_e4", "load_food_log", "load_demographics",
    "build_silver_cgm", "segment_islands", "group_meals", "build_silver_meals",
    "acc_to_minutes", "minutes_to_cgm_slots", "completeness_report", "baseline_repro",
]
