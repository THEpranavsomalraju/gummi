# Demo day: p_012, replay day 6 (D-15)

Real data from BIG IDEAs participant 012, the sixth day of their recording (dates shifted by the dataset), for mocks
and demo planning. Times are the participant's local clock. Gummi's replay maps them onto the demo date in the
profile timezone (D-45).

| File | Rows | Columns |
|---|---|---|
| p012_day6_cgm.csv | 288 (every 5 minutes, 00:02 to 23:57, no gaps) | user_id, day_index, minute_of_day, local_time, glucose_mg_dl |
| p012_day6_food_log.csv | 21 food items as logged | meal_id, local_time, minute_of_day, logged_food, amount, unit, carbs_g, sugar_g, protein_g, fat_g, is_standard_breakfast |
| p012_day6_meals.csv | 9 meals (items within 15 minutes grouped) | meal_id, items, macro totals, is_standard_breakfast; what replay_meals releases |

Notes for the demo: the standardized breakfast (Frosted Flakes plus milk, 56.5 g carbs) is at 05:54, before the
06:00 morning-briefing trigger, so start the replay at about day6T05:00 if the breakfast meal_due card should show.
Glucose ranges from 75 to 174 mg/dL that day. One food-log row (the 10:30 almonds) logged fat as 255 g, the same as its calories; silver_meals re-derives it from the calories (20.4 g), and these files carry the repaired value. Food log text is as the participant typed it ("Angle Food Candy from
Mother"); amounts and units are often blank.

Source: Bent B, et al. BIG IDEAs Lab Glycemic Variability and Wearable Device Data, v1.1.3, PhysioNet; Bent B, et al.
npj Digital Medicine 2021;4:89. Open Data Commons Attribution License v1.0.
