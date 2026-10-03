# Demo day candidates (decision D-15)

DECIDED: pick A, p_012 replay day 6 (Nikhil, 2026-10-03). The day's real data is in reports/demo_day/.

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

## What the demo day looks like with the v1.1 three-way grades (DRAFT)

p_012 day 6 replayed through `model.for_user("p_012")` (fold 2, never trained on 012), meals graded 2 hours after
eating with readings that arrived an hour later (`scripts/make_test_events.py --participants 012 --hours 19`):

- Gummi beats CGM-only on 4 of 9 meals: the standardized breakfast (05:54), the 16:35 diet coke, and both evening
  meals (19:02 toast 130 vs actual 161, CGM-only 115; 19:24 candy 145 vs 161, CGM-only 113). So the proud mood
  fires about 4 times that day.
- On the other 5 (07:40, 08:51, 10:30, 12:41 and the 17:45 dinner) CGM-only is closer: Gummi expects a rise that this
  person does not show. Gummi still beats last value on most of them.
- Across the day's 25 grades: Gummi 10.2 mg/dL, CGM-only 9.0, last value 13.3. Say it plainly if asked: on this
  day the CGM-only method is slightly closer on average, and Gummi's edge is on the big meals.
