"""Readers for the raw BIG IDEAs CSVs.

Formats verified on 2026-10-03:
- File names carry the participant ID: <SIGNAL>_<ID>.csv (PhysioNet listing of folder 001).
- Dexcom: Clarity export. Keep rows with Event Type == "EGV". Time column
  "Timestamp (YYYY-MM-DDThh:mm:ss)", value "Glucose Value (mg/dL)" (PhysioFusion loader).
- E4 signals: a "datetime" column plus value columns whose names start with a space
  (e.g. " hr", " acc_x"); strip names before use (PhysioFusion loader).
- Food log (v1.1.3, 001): date,time,time_begin,time_end,logged_food,amount,unit,searched_food,
  calorie,total_carb,dietary_fiber,sugar,protein,total_fat. The column is "time", not "time_of_day".
- Demographics.csv: ID (unpadded int), Gender (MALE/FEMALE), HbA1c.
"""
from __future__ import annotations

import re
from pathlib import Path

import numpy as np
import pandas as pd

DEXCOM_TIME = "Timestamp (YYYY-MM-DDThh:mm:ss)"
DEXCOM_VALUE = "Glucose Value (mg/dL)"
DEXCOM_LOW, DEXCOM_HIGH = 40.0, 400.0   # G6 reportable range; "Low"/"High" strings map here
MACROS = ["calorie", "total_carb", "dietary_fiber", "sugar", "protein", "total_fat"]


def discover(root: str | Path) -> dict[str, dict[str, Path]]:
    """Map participant id -> {signal prefix -> file path} for whatever is on disk."""
    root = Path(root)
    found: dict[str, dict[str, Path]] = {}
    for folder in sorted(p for p in root.iterdir() if p.is_dir() and p.name.isdigit()):
        files = {}
        for f in folder.glob("*.csv"):
            stem = f.stem  # e.g. Dexcom_001, Food_Log_001
            prefix = stem.rsplit("_", 1)[0]
            files[prefix] = f
        if files:
            found[folder.name] = files
    return found


def load_dexcom(path: str | Path) -> pd.DataFrame:
    """Glucose readings only: columns ts (naive datetime), glucose (float), glucose_flag (str|None)."""
    raw = pd.read_csv(path)
    raw.columns = [c.strip() for c in raw.columns]
    if "Event Type" not in raw.columns or DEXCOM_TIME not in raw.columns:
        raise ValueError(f"{path}: unexpected Dexcom columns {list(raw.columns)[:8]}")
    egv = raw[raw["Event Type"].astype(str).str.strip() == "EGV"].copy()
    text = egv[DEXCOM_VALUE].astype(str).str.strip()
    flag = np.where(text.str.lower() == "low", "low", np.where(text.str.lower() == "high", "high", None))
    value = pd.to_numeric(text, errors="coerce")
    value = value.where(flag != "low", DEXCOM_LOW).where(flag != "high", DEXCOM_HIGH)
    out = pd.DataFrame({
        "ts": pd.to_datetime(egv[DEXCOM_TIME]),
        "glucose": value.astype(float),
        "glucose_flag": flag,
    })
    out = out.dropna(subset=["ts"]).sort_values("ts")
    out = out.drop_duplicates(subset="ts", keep="last").reset_index(drop=True)
    return out


def load_e4(path: str | Path, usecols: list[str] | None = None, chunksize: int | None = None) -> pd.DataFrame:
    """Read an Empatica E4 CSV, strip column names, parse datetime.

    usecols: stripped value column names to keep (datetime is always kept).
    For the large ACC file pass chunksize and aggregate per chunk instead (see silver.acc_to_minutes).
    """
    df = pd.read_csv(path, encoding="utf-8-sig")   # HR files start with a byte-order mark
    df.columns = [c.strip().lstrip("\ufeff") for c in df.columns]
    time_col = "datetime" if "datetime" in df.columns else df.columns[0]
    df = df.rename(columns={time_col: "datetime"})
    if usecols:
        df = df[["datetime", *usecols]]
    df["datetime"] = parse_e4_times(df["datetime"])
    return df.sort_values("datetime").reset_index(drop=True)


_US_SHORT = re.compile(r"^\d{1,2}/\d{1,2}/\d{2} \d{1,2}:\d{2}$")


def parse_e4_times(s: pd.Series) -> pd.Series:
    """E4 time stamps. Each file uses one format: "2020-02-13 15:29:00" (most) or "2/13/20 15:29" (HR_001).

    Explicit formats keep this fast and identical on pandas 1.5 (Databricks serverless environment 3) through 3.x;
    a file mixing formats falls back to per-element parsing.
    """
    s = s.astype(str).str.strip()
    first = s.iloc[0] if len(s) else ""
    fmt = "%m/%d/%y %H:%M" if _US_SHORT.match(first) else None
    try:
        return pd.to_datetime(s, format=fmt) if fmt else pd.to_datetime(s)
    except (ValueError, TypeError):
        try:
            return pd.to_datetime(s, format="mixed")      # pandas >= 2.0
        except (ValueError, TypeError):
            return pd.Series([pd.Timestamp(x) for x in s], index=s.index)


FOOD_COLS_14 = ["date", "time", "time_begin", "time_end", "logged_food", "amount", "unit", "searched_food",
                "calorie", "total_carb", "dietary_fiber", "sugar", "protein", "total_fat"]
# Participant 003 (v1.1.3) ships without a header row and with 11 columns. Mapping verified by
# cross-matching the identical "(Kellogg's) Frosted Flakes" 1.5 cup entry logged by 004 and 006
# (220 kcal, 52 g carbs, 1 g fiber, 20 g sugar, 2 g protein, 0 g fat): 003 shows 220, 52, 20, 2,
# so fiber, fat and time_end are absent, and the four numbers are calorie, carbs, sugar, protein.
FOOD_COLS_11 = ["date", "time", "time_begin", "logged_food", "amount", "unit", "searched_food",
                "calorie", "total_carb", "sugar", "protein"]
STD_BREAKFAST_PATTERN = "frosted flake"    # the provided cereal ("Frosted Flake" in 013, "Frosted Flakes" elsewhere)
# Seen in v1.1.3: 001 "Standard Breakfast", 006 "Std breakfast", 007 "Std bfast" / "Std Bfast",
# 013 logged "Frosted Flake" with searched_food "Std Bfast", 015 "Standard breakfast"
STD_BREAKFAST_NAME_REGEX = r"^\s*(standard|std)\.?\s*(breakfast|bfast|bkfst)\s*$"


def load_food_log(path: str | Path) -> pd.DataFrame:
    """One row per logged item with eaten_at (naive datetime), numeric macros and a breakfast flag.

    Handles both layouts seen in v1.1.3: the 14-column file with a header, and the headerless
    11-column file (participant 003). Missing macro columns come back as NaN, never 0.
    The standardized breakfast is identified when logged_food or searched_food matches
    STD_BREAKFAST_NAME_REGEX ("Standard Breakfast", "Std breakfast", "Std bfast") or contains "frosted flake".
    Participants also logged it as "Corn Flakes" or "Cornflakes" with searched_food "(Kellogg's) Frosted Flakes";
    the "Std ..." rows carry the same 56.5 g carb total as 1.5 cups of cereal plus milk.
    """
    with open(path, encoding="utf-8-sig") as fh:
        first = fh.readline().strip().lower()
    if first.startswith("date,"):
        df = pd.read_csv(path, encoding="utf-8-sig")
        df.columns = [c.strip() for c in df.columns]
        layout = "header"
    else:
        df = pd.read_csv(path, header=None, encoding="utf-8-sig")
        if df.shape[1] == len(FOOD_COLS_14):
            df.columns = FOOD_COLS_14
        elif df.shape[1] == len(FOOD_COLS_11):
            df.columns = FOOD_COLS_11
        else:
            raise ValueError(f"{path}: headerless food log with {df.shape[1]} columns, unknown layout")
        layout = f"headerless_{df.shape[1]}"
    tcol = "time" if "time" in df.columns else ("time_of_day" if "time_of_day" in df.columns else None)
    # time_begin is "YYYY-MM-DD HH:MM:SS" in every v1.1.3 file; date + time (formats vary by file) only fills gaps
    if "time_begin" in df.columns:
        eaten = pd.to_datetime(df["time_begin"].astype(str).str.strip(), format="%Y-%m-%d %H:%M:%S", errors="coerce")
    else:
        eaten = pd.Series(pd.NaT, index=df.index, dtype="datetime64[ns]")
    gaps = eaten.isna()
    if tcol is not None and gaps.any():
        joined = df.loc[gaps, "date"].astype(str).str.strip() + " " + df.loc[gaps, tcol].astype(str).str.strip()
        eaten.loc[gaps] = [_timestamp_or_nat(x) for x in joined]
    df["eaten_at"] = pd.to_datetime(eaten)
    for m in MACROS:
        df[m] = pd.to_numeric(df[m], errors="coerce") if m in df.columns else np.nan
    df["logged_food"] = df["logged_food"].astype(str).str.strip()
    searched = df["searched_food"].fillna("").astype(str) if "searched_food" in df.columns else ""
    logged = df["logged_food"].str.lower()
    searched_l = searched.str.lower() if not isinstance(searched, str) else pd.Series("", index=df.index)
    df["is_standard_breakfast"] = (
        logged.str.match(STD_BREAKFAST_NAME_REGEX) | searched_l.str.match(STD_BREAKFAST_NAME_REGEX)
        | logged.str.contains(STD_BREAKFAST_PATTERN, regex=False)
        | searched_l.str.contains(STD_BREAKFAST_PATTERN, regex=False)
    )
    df["source_layout"] = layout
    return df.dropna(subset=["eaten_at"]).sort_values("eaten_at").reset_index(drop=True)


def _timestamp_or_nat(text: str):
    try:
        return pd.Timestamp(text)
    except (ValueError, TypeError):
        return pd.NaT


def load_demographics(path: str | Path) -> pd.DataFrame:
    df = pd.read_csv(path)
    df.columns = [c.strip() for c in df.columns]
    df["participant_id"] = df["ID"].astype(int).map(lambda i: f"{i:03d}")
    df = df.rename(columns={"Gender": "gender", "HbA1c": "hba1c"})
    return df[["participant_id", "gender", "hba1c"]].sort_values("participant_id").reset_index(drop=True)
