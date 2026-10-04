=== LEAD UPDATE ===
From: Data agent
To: Backend agent (via human)
Type: REQUEST
Phase: 5 (demo)
Summary: D-15 changes from p_012 day 6 to p_012 day 4 (Nikhil's call). The followed person stays the same; only the
replay start day changes. Please set DEFAULT_START to "day4T05:00" and redeploy.
Details:
1. Why: Nikhil asked for a demo day where Gummi shows better.
   - I scored all 21 qualifying days with gummi_model_v1_2 and for_user, replayed the way the demo runs it (19 hours,
     60-minute delay). Report: data/reports/demo_day_scores.md.
   - Meal-curve error in mg/dL, DRAFT:

     | Replay | Meals where Gummi beats CGM-only | Gummi | CGM-only | Last value | All grades, Gummi / CGM-only |
     |---|---|---|---|---|---|
     | p_012 day 4 (new) | 8 of 9 | 19.9 | 32.3 | 35.3 | 11.3 / 16.9 (27 grades) |
     | p_012 day 6 (old) | 4 of 9 | 16.7 | 12.7 | 19.6 | 10.9 / 9.2 |

   - Fleet, all 15 participants over 19 hours, Gummi / CGM-only / last value:
     - day 4: 11.1 / 12.4 / 15.6 (336 grades)
     - day 6: 12.4 / 13.2 / 15.5 (340 grades)
2. Changes in your files (I did not edit backend/):
   - backend/gummi_api/config.py: DEFAULT_START = "day4T05:00". Breakfast is at 05:56, before the 06:00 briefing
     trigger, as before.
   - backend/tests/test_contract.py line 72 asserts replay_clock == "day6T05:00". Change it to "day4T05:00".
   - Redeploy the App, because main.py builds hot state from DEFAULT_START at startup.
   - D-61 (auto-follow p_012) and her fold model (gummi_model_v1_2_fold2) stay the same.
3. What p_012 day 4 does. Times are replay-local. Every number comes from my replay of your rules, so your engine
   may differ by a tick.
   - 05:56 standard breakfast: predicted 135, actual 188, CGM-only 112, last value 107.
     - The breakfast forecast is under 140, so the walk nudge does not fire at breakfast.
     - It fires at about 07:21, once the delayed readings show the rise (forecast peak in the next hour 145).
   - 08:55 egg and bacon: predicted 141, actual 102, CGM-only 161, last value 188.
   - 19:01 brownie: the walk nudge fires at meal time (forecast 151); actual 186.
   - 19:22 snack: graded at 22:22. "I predicted 178 for dark chocolate chip, corn cheese puffs and more. It was 186.
     CGM-only said 135, last value said 146."
   - Walk nudges, using your rule (forecast peak within 60 minutes crosses 140, 45-minute cooldown): 07:21, 08:16,
     19:01, 19:46, 20:31, 21:16.
   - The proud mood (beats CGM-only) fires on 8 of the 9 meal grades.
4. Option for a short live segment.
   - At 60x, a run from day4T05:00 reaches the evening about 14 minutes in.
   - start_at "day4T18:00" works because your engine's start() preloads earlier history. From there:
     - brownie nudge at about 1 minute
     - 20:00 evening recap at 2 minutes
     - the 178/186 grade at about 4.4 minutes
   - Your call with Mahil.
5. Live gold: no pipeline change is needed. Grades from a day-4 run add to the out-of-sample grades already in
   stream_gold_accuracy. If you want the dashboard to show only the demo run, tell Nikhil. Clearing events_live and
   running a full refresh needs his OK, because it deletes files.
6. Still standing: I turn continuous mode back on when you ping, about 30 minutes before rehearsal.
Action needed from you:
(1) Set DEFAULT_START = "day4T05:00" and update the test.
(2) Redeploy.
(3) Confirm that /stream/status shows replay_clock day4T05:00 after a start.
Blocks me until: not blocking
Proof:
- data/scripts/score_demo_days.py writes data/reports/demo_day_scores.csv with all 21 days.
- The fleet numbers come from make_test_events.py, with all 15 participants, --replay-day 4 and 6, --hours 19.
- data/reports/demo_day/p012_day4_*.csv holds the day's real data.
===================
