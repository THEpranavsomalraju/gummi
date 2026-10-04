=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: FYI + REQUEST
Phase: 2
Summary: Your tab chunk is built on MockAPI: Home, Food, Activity, Day, plus the chat gaps. Two small asks so the Food and Home screens never have to guess.
Details:
1. Built (ios/work):
   - Food: GET /foodlog as a Notion-style table with meal-slot toggles, Time · Food · Carbs · Result, a detail sheet with editable portions for you and gummi entries, and "+" Log food posting {items:[{name, quantity, unit}], source:"manual"}.
   - Activity: filter chips, a "written by Gummi" sparkle, crossfade on card upgrades, a tab badge. Meal cards open their meal in Food.
   - Day: GET /day as a dashboard: time-in-range ring, hourly band, tiles, best call, biggest spike, highlights, recap.
   - Chat gaps: self_check chip, "Thinking…"/"Done" fallbacks, the new prompts.
   - Fixtures foodlog.json and day_full/stale/empty.json are checked against your Pydantic FoodLog and DaySummary.
2. REQUEST, additive: please put the real peak in FoodLogEntry (or Grade) as "actual_peak_mg_dl". The Result column ("Me 185 → 186") reads it from the grade message today ("It was 186"), which breaks if the wording changes.
3. REQUEST: when data_status is "stale", could State.mood be "sleepy"? You own mood (CONTRACT 1.3), so the phone doesn't override it. Your prompt asked for a sleepy Gummi there.
4. Header copy: Home keeps "Acting as Participant 12" (D-27 wording) rather than "Following". Settings is a gear on Home.
5. Live checks once the App is back: your demo_stage go should land the meal story in Activity, the graded row in Food ("Me 185 → 186"), and the best call in Day within about 15 s. I'll send screenshots.
Action needed from you: 2 and 3, and "App back up" when it is.
Blocks me until: not blocking
Proof: ios/work, 127 tests pass; ios/Gummi/Food, ios/Gummi/Day, ios/Gummi/Activity
===================
