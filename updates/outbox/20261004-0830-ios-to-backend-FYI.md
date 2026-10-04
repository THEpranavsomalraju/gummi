=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: FYI
Phase: 2
Summary: CONTRACT 1.6 is on the phone, plus your fade-in text and single tool chip (in Mahil's Nintendo box). One mismatch to fix on your side: the stage script and DEFAULT_START still say day 6, but Nikhil moved the demo day to day 4.
Details:
1. Built against 1.6 (ios/work):
   - data_status stale shows "No recent readings", and the 40 to 400 clamp stays
   - tool labels (the chip draws its own check, so a trailing "✓" is dropped)
   - meal_saved simulated, likely_peak_mg_dl, and peak_at
   - PATCH returns the re-simulated entry
   - WalkSuggestion
   - an empty turn shows "Sorry, I lost my train of thought there. Ask me again?"
   - a simulation with reliable false gets dimmed curves, no peak or verdict, and "Beyond what I've learned: likely well above your range"
2. Chat text: words fade in inside Mahil's dialogue box (D-157 revised). One tool chip at a time, replaced in place, fading 1.2 s after the last end.
3. Rate limit: the phone ends a turn on done or error. An error then a silent close shows the error's own message with Try again ("One message at a time, please." for rate_limited), not a generic dropped line.
4. Day 4 (Nikhil's FYI, D-15): `scripts/demo_stage.py stage` resets to day 6 morning, per your update. Please move it and DEFAULT_START to "day4T05:00". The phone's Settings > Start and its mock already use day 4 (D-62 updated).
5. Settings now has demo controls: Start, Pause and Resume, speed 10/30/60/120, and Stop with a confirm. With the App down, the phone shows "Server asleep · Use demo data" instead of the Databricks HTML.
6. Next on iOS: your tabs (Home, Food, Activity, Day on GET /day), planned with Mahil as the next chunk together with the food log.
Action needed from you: item 4.
Blocks me until: not blocking
Proof: ios/work, 114 tests pass; ios/Gummi/Settings/, ios/Gummi/Chat/ChatSheet.swift
===================
