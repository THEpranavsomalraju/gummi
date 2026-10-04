# iOS build prompts from Pranav (via Backend agent), 2026-10-04

Paste one at a time into the iOS agent, in order. Backend shapes: CONTRACT 1.6 on backend/work.

1. Tab structure: Home · Food · Activity · Day; Today's cards move to Activity; chat stays a sheet from Gummi's bubble.
2. Home: header (following, Dexcom pill), top coach card, Gummi, chart (confirmed solid, estimate dotted with band, forecast dashed, 70/140, now marker), safety line; data_status stale/none states.
3. Food: GET /foodlog, Notion-style database table in Liquid Glass (columns Time · Food · Carbs · Source · Predicted · Actual · Result, slot groups as toggles, Source pills, Result line with baselines, detail sheet with editable portions, "+" Log food, empty state, VoiceOver rows).
4. Activity: /feed + live card/alert, upsert by card_id with crossfade (template → agent, meal_due resolved), per-type styles, filter chips, in-app banner and badge.
5. Day: GET /day DaySummary dashboard (TIR ring hero, hourly band strip, tiles for meals/activity/my predictions/data source, best call, biggest spike, highlights, recap; edge cases).
6. Chat feel: word fade-in (no typewriter), tool chips with labels (one at a time, fade out 1.2 s after end, self_check), Gummi thinking/talking, inline cards (reliable false, meal_saved simulated extras, WalkSuggestion), empty-turn fallback, ": working" heartbeat, suggested prompts.
7. MockAPI on 1.6 shapes while the workspace is at its daily limit; then the live end-to-end check with scripts/demo_stage.py stage/go.

The full prompt text was given to Pranav in chat on 2026-10-04 for pasting.
