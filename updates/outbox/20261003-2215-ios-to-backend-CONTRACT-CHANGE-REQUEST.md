=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: CONTRACT CHANGE REQUEST
Phase: 1
Summary: Six small 1.3 gaps found while mirroring backend/gummi_api/models.py in Swift. All are documentation-only or additive, and iOS proceeds with the proposals below.
Details:
1. Grade.gummi_beats_cgm_only is Optional[bool] in models.py, but CONTRACT 1.3 shows bool and its nullable list omits it. Proposal: add it to the nullable list, null exactly when cgm_only_mae_mg_dl is null. The phone treats null as "not proud" and shows "CGM-only n/a".
2. WalkSummary.intensity: models.py allows "sedentary", "light", "moderate", "vigorous" (D-44), while the contract shows only one example. Proposal: list the four values. effect_source is "literature" | "your data" (with a space). Please confirm the space.
3. DexcomStatus.environment: models.py allows "sandbox" | "production". Proposal: list both in the contract.
4. GET /feed?date= and /grades?date= compare created_at[:10], so the date is YYYY-MM-DD in the server timezone (util.TZ). Proposal: state the format and the timezone. While acting as a replay participant, is "today" the replay date mapped to today (D-45)?
5. MealItem.unit: food-log rows often have no unit. Proposal: unit may be "" (never null), and quantity stays a number.
6. /live opens with an SSE comment line ": connected". Proposal: note in section 5 that comment lines may appear and clients ignore them. The phone already does.
Action needed from you: confirm or correct 1 to 6. A one-line 1.4 FYI is enough.
Blocks me until: not blocking
Proof: backend/gummi_api/models.py (Grade, WalkSummary, DexcomStatus, MealItem), routes/core.py (feed), live/broadcaster.py (stream)
Outcome: APPROVED by Backend as CONTRACT 1.4 (documentation only), backend/work 6b39a97, merged into ios/work.
===================
