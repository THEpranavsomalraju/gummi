"""Loader tests on tiny fixtures that copy the real v1.1.3 layouts (verified 2026-10-03)."""
import numpy as np
import pandas as pd

from bigideas import build_silver_cgm, build_silver_meals, group_meals, load_dexcom, load_food_log

DEXCOM = """Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Event Subtype,Patient Info,Device Info,Source Device ID,Glucose Value (mg/dL),Insulin Value (u),Carb Value (grams),Duration (hh:mm:ss),Glucose Rate of Change (mg/dL/min),Transmitter Time (Long Integer)
1,,FirstName,,2019,,,,,,,,
2,,LastName,,001,,,,,,,,
5,,Device,,,Dexcom G6 Mobile App,iPhone G6,,,,,,
7,,Alert,High,,,iPhone G6,200.0,,,,,
13,2020-02-13 17:23:32,EGV,,,,iPhone G6,61.0,,,,,11101.0
14,2020-02-13 17:28:32,EGV,,,,iPhone G6,59.0,,,,,11401.0
15,2020-02-13 17:33:32,EGV,,,,iPhone G6,Low,,,,,11701.0
16,2020-02-13 18:03:32,EGV,,,,iPhone G6,High,,,,,13501.0
"""

FOOD_14 = """date,time,time_begin,time_end,logged_food,amount,unit,searched_food,calorie,total_carb,dietary_fiber,sugar,protein,total_fat
2020-02-14,07:10:00,2020-02-14 07:10:00,,Natrel Lactose Free 2 Percent,8.0,fluid ounce,(Natrel) Lactose Free 2% Partly Skimmed Milk,120.0,9.0,,8.0,12.0,
2020-02-14,07:10:00,2020-02-14 07:10:00,,Standard Breakfast,0.75,cup,"(Kellogg's) Frosted Flakes, Cereal",110.0,26.0,,10.0,1.0,
2020-02-14,09:38:00,2020-02-14 09:38:00,,Breakfast Trail Mix,0.5,cup,"(Giant) Breakfast Blend, Trail Mix",280.0,30.0,,22.0,4.0,
2020-02-14,09:50:00,2020-02-14 09:50:00,,Coffee,1,cup,Coffee,2.0,0.0,0.0,0.0,0.3,0.0
"""

FOOD_11_HEADERLESS = """2020-02-23,05:30:00,2020-02-23 05:30:00,Milk,4.0,ounce,(Natrel) Lactose Free 2% Partly Skimmed Milk,60.0,4.5,4.0,6.0
2020-02-23,05:30:00,2020-02-23 05:30:00,Cornflakes,1.5,cup,(Kellogg's) Frosted Flakes,220.0,52.0,20.0,2.0
2020-02-23,12:00:00,2020-02-23 12:00:00,Spaghetti,12.0,ounce,Spaghetti,511.2,102.6,3.7,18.0
"""

FOOD_STD = """date,time,time_begin,time_end,logged_food,amount,unit,searched_food,calorie,total_carb,dietary_fiber,sugar,protein,total_fat
2020-03-02,05:15:00,2020-03-02 05:15:00,,Std breakfast,,,,280,56.5,1.0,24.0,8.0,2.5
2020-03-02,09:50:00,2020-03-02 09:50:00,,Premier protein choc shake,,,,160,5.0,3.0,1.0,30.0,3.0
"""


def _write(tmp_path, rel, text):
    p = tmp_path / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    return p


def test_dexcom_keeps_only_egv_and_maps_low_high(tmp_path):
    df = load_dexcom(_write(tmp_path, "001/Dexcom_001.csv", DEXCOM))
    assert len(df) == 4
    assert df["glucose"].tolist() == [61.0, 59.0, 40.0, 400.0]
    flags = df["glucose_flag"].tolist()
    assert pd.isna(flags[0]) and pd.isna(flags[1]) and flags[2:] == ["low", "high"]
    assert df["ts"].is_monotonic_increasing


def test_islands_split_on_gaps_over_15_min(tmp_path):
    _write(tmp_path, "001/Dexcom_001.csv", DEXCOM)
    cgm = build_silver_cgm(tmp_path)
    # 17:33 -> 18:03 is a 30-minute gap: new island
    assert cgm["island"].tolist() == [0, 0, 0, 1]
    assert (cgm["participant_id"] == "001").all()


def test_food_log_with_header(tmp_path):
    df = load_food_log(_write(tmp_path, "001/Food_Log_001.csv", FOOD_14))
    assert df["source_layout"].iloc[0] == "header"
    assert df["is_standard_breakfast"].tolist() == [False, True, False, False]
    assert np.isnan(df.loc[0, "dietary_fiber"])  # blank stays NaN, never 0


def test_food_log_headerless_11_columns(tmp_path):
    df = load_food_log(_write(tmp_path, "003/Food_Log_003.csv", FOOD_11_HEADERLESS))
    assert df["source_layout"].iloc[0] == "headerless_11"
    cereal = df[df["logged_food"] == "Cornflakes"].iloc[0]
    assert cereal["calorie"] == 220.0 and cereal["total_carb"] == 52.0
    assert cereal["sugar"] == 20.0 and cereal["protein"] == 2.0
    assert np.isnan(cereal["dietary_fiber"]) and np.isnan(cereal["total_fat"])
    assert bool(cereal["is_standard_breakfast"])


def test_std_breakfast_short_name(tmp_path):
    df = load_food_log(_write(tmp_path, "006/Food_Log_006.csv", FOOD_STD))
    assert df["is_standard_breakfast"].tolist() == [True, False]


def test_std_breakfast_spellings():
    import re
    from bigideas.loaders import STD_BREAKFAST_NAME_REGEX
    for name in ["Standard Breakfast", "Std breakfast", "Std bfast", "Std Bfast", "std. breakfast"]:
        assert re.match(STD_BREAKFAST_NAME_REGEX, name.lower()), name
    for name in ["Breakfast Trail Mix", "Cereal", "standard fries"]:
        assert not re.match(STD_BREAKFAST_NAME_REGEX, name.lower()), name


FOOD_007 = """date,time_of_day,time_begin,time_end,logged_food,amount,unit,searched_food,calorie,total_carb,dietary_fiber,sugar,protein,total_fat
03/16/2020,09:45,2020-03-16 09:45:00,10:00:00,Std bfast,,,,280,56.5,1.0,24.0,8.0,2.5
"""


def test_food_log_us_dates_and_time_of_day(tmp_path):
    df = load_food_log(_write(tmp_path, "007/Food_Log_007.csv", FOOD_007))
    assert str(df.loc[0, "eaten_at"]) == "2020-03-16 09:45:00"
    assert bool(df.loc[0, "is_standard_breakfast"])


def test_meal_grouping_chains_rows_within_15_min(tmp_path):
    df = load_food_log(_write(tmp_path, "001/Food_Log_001.csv", FOOD_14))
    meals = group_meals(df)
    # 07:10 milk + cereal -> one meal; 09:38 trail mix + 09:50 coffee (12 min later) -> one meal
    assert len(meals) == 2
    assert meals.loc[0, "total_carb"] == 35.0 and bool(meals.loc[0, "is_standard_breakfast"])
    assert meals.loc[1, "n_items"] == 2


def test_silver_meals_renames_and_ids(tmp_path):
    _write(tmp_path, "001/Food_Log_001.csv", FOOD_14)
    _write(tmp_path, "001/Dexcom_001.csv", DEXCOM)
    meals = build_silver_meals(tmp_path)
    assert {"carbs_g", "sugar_g", "fiber_g", "protein_g", "fat_g", "calories"} <= set(meals.columns)
    assert meals["meal_id"].tolist() == ["001-001", "001-002"]
    assert meals["meal_slot"].tolist() == ["breakfast", "breakfast"]


FOOD_013 = """date,time_of_day,time_begin,time_end,logged_food,amount,unit,searched_food,calorie,total_carb,dietary_fiber,sugar,protein,total_fat
05/31/2020,10:19,2020-05-31 10:19:00,,Frosted Flake,1.5,cup,Std Bfast,280,56.5,1.0,24.0,8.0,2.5
05/31/2020,10:30,2020-05-31 10:30:00,,Decaf Latte,12,ounce,Latte,190,19.0,0.0,17.0,10.0,7.0
"""


def test_std_breakfast_from_searched_food(tmp_path):
    df = load_food_log(_write(tmp_path, "013/Food_Log_013.csv", FOOD_013))
    assert df["is_standard_breakfast"].tolist() == [True, False]


def test_fat_logged_as_calories_is_rederived_from_energy():
    from bigideas.silver import fix_fat_logged_as_calories
    food = pd.DataFrame({"calorie": [255.0, 120.0, np.nan], "total_carb": [9.0, 10.0, 5.0],
                         "protein": [8.9, 2.0, 1.0], "total_fat": [255.0, 8.0, 40.0]})
    out = fix_fat_logged_as_calories(food)
    assert out["total_fat"].tolist()[0] == round((255 - 36 - 35.6) / 9, 1)   # repaired
    assert out["total_fat"].tolist()[1] == 8.0                              # plausible row untouched
    assert out["total_fat"].tolist()[2] == 40.0                             # no calories: untouched
