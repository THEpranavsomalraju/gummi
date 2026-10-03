"""Bronze tables: raw rows as delivered, plus participant_id and lineage. No cleaning here.

bronze_cgm          every Dexcom export row (metadata and alert rows included), all columns as strings
bronze_food_log     every food log row, mapped to the 14 standard column names (003 had no header)
bronze_demographics Demographics.csv as delivered
bronze_hr           per-minute mean heart rate (the 1 Hz file is aggregated on arrival; ablation only)
"""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from .loaders import FOOD_COLS_11, FOOD_COLS_14, discover, load_e4


def bronze_cgm(root: str | Path) -> pd.DataFrame:
    parts = []
    for pid, files in sorted(discover(root).items()):
        if "Dexcom" not in files:
            continue
        df = pd.read_csv(files["Dexcom"], dtype=str, encoding="utf-8-sig")
        df.columns = [c.strip() for c in df.columns]
        df.insert(0, "participant_id", pid)
        df["source_file"] = files["Dexcom"].name
        parts.append(df)
    out = pd.concat(parts, ignore_index=True)
    out.columns = [c.replace(" ", "_").replace("(", "").replace(")", "").replace("/", "_per_").replace("-", "_")
                   .replace(":", "").lower() for c in out.columns]
    return out


def bronze_food_log(root: str | Path) -> pd.DataFrame:
    parts = []
    for pid, files in sorted(discover(root).items()):
        if "Food_Log" not in files:
            continue
        path = files["Food_Log"]
        with open(path, encoding="utf-8-sig") as fh:
            first = fh.readline().strip().lower()
        if first.startswith("date,"):
            df = pd.read_csv(path, dtype=str, encoding="utf-8-sig")
            df.columns = [c.strip() for c in df.columns]
            df = df.rename(columns={"time_of_day": "time"})
            layout = "header"
        else:
            df = pd.read_csv(path, dtype=str, header=None, encoding="utf-8-sig")
            df.columns = FOOD_COLS_14 if df.shape[1] == 14 else FOOD_COLS_11
            layout = f"headerless_{df.shape[1]}"
        for c in FOOD_COLS_14:
            if c not in df.columns:
                df[c] = None
        df = df[FOOD_COLS_14]
        df.insert(0, "participant_id", pid)
        df["source_layout"] = layout
        df["source_file"] = path.name
        parts.append(df)
    return pd.concat(parts, ignore_index=True)


def bronze_demographics(root: str | Path) -> pd.DataFrame:
    df = pd.read_csv(Path(root) / "Demographics.csv", encoding="utf-8-sig")
    df.columns = [c.strip().lower() for c in df.columns]
    df["participant_id"] = df["id"].astype(int).map(lambda i: f"{i:03d}")
    return df


def bronze_hr(root: str | Path) -> pd.DataFrame | None:
    parts = []
    for pid, files in sorted(discover(root).items()):
        if "HR" not in files:
            return None
        df = load_e4(files["HR"], usecols=["hr"])
        m = df.groupby(df["datetime"].dt.floor("min")).agg(hr_mean=("hr", "mean"), samples=("hr", "size")).reset_index()
        m = m.rename(columns={"datetime": "minute"})
        m.insert(0, "participant_id", pid)
        parts.append(m)
    return pd.concat(parts, ignore_index=True)
