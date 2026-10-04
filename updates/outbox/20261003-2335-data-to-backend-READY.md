=== LEAD UPDATE ===
From: Data agent
To: Backend agent (via human)
Type: READY
Phase: 3 (Data)
Summary: The blend was tried, nested and participant-grouped, and is not shipped: about 0.02 mg/dL gained on average,
in only 2 or 3 of 5 folds, and it undoes most of the big-spike fix. The final model is now named gummi_model_v1_2,
in its own folder. Nowcast messages say "I was within".
Details:
1. Blend y = w_h × Gummi + (1 − w_h) × CGM-only (item 2). Report: data/reports/blend_experiment.md; code:
   data/scripts/blend_experiment.py.
   - Method: w_h was chosen on an inner 4-fold participant-grouped CV inside each outer fold's training people, for
     every 5-minute step, separately for meal and quiet windows. Bands came from the blend's own inner out-of-fold
     residuals. Scored on the outer fold.
   - MAE in mg/dL, Gummi → blend:

     | Window | Minutes ahead | Gummi | Blend | Folds where blend is better |
     |---|---|---|---|---|
     | all | 60 | 12.059 | 12.036 | 3 of 5 |
     | all | 120 | 14.237 | 14.213 | 2 of 5 |
     | all | 180 | 15.155 | 15.149 | 3 of 5 |
     | meal | 60 | 15.724 | 15.660 | 3 of 5 |
     | quiet | 120 | 10.682 | 10.683 (worse by 0.001) | 0 of 5 |

   - Coverage: 0.800 → 0.799 overall, 0.759 → 0.756 in meal windows at 120 min.
   - Chosen weights: quiet about 1.0 (Gummi alone); meal 0.7 to 0.85.
   - Not shipped, for three reasons:
     (a) It fails the rule: quiet windows at 120 min are 0.001 worse, and coverage dips.
     (b) The gain is inside fold noise: 2 or 3 of 5 folds.
     (c) Mixing about 20% CGM-only into meal windows drags peaks down. The blend's peak bias is at best −13.6 mg/dL,
         against −10.7 for Gummi, and it catches at most 96 of the 292 meals that reach 140, against 135. That costs
         the walk nudge.
   - Item 3 (boosting): not run. With no reliable gain from the much simpler blend, I expect the same negative
     result, as Pranav predicted.
   - Your live p_012 nowcast numbers (Gummi 12.6, CGM-only 11.3, 5 grades) are within one person's day-to-day noise.
     In CV, quiet windows favor Gummi over CGM-only by 0.5 to 1.5 mg/dL at 30 to 180 min.
2. Final version and path (item 5a):
   - /Volumes/workspace/gummi_ml/artifacts/gummi_model_v1_2/, so set GUMMI_MODEL_DIR to it.
   - It holds the exact coefficients of registered workspace.gummi_ml.gummi_model version 5 (md5 of model.npz
     b830b452929351476bf184bf6b457a8e), with meta.version "gummi_model_v1_2".
   - model.version returns "gummi_model_v1_2", and for_user("p_012").version returns "gummi_model_v1_2_fold2".
   - config.VERSION is now gummi_model_v1_2. The training notebook writes to /Volumes/.../artifacts/<VERSION>/, so
     a later training run no longer overwrites another version's folder.
   - gummi_model_v1/ (v1.1) and gummi_model_v1_next/ stay as they are. Nothing was deleted.
   - It still needs the updated data/gummi_model code: the big-meal column, plus the message change below.
3. Grade wording (item 5b): grading.py nowcast messages now read "I was within 3 mg/dL. CGM-only was within 2, last
   value within 4." Meal messages were already first person ("I predicted 153 for the standard breakfast. It was
   174. ..."). The sample events are regenerated with the new wording.
4. Reviewer agent FYI received. agent_memory/ is outside events_live/, so gummi_stream never reads it.
Action needed from you: ship data/gummi_model from data/work in the App, set GUMMI_MODEL_DIR to
/Volumes/workspace/gummi_ml/artifacts/gummi_model_v1_2/, and confirm the App reports model_version gummi_model_v1_2.
Blocks me until: not blocking
Proof:
- pytest data/tests: 45 passed.
- scripts/blend_experiment.py output: data/local_out/blend_experiment/summary.csv and per_fold.csv.
- md5 of the model.npz uploaded to gummi_model_v1_2 matches gummi_model_v1_next (version 5).
===================
