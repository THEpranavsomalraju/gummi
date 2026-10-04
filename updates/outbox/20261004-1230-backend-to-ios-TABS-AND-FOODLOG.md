# Backend → iOS: tabs, Food log, Activity, Day (2026-10-04)

Mahil, nice work on the stale state, chips, fade-in, demo controls and the "Server asleep" fallback. That's exactly right.

**Day 4:** this is already done on `backend/work` (commit 1e80b66). `DEFAULT_START = "day4T05:00"`, and `demo_stage.py` stages `day4T18:00 → day4T22:10`, so the evening grade lands as "I predicted 185 … It was 186. CGM-only said 155, last value said 178." It isn't live yet only because the App can't deploy while we're at Databricks' free daily limit. I'll redeploy as soon as compute is back. Then I'll send "App back up", plus the new URL and client id/secret if the workspace moves.

Below is your next chunk as prompts. Paste them into your agent one at a time, in order. Shapes are CONTRACT 1.6 on `backend/work`. Prompt 6 only checks the chat items you haven't mentioned yet.

---

## Prompt 1: Tab structure

```
Restructure the app into four tabs: Home · Food · Activity · Day. Settings stays reachable (gear in Home's toolbar). Chat stays a sheet opened from the bubble beside Gummi on Home.

- Standard SwiftUI TabView with SF Symbols: Home (house), Food (fork.knife), Activity (bell), Day (chart.bar.doc.horizontal).
- On iOS 26 the tab bar picks up Liquid Glass naturally. On iOS 18 the default material tab bar is fine.
- Move every card/notification UI that lives on "Today" into Activity. Today goes away as a tab.
- AppModel stays the single source of truth. Every tab reads from it, and live events (/live: state, card, grade, alert, mood) update the right tab with animation, no pull-to-refresh needed.
- Cross-links: tapping a meal_story or meal_logged card in Activity opens that meal in Food. "Ask Gummi why" opens chat with the card's prompt prefilled.

Verify: builds, existing tests pass, each tab renders from MockAPI, and live events update the right tab.
```

## Prompt 2: Home

```
Polish Home as the "right now" screen. Top to bottom:
1. Compact header: "Following Participant 12" (State.acting_as; tap opens the Follow picker) and a small Dexcom pill (State.dexcom.connected, data_through).
2. The top coach card (State.top_card), swipeable to the previous few.
3. Gummi center stage, mood from State.mood and the live "mood" event, chat bubble button beside him.
4. Glucose chart (Swift Charts):
   - confirmed: solid line
   - estimate: dotted line with a translucent band (band_low/band_high), labeled "Gummi's estimate"
   - forecast: dashed with band, 2 h ahead
   - 70 and 140 lines, and a "now" marker at State.replay_now
   Line styles must differ, not just colors (accessibility). Clamp bands to 40 to 400.
5. Safety line, always visible: "Not for treatment decisions. Check your Dexcom app for current readings."
Keep the existing stale handling ("No recent readings", Gummi sleepy). data_status == "none": friendly empty state with a Follow button.

Verify: live, stale and none render correctly from MockAPI, and the chart animates smoothly on a state event.
```

## Prompt 3: Food tab (the food log)

```
Build the Food tab on GET /foodlog?date=YYYY-MM-DD. Pranav wants it to feel like a Notion database, but native and seamless in Liquid Glass.

Data: entries[] newest first. Each entry has:
- meal (Meal)
- origin: "study_log" | "you" | "gummi"
- graded (bool)
- prediction {predicted_peak_mg_dl, cgm_only_peak_mg_dl?, last_value_peak_mg_dl?, status} or null
- grade (Grade) or null
- note
Refetch on a meal_due, meal_logged or meal_story card from /live, and on pull-to-refresh.

Layout:
- Header like a Notion page: large title "Food log", the date as subtitle, a date switcher (chevrons + calendar) on glass.
- A real table: one row per meal, hairline dividers, generous row height, clean type, no heavy boxes.
  - Columns ("properties"): Time · Food · Carbs · Source · Predicted · Actual · Result.
  - On narrow widths collapse to Time · Food · Carbs · Result; the rest moves into the detail sheet.
- Group rows by meal slot as collapsible sections like Notion toggles, by local time of eaten_at: Breakfast before 11, Lunch 11 to 15, Dinner 17 to 22, Snack otherwise. Each header shows that slot's carb total.
- Source as a Notion-style pill: "Study log" / "You" / "Gummi" (Gummi's can carry a tiny koala glyph).
- Result column:
  - graded: "Me 185 · CGM-only 155 · last 178 → 186", with a small check when grade.gummi_beats_cgm_only == true
  - simulated (origin you/gummi): muted "Not graded" pill plus the likely peak you already show; note on tap
  - pending: "Grading after <window_end, local time>"
- Row tap opens a glass detail sheet:
  - all properties at the top
  - the meal's curve if available
  - item list with editable portions (PATCH /meals/{meal_id}), only for origin you/gummi (you already have this; reuse it)
  - "Ask Gummi about this meal" opens chat with a prefilled prompt
- Floating glass "+" opens "Log food": a text field (system keyboard dictation works), POST /meals {items:[{name, quantity, unit}], source:"manual"}.
- Empty state: Gummi with "Nothing logged yet. Tell me what you ate in chat and I'll add it here."

Liquid Glass: glass only on floating chrome (header controls, "+", sheets). The table stays crisp on the normal background for contrast. Use .glassEffect() on iOS 26 with an .ultraThinMaterial fallback under if #available (min iOS 18). Light and dark via the D-60 tokens. Tabular figures for numbers.

Accessibility: each row is one VoiceOver element, e.g. "Breakfast, 5:56 AM, milk and frosted flakes, 56 grams of carbs, from the study log, I predicted 152, actual 174". Dynamic Type wraps the Food column.

Verify: decoding tests with a /foodlog fixture covering all three origins plus graded, pending and simulated; every state renders; PATCH updates the row.
```

## Prompt 4: Activity tab

```
Build the Activity tab: everything Gummi posted or nudged, newest first. Notification-style cards live here, not on Home or Day.

Data: GET /feed (StoryCard list) plus live "card" and "alert" events.
- Cards upsert by card_id: the same id arriving again replaces the old card in place. This happens when:
  - background agents rewrite a template card a few seconds later (generated_by "template" → "agent")
  - meal_due cards resolve with actions [] and a body ending "Logged."
  Animate the change with a subtle crossfade, never a jump or a duplicate.

Layout:
- Grouped by Morning / Afternoon / Evening.
- A compact, distinct style per type:
  - morning_briefing
  - meal_due: "Log it" → POST /meals/due/{due_id}/log; a 409 due_already_logged shows it as logged
  - meal_logged
  - meal_story: the grade line (me vs CGM-only vs last value), a proud mark when gummi_beats_cgm_only
  - walk_suggested: Start walk
  - walk_summary
  - evening_recap
  Unknown types fall back to the generic card (keep your _unknown handling).
- generated_by "agent" shows a tiny sparkle ("written by Gummi").
- Filter chips at the top on glass: All · Meals · Walks · Grades.
- A new card arriving while you're on another tab shows an in-app banner and badges the tab until viewed.

Verify: during a live burst (backend's demo_stage.py), cards arrive and upgrade in place with no duplicates; filters work; VoiceOver reads each card's title and body.
```

## Prompt 5: Day tab (the dashboard)

```
Build the Day tab on GET /day?date=YYYY-MM-DD (DaySummary). Pranav wants one cool, properly laid out synopsis of the day. It's a dashboard, not a feed. No LLM call, so it loads instantly.

Fields:
- glucose {readings, time_in_range_pct, average_mg_dl, peak {mg_dl, at}, low {mg_dl, at}} or null
- hourly[] {hour, avg_mg_dl, min_mg_dl, max_mg_dl}
- meals {count, carbs_g, biggest {food, carbs_g, at}}
- activity {steps, walks, walk_minutes}
- predictions {made, graded, gummi_mae_mg_dl, cgm_only_mae_mg_dl, last_value_mae_mg_dl, beat_cgm_only_pct}
- best_call {about, message, gummi_peak_error_mg_dl} or null
- biggest_spike {peak_mg_dl, at, after_meal} or null
- highlights[] (first-person lines in Gummi's voice)
- recap (evening_recap StoryCard) or null
- data_status

Layout, a scrolling dashboard:
1. Hero: big time-in-range ring (%), with average, peak (time) and low (time) beside it.
2. Hourly strip (Swift Charts): a min-to-max band per hour, avg line, 70/140 lines, peak marked.
3. 2-column tile grid:
   - Meals: count, total carbs, biggest
   - Activity: steps, walks, minutes
   - My predictions: graded count; Me vs CGM-only vs last value as three small bars; "beat CGM-only X%"
   - Data source: Dexcom status
4. "Best call of the day" card (best_call.message) and "Biggest spike" card (peak, time, after which meal).
5. Highlights as a short list with a tiny Gummi avatar.
6. Evening recap card if present; otherwise "Recap at 8 PM".

Glass for the header and date switcher; tiles crisp. Tabular figures. Pull-to-refresh, plus a refresh on any grade or meal_story live event.
Edge cases:
- glucose null: "No readings yet today"
- data_status "stale": a banner
- predictions.graded == 0: "First grades land 3 hours after a meal"

Verify: a /day fixture and a stale fixture render cleanly in light and dark, and the layout holds at the largest Dynamic Type size.
```

## Prompt 6: Chat gap check (most of this is done)

```
Chips, word fade-in, empty-turn copy, reliable:false and meal_saved extras are done. Check these remaining items:
- "self_check" tool chip ("Double-checking myself…" → "Checked ✓") behaves like the others. A missing label falls back to "Thinking…" / "Done ✓".
- Gummi in the sheet is thinking while tools run and talking while text fades in. The final mood event applies only inside chat (Home's mood comes from /live).
- ": working" comment lines (heartbeat during slow tools) are ignored, and the 60 s silence timeout stays.
- Fade-in respects Reduce Motion (plain appear).
- Suggested prompts when the chat is empty: "Can I have a cookie?", "Should I walk?", "Why did I spike?", "How am I doing?".
Verify: replay chat_sse_capture.txt plus fixtures for self_check and a heartbeat through the decoder.
```

## Prompt 7: Mock now, live end-to-end later

```
Until Backend says "App back up", build against MockAPI. Make sure it serves CONTRACT 1.6 shapes for:
- /foodlog with all three origins (graded, pending, simulated)
- /day with full, stale and empty variants
- tool events with labels, including self_check
Once it's up: switch to live and run the full flow on the phone. Follow p_012, open every tab, and chat ("Can I have a cookie?", "Should I walk?"). Then Backend runs demo_stage.py stage and go. Within about 15 s the meal story should land in Activity, the graded row in Food ("Me 185 … → 186") and the best call in Day. Send Backend a screenshot plus the request for anything that looks off.
```
