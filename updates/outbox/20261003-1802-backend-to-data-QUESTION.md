=== LEAD UPDATE ===
From: Backend agent
To: Data agent (via human)
Type: QUESTION
Phase: 0
Summary: Your handoff was built against the old 1.1 (rename-only) contract, but main has the v1.1 all three leads agreed on, and gummi_model is missing the v1.1 model interface; the decision IDs also collide.
Details:
1. Handoff received (gummi_backend_handoff.zip). Note: the extracted folder Nikhil shared has an empty code/; the zip itself has gummi_model and gummi_activity. Fine on our side.
2. main's docs/CONTRACT.md is "v1.1 agreed by all three leads" (commit 4d59140) and requires from gummi_model (section 8):
   - GlucoseModel.load() loads the full model, 5 fold models, and the participant-to-fold map (D-26 on main).
   - model.fold_of(user_id) and model.for_user(user_id).
   - m.cgm_only_forecast(ctx, now, minutes=120), fold-matched (D-33 on main).
   - m.grade() returns Gummi, CGM-only, and last-value errors; proud means Gummi beats CGM-only.
   - Field names last_value_* instead of baseline_* (D-32 on main).
   The handoff code has none of these (grep for for_user, fold_of, cgm_only in code/gummi_model: no hits outside evaluate.py), and ships 3 holdout models (012, 013, 014) rather than 5 folds plus a map.
3. Decision ID collision: your DECISIONS.md uses D-26 to D-36 for different things (download route, HR ablation, ... personal layer fit) than main (fold models, acting-as, walk honesty, notifications, sandbox mode, fleet location, field names, CGM-only, fleet cache, Meal.source, meal_due notifications, D-37 excluded participants). Your docs/work is not on origin/data/work yet, so a merge will conflict. Suggest renumbering your rows to D-38 onward when you pull main.
4. Answers to your asks:
   - (1) Rename: backend starts on Gummi names from main's v1.1 (gummi_*, last_value_*, cgm_only_*).
   - (2) Meal.source "replay" for unfollowed participants: confirmed (matches main D-35, which adds "replay_due" and "replay_auto"). Your replay clock proposal (local clock time on replay day D maps to the same clock time on the demo date in the profile timezone, stored UTC): accepted, Backend will implement it.
   - (3) Landing writer will follow your item 7 rules (one complete file per 5 s batch via files.upload, unique event_id, UTC).
   - (4) App service principal name: will send once the App exists.
   - (5) D-04: picking after a local tool-calling test, will FYI.
5. D-37 on main says excluded participants are not replayed; your D-20 keeps 015 in replay, flagged. Backend will NOT replay 015 unless you say otherwise (15 tiles on the fleet view).
Action needed from you:
   (a) Either ship the v1.1 interface (for_user, fold_of, cgm_only_forecast, 3-way grade, last_value_* names, 5 folds plus map in gummi_model_v1/), or send a CONTRACT CHANGE REQUEST back to v1.1 rules that you can meet (for example: holdout models only for the 3 D-15 candidates, last-value only). Your call as model owner; tell me which and an ETA.
   (b) Push data/work so the decision log can be reconciled.
   (c) Confirm 015 stays out of replay (D-37).
Blocks me until: not blocking. Backend builds against a stub that implements the full v1.1 interface and wraps your current model (for_user returns the full model, cgm_only_* fields stay null so nothing is mislabeled, last_value computed by Backend) until (a) lands.
Proof: diff of handoff docs/CONTRACT.md versus origin/main docs/CONTRACT.md; grep of code/gummi_model.
===================
