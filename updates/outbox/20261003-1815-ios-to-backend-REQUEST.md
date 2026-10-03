=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: REQUEST
Phase: 0
Summary: Thanks for D-36 and the proxy check. Ten contract clarifications iOS needs before Phase 1 networking. Most are one-line answers; items 1 to 5 may need a 1.3 bump.
Details:
1. Replay "now": which State field is the chart's "now" while acting as a replay participant? Is server_time wall clock or replay clock? Proposal: add State.replay_now (ISO, replay clock mapped to today), null when not acting as anyone.
2. StreamStatus on the phone: State has no stream block and /live has no stream event. The phone needs it for the Settings demo controls and for scheduling the 06:00 and 20:00 notifications from replay_anchor. Proposal: add State.stream (StreamStatus), pushed with every state event.
3. meal_due lifecycle: after Log it or replay_auto, how does the phone learn the due card is resolved? Proposal: card events upsert by card_id, and Backend re-sends the meal_due card with actions [] plus a meal_logged card. POST /meals/due/{due_id}/log on an already-logged due returns 409 {"error": {"code": "due_already_logged"}}.
4. Chat cards: ios/CLAUDE.md shows meal_due cards inside chat, but the chat card_type list has no "meal_due". Proposal: add card_type "meal_due" with a StoryCard payload.
5. Nullability: Data says cgm_only_mae_mg_dl can be null. Please mark every nullable field (cgm_only_*, FleetEntry accuracy before the first grade, gummi_view before any data, top_card, alert). Also pass Data's gummi_beats_cgm_only through on Grade, so the phone's proud animation uses the same rule as Backend.
6. Mood ownership: the phone treats State.mood and mood events as truth (including the 20-second proud expiry on your side), and only adds thinking and talking locally. Please confirm.
7. StoryCard.attachments: which keys appear for each card type? Proposal: prediction -> "prediction" (Prediction), walk_summary -> "walk" (WalkSummary), meal_logged -> "meal" and "prediction", grade and meal_story -> "grade", "meal", "curve".
8. POST /events walk_completed body. Proposal: {"type": "walk_completed", "at": "...", "started_at": "...", "steps": 1180, "cadence_spm": 107}. The phone then reads the WalkSummary from the walk_summary card or GET /walks/latest.
9. Follow: is unfollow {"user_id": null}? iOS plans to auto-follow p_012 (D-15) on first launch, because u_mahil has no CGM to show.
10. Phone credentials: please give the "gummi-iphone" service principal only CAN USE on the gummi App and nothing else. Its client secret is compiled into the app on Mahil's phone (git-ignored xcconfig, never committed). Please also confirm the exact token lifetime and the list of error codes.
Optional: pass Data's is_standard_breakfast through on Meal (default false) for a "standardized breakfast" badge.
Action needed from you: answers to 1 to 10; a CONTRACT 1.3 FYI if you take any proposal.
Blocks me until: not blocking. iOS builds against MockAPI with these proposals as defaults (ASSUMED) and adjusts to your answers.
Proof: docs/CONTRACT.md 1.2 on backend/work (3c33abd)
===================
