# Demo day candidates (decision D-15)

DECIDED (changed 2026-10-04): p_012 replay day 4, the same person on her best day. Nikhil asked for a day that shows
Gummi better; all 21 qualifying days were scored with gummi_model_v1_2 in reports/demo_day_scores.md. Gummi's meal
curves beat CGM-only's on 8 of 9 meals that day (19.9 against 32.3 mg/dL). The earlier pick, day 6 (Nikhil,
2026-10-03), is kept below for the record. The day's real data is in reports/demo_day/.

DRAFT numbers, Data Lead. Criteria from data/CLAUDE.md plus the demo script in PROJECT_OVERVIEW
section 9: full CGM coverage from 06:00 to 22:00, a clear standardized-breakfast spike, at least one later meal, and
at least one meal where Gummi's forecast reaches the 140 mg/dL high line (the walk nudge in step 5). 015 is excluded
(D-20). 21 of 140 participant-days qualify; all of them are in `reports/demo_day_candidates.csv`, made by
`python data\scripts\demo_day_candidates.py`. Grades below come from participant-grouped predictions made at
meal-logging time with data up to one hour before (the model never saw that person), next to the last-value guess.

| Pick | Participant, replay day | Why | Meals (later) | Breakfast rise | Forecasts at 140+ | Gummi curve error vs last value (mg/dL) |
|---|---|---|---|---|---|---|
| A | p_012, day 6 | Busiest day: many meals, several walk nudges | 9 (5) | 57 | 3 | 15.5 vs 19.6 |
| B | p_013, day 4 | Biggest breakfast spike, a few clear meals | 4 (3) | 108 | 3 | 29.5 vs 42.9 |
| C | p_014, day 8 | Big breakfast, clean simple day | 4 (2) | 100 | 3 | 22.8 vs 26.7 |

Other qualifying days with a clear Gummi advantage: p_011 day 10 (23.2 vs 35.0), p_008 day 8 (14.1 vs 26.7),
p_010 day 8 (35.7 vs 70.7, very spiky).

## Honesty note for the demo

Solved by the v1.1 fold models (D-26). `gummi_model_v1/` holds the full model plus 5 participant-grouped fold models
and the participant-to-fold map. The Backend calls `model.for_user("p_012")`, which returns the fold model trained
without participant 012, so "Gummi has never seen this person" is true on stage, and the same holds for every other
fleet participant. Teammates and the sandbox get the full model. The earlier `gummi_model_v1_holdout_*` exports and
`scripts/export_holdout_models.py` are retired.

## The earlier pick, day 6, with the three-way grades (DRAFT, model with the big-meal term, D-70)

Superseded by day 4; see reports/demo_day_scores.md. p_012 day 6 replayed through `model.for_user("p_012")` (fold 2, never trained on 012), meals graded 2 hours after
eating with readings that arrived an hour later (`scripts/make_test_events.py --participants 012 --hours 19`):

- Gummi beats CGM-only on 4 of 9 meals: the standardized breakfast at 05:54 ("I predicted 153. It was 174."
  CGM-only said 120), the 16:35 diet coke, and both evening meals (19:02 toast: 142 against an actual 161; 19:24
  candy: "I predicted 164. It was 161."). So the proud mood fires about 4 times that day.
- The breakfast forecast now crosses 140, so the walk nudge can fire after breakfast.
- On the other 5 meals (07:40, 08:51, 10:30, 12:41 and the 17:45 dinner), CGM-only is closer: Gummi expects a rise
  this person does not show. Gummi still beats last value on most of them.
- Across the day's 25 grades: Gummi 10.9 mg/dL, CGM-only 9.0, last value 13.3. If asked, say it plainly: on this
  day CGM-only is slightly closer on average, and Gummi's edge is on the big meals.
