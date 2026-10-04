# Demo day scores: why D-15 moved to p_012, day 4

DRAFT, Data Lead, 2026-10-04. Nikhil asked for a demo day that shows Gummi better. All numbers are mg/dL,
out of sample, from gummi_model_v1_2. DRAFT until Pranav and Nikhil approve.

## Method

- The 21 qualifying participant-days are listed in reports/demo_day_candidates.csv. Each has a standardized
  breakfast, a later meal, no gaps, and at least one forecast reaching 140.
- Each day is replayed exactly as the demo would run it: 19 hours from an hour before breakfast, with the
  one-hour Dexcom delay.
- Each person is predicted by her fold model (model.for_user), which never saw her.
- Every meal is graded over its 2 hours, and the hourly nowcasts are graded too.
- Code: data/scripts/score_demo_days.py. Output: data/reports/demo_day_scores.csv.

## Result

Gummi's meal curves beat CGM-only's on average on 15 of the 21 days. The median day's edge is 3.4 mg/dL. The old
pick, p_012 day 6, was one of the 6 days where CGM-only did better. The new pick is the same person on the best
day.

| Day | Meals where Gummi's curve beats CGM-only | Meal curve error, Gummi / CGM-only / last value | Peak error at meal time, Gummi / CGM-only | All grades, Gummi / CGM-only |
|---|---|---|---|---|
| **p_012 day 4 (new)** | **8 of 9** | **19.9 / 32.3 / 35.3** | **24.0 / 39.0** | **11.3 / 16.9 (21 of 27 won)** |
| p_013 day 6 | 6 of 7 | 22.6 / 32.1 / 37.2 | 33.2 / 55.0 | 14.8 / 19.1 |
| p_014 day 8 | 3 of 4 | 21.0 / 29.8 / 26.7 | 34.5 / 57.3 | 14.3 / 16.9 |
| p_011 day 8 | 3 of 4 | 11.7 / 20.0 / 21.3 | 20.8 / 43.3 | 9.9 / 13.5 |
| p_008 day 8 | 3 of 3 | 15.4 / 23.1 / 26.7 | 19.4 / 37.6 | 7.8 / 10.7 |
| p_012 day 6 (old) | 4 of 9 | 16.7 / 12.7 / 19.6 | 12.8 / 18.5 | 10.9 / 9.2 (12 of 27 won) |

The full list of 21 days is in the CSV.

## Why p_012 day 4 over the other top days

1. **Same person.**
   - The followed user stays p_012 (D-61), and so does her fold model.
   - Only the replay start day changes (D-62).
2. **Most meals won**, and every kind of meal is in the day:
   - a cereal breakfast
   - a protein-only meal: egg and bacon, where Gummi said 141 and CGM-only said 161, after the breakfast peak. It
     was 102.
   - three sweet snacks in the evening
3. **The whole fleet looks better too.** The replay starts every participant on the same day number, so the fleet
   view and the live gold change with D-15. All 15 participants over 19 hours:

   | Replay day | Grades | All, Gummi / CGM-only / last value | Meals | Quiet |
   |---|---|---|---|---|
   | 4 (new) | 336 | 11.1 / 12.4 / 15.6 | 18.5 / 21.2 / 26.1 | 9.2 / 10.2 / 13.0 |
   | 6 (old) | 340 | 12.4 / 13.2 / 15.5 | 22.2 / 22.9 / 27.2 | 9.7 / 10.6 / 12.3 |
   | 8 | 321 | 12.2 / 13.0 / 16.3 | 20.4 / 21.6 / 28.6 | 10.2 / 10.9 / 13.3 |

4. **Runner-up: p_011 day 8.**
   - It has the cleanest breakfast: forecast 142, actual 158, CGM-only 117. The walk nudge fires at breakfast.
   - But it has only 4 meals, the fleet edge on day 8 is smaller, and it would change the followed participant.

## The trade-off on day 4

- **Breakfast is a miss.**
  - Gummi said 135. It was 188. CGM-only said 112, and last value said 107.
  - Gummi is closer, but still 53 off. The rise is slow: 103 at breakfast, peak 188 at 07:52.
- **The breakfast walk nudge is late.** It fires at about 07:21, when the delayed readings show the rise, not at
  breakfast. Day 6's nudge fired at breakfast.
- **The evening carries the story.**
  - A walk nudge fires right at the 19:01 brownie: forecast 151, actual 186.
  - Then: "I predicted 178 for dark chocolate chip, corn cheese puffs and more. It was 186. CGM-only said 135, last
    value said 146."

## Honest framing for judges

The demo day is a showcase, picked for a clear story, and it is the best of 21 days. The numbers to quote as
Gummi's accuracy stay the cross-validated ones, from data/reports/model_eval.md section 4, over 602 held-out
meals:

| Error | Gummi | CGM-only | Last value |
|---|---|---|---|
| Peak error | 20.4 | 28.9 | 35.1 |
| Curve error | 18.0 | 19.3 | 23.2 |

If asked "why this day": "It has a big breakfast spike and an evening of sweets, so every feature shows up. Across
all held-out people the edge is smaller, and here are those numbers."
