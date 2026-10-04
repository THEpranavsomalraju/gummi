# Demo day: p_012, replay day 4 (D-15, changed from day 6 on 2026-10-04)

Real data from BIG IDEAs participant 012, the fourth day of their recording (dates shifted by the dataset), for mocks
and demo planning. Times are the participant's local clock. Gummi's replay maps them onto the demo date in the
profile timezone (D-45). Same person as before, so the followed user (p_012) and her fold model stay the same; only
the replay day changes. Why day 4: data/reports/demo_day_scores.md.

| File | Rows | Columns |
|---|---|---|
| p012_day4_cgm.csv | 288 (every 5 minutes, 00:02 to 23:57, no gaps) | user_id, day_index, minute_of_day, local_time, glucose_mg_dl |
| p012_day4_food_log.csv | 18 food items as logged | meal_id, local_time, minute_of_day, logged_food, amount, unit, carbs_g, sugar_g, protein_g, fat_g, is_standard_breakfast |
| p012_day4_meals.csv | 9 meals (items within 15 minutes grouped) | user_id, meal_id, day_index, minute_of_day, items, macro totals, calories, is_standard_breakfast; what replay_meals releases |

Regenerate: `python data/scripts/export_demo_day.py --participant 012 --day 4`.

## The day

| Time | Meal | Carbs (g) | Gummi's peak forecast at meal time | Actual 2-hour peak | CGM-only | Last value |
|---|---|---|---|---|---|---|
| 05:56 | Standard breakfast (Frosted Flakes plus milk) | 56.5 | 135 | 188 | 112 | 107 |
| 08:55 | Egg, bacon | 1.3 | 141 | 102 | 161 | 188 |
| 12:18 | Bourbon | 0 | 102 | 96 | 108 | 95 |
| 13:10 | Coffee, cream cheese, sausage and more | 6.3 | 108 | 95 | 107 | 95 |
| 14:23 | Diet Coke | 0 | 106 | 108 | 107 | 85 |
| 15:32 | Fried cheddar cheese bite | 0 | 106 | 120 | 109 | 95 |
| 17:38 | Mint chocolate cookies | 48 | 138 | 185 | 112 | 117 |
| 19:01 | Brownie | 50 | 151 | 186 | 129 | 119 |
| 19:22 | Dark chocolate chips, corn cheese puffs, cheese and crackers | 65.6 | 178 | 186 | 135 | 146 |

mg/dL, from gummi_model_v1_2's fold model for p_012 (fold 2, never trained on her). Gummi's curve beats CGM-only's on
8 of 9 meals (all but the cheese bite). DRAFT until Pranav and Nikhil approve.

Notes for the demo:
- The standardized breakfast is at 05:56, before the 06:00 morning-briefing trigger, so start the replay at about
  day4T05:00 if the breakfast meal_due card should show.
- The breakfast rise is slow: 103 at breakfast, peak 188 at 07:52. Gummi's forecast at breakfast says 135, so the
  walk nudge does not fire at breakfast. It fires at about 07:21, once the delayed readings show the rise (forecast
  peak in the next hour 145).
- The evening is the strong part. A walk nudge fires right at the 19:01 brownie (forecast 151). The 19:22 snack grade
  lands at 22:22 replay time: "I predicted 178. It was 186. CGM-only said 135."
- At 60x, from day4T05:00 the evening is 14 minutes in. For a short live segment, starting near day4T18:00 reaches
  the brownie nudge in about 1 minute, the 20:00 recap in 2, and the 178/186 grade in about 4.5, provided the
  replay producer loads her earlier readings and meals as history (Backend to confirm).
- Glucose ranges from 77 to 193 mg/dL that day. Food log text is as the participant typed it ("Jim Bean Bourbon").
  Amounts and units are often blank.

The earlier pick, day 6, stays in this folder (p012_day6_*.csv). Its breakfast forecast crosses 140 at breakfast
(153, actual 174), but Gummi's curve beats CGM-only's on only 4 of its 9 meals.

Source: Bent B, et al. BIG IDEAs Lab Glycemic Variability and Wearable Device Data, v1.1.3, PhysioNet; Bent B, et al.
npj Digital Medicine 2021;4:89. Open Data Commons Attribution License v1.0.
