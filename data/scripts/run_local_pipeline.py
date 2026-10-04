"""Run the whole data path on a laptop (same code the Databricks notebook runs).

    py data\\scripts\\run_local_pipeline.py                     (from the repo root)
    py data\\scripts\\run_local_pipeline.py --exclude           (no exclusions)
    py data\\scripts\\run_local_pipeline.py --no-hr             (skip the heart-rate ablation)

Inputs:  data/raw/bigideas_1.1.3/  (from download_bigideas.py)
Outputs: data/local_out/ (git-ignored): CSV tables, gummi_model_v1/ artifact, run_summary.json
Default exclusion is 015, the participant the published baseline excluded (D-20 decides).
Nothing here is judge-facing until the human approves the numbers.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(DATA))

import gummi_pipeline  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default=str(DATA / "raw" / "bigideas_1.1.3"))
    ap.add_argument("--out", default=str(DATA / "local_out"))
    ap.add_argument("--exclude", nargs="*", default=["015"], help="participants left out of training (D-20)")
    ap.add_argument("--no-hr", action="store_true", help="skip the heart-rate ablation")
    ap.add_argument("--no-meal-eval", action="store_true", help="skip the slower meal-prediction evaluation")
    args = ap.parse_args()
    gummi_pipeline.run(args.raw, args.out, exclude=tuple(args.exclude), use_hr=not args.no_hr,
                      meal_eval=not args.no_meal_eval)
    return 0


if __name__ == "__main__":
    sys.exit(main())
