=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: REQUEST
Phase: 2
Summary: The phone now runs chat over POST /chat (D-155 to D-160). Ten points in the chat contract are unclear or out of date, and the live estimate for p_012 is broken (item 11).
Details:
1. walk_suggestion payload: tools.suggest_walk sends {minutes, start, forecast_peak_mg_dl, forecast_peak_drop_mg_dl, effect_source}, and the last three can be null. CONTRACT section 3 has no object for it. Proposal: add WalkSuggestion with those fields, all three nullable. The phone already decodes it that way.
2. grade and meal_due chat cards: section 6 lists card_type "grade", but no chat tool emits it, and nothing emits "meal_due" in chat. Is either planned? Meanwhile the phone decodes both (grade payload is a Grade, meal_due payload is a StoryCard) and pins any pending meal_due card from the feed above the chat input with its Log it button.
3. CONTRACT section 7 "Simulation rule" says a non-matching chat meal becomes a simulation. Under D-59 and 1.5, log_meal saves a simulated, ungraded food-log entry, and the simulate_food tool description also asks for simulations of meals mentioned while acting as. Proposal: rewrite the rule to say what the code does now.
4. meal_saved has no flag saying it's simulated, and no likely peak. The phone infers "Simulated on Participant N's day · not graded" from State.acting_as. Proposal (additive): put "simulated": true, "likely_peak_mg_dl", and "peak_at" in the card payload next to the Meal, for example {"meal": Meal, "simulated": true, "likely_peak_mg_dl": 158.0, "peak_at": "..."}. This changes the payload shape, so a 1.6 change; or add the three fields at the top level of the payload so today's decoding keeps working.
5. PATCH /meals on a chat entry: _patch updates items and totals, but u.meal_sims keeps the old simulated peak, so after editing portions the food log and the next reply still use the old peak. Please recompute meal_sims on PATCH for the user's own meals.
6. PATCH /meals body: nutrition.item keeps any macros it's sent, so the phone scales every macro by quantity before sending. Please confirm that's the intended contract: "items carry final macros for that quantity".
7. Ending a turn: rate_limited sends error with no done, while the failure path sends error then done. The phone treats either done or error as the end, and a close with neither as a dropped turn. Please confirm, and add it to section 6.
8. Silence: ask_data can take 20+ seconds with nothing sent after tool start. The phone gives up after 60 s of silence. Is 60 s enough, or can the backend send an SSE comment line as a heartbeat during long tools?
9. conversation_id: history lives in memory (CONVERSATIONS), so after an App restart a known id silently starts fresh. That's fine for the phone; please note it in section 6.
10. Final mood event: the phone shows it on Home's Gummi only while chat is open; the live channel's mood owns Home otherwise. Shout if you meant it to change Home's mood.
11. Live data bug (not chat): a real /chat capture at 2026-10-04 02:20 ET ("How am I doing today?", conversation conv_4787, trace tr-f5d662dc2fb939507a6ed2a386eb7c92) returned gummi_view {glucose_mg_dl 121.2, band_low_mg_dl -631.2, band_high_mg_dl 878.0, minutes_since_confirmed 3892, confidence "low"}. The reply told the user they were "comfortably within" range. Earlier, State for p_012 had 0 confirmed readings at replay time Oct 6 20:26. The estimate seems to run 65 hours past the last reading. Suggestions: cap the estimate gap, or return gummi_view null when data is that stale; have get_state tell the model the data is stale so it never calls an estimate with a ±750 band "in range". The phone now clamps the displayed band to 40 to 400, but that only hides the symptom.
Action needed from you: answer 2, 6, 7, 8, 10; decide on 1, 3, 4 (contract edits are yours); fix 5 and 11 when you can.
Blocks me until: not blocking (the phone handles today's behavior)
Proof: real capture saved as ios/GummiTests/Fixtures/chat_sse_capture.txt and decoded in ChatDecodingTests; code read from backend/gummi_api/agent/chat.py (stream_turn, run_turn), agent/tools.py (suggest_walk, log_meal), routes/meals.py (_patch, create_meal), nutrition/estimate.py (item). 92 iOS tests pass.
===================
