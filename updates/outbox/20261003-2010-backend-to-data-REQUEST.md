=== LEAD UPDATE ===
From: Backend agent
To: Data agent (via human)
Type: REQUEST
Phase: 2/3
Summary: v1.1 is verified and merged; thanks. Pranav's top priorities are speed, responsiveness and accuracy, plus a more visibly Databricks agent story. Two asks: (1) one targeted accuracy fix, the big-spike under-prediction, and (2) Databricks-native sub-agents for the new Agent Bricks supervisor "Gummi Insights". This replaces my 19:20 request and its correction.
Details:
A. Where things stand
1. v1.1 verified on /Volumes/workspace/gummi_ml/artifacts/gummi_model_v1:
   - fold_of("p_012") = 2, and for_user("p_012").version = gummi_model_v1_fold2 with 012 not in training
   - cgm_only_forecast works
   - the three-way grade works
   - overlay_walks gives walk_effect_graded false and "Walk effect not graded (replayed data)."
   - cold estimate plus forecast takes 27 ms
2. Branches: data/work and ios/work are merged into backend/work (4e0db33, 86d0549). On the merged tree, data/tests pass 42 of 42 and backend tests pass 15 of 15. Nothing goes to main until Pranav says so.
   Please run "git merge origin/backend/work" into data/work before your next commit.
3. Decision IDs: Mahil's D-38 to D-40 collided with yours and are now D-60 to D-62. Your D-38 to D-49 are untouched.
   Ranges from now on: Data D-38 to D-49, Backend D-50 to D-59, iOS D-60 to D-69. Next blocks of 10 go in the same order (Data D-70, Backend D-80, iOS D-90).
4. Confirmed from Backend: D-32 (last_value_* names), D-35 (Meal.source values), your replay clock D-45.
5. CONTRACT 1.3 (D-51, answers to an iOS request), the parts relevant to you:
   - Meal.is_standard_breakfast, which Backend fills from replay_meals.is_standard_breakfast
   - Grade.gummi_beats_cgm_only and gummi_beats_last_value, passed straight through from grade(); proud fires only on gummi_beats_cgm_only
   - State.replay_now, the replay clock mapped to today per D-45
   No change is needed in gummi_model or gummi_stream.
6. Your grants for Pranav work. He reads gummi_data and gummi_ml, and downloaded the artifact with them.

B. Ask 1: accuracy, one targeted fix (highest priority)
1. Your eval_results show Gummi beats CGM-only and last value at every horizon, in both meal and quiet windows. For example, 60 min MAE is 12.4 vs 13.4 vs 14.9, and meal windows at 60 min are 16.2 vs 17.3 vs 20.4. No overhaul is needed. My earlier "12.8 vs 11.3" came from your 14-grade pipeline fixture, not results. Sorry for the noise.
2. The real issue is big-spike under-prediction: the bias is -14 mg/dL on average and -40 on the standardized breakfast. It costs the demo twice:
   - forecasts cross 140 less often than real glucose, so the walk nudge fires less
   - the "I predicted 168, it was 172" moment lands less often on big meals
3. Options, all participant-grouped and fit out-of-fold:
   - a) a per-horizon bias correction conditioned on carbs
   - b) a nonlinear carb term, e.g. carbs plus carbs squared, or carb bins
   - c) asymmetric or quantile loss near the peak
4. Ship it only if CV keeps or improves overall MAE at every horizon. Report before and after for MAE by horizon and window, peak bias, peak error, band coverage and fold spread.
5. Keep the interface the same (for_user, cgm_only_forecast, grade, simulate), so Backend just reloads the artifact. Pranav approves any judge-facing number.

C. Ask 2: Agent Bricks sub-agents (the Databricks "agent map")
1. Backend created the Supervisor Agent "Gummi Insights":
   - supervisor_agent_id becc8b0e-f2aa-45dd-bfd5-a4fe1fc166a4
   - endpoint mas-becc8b0e-endpoint
   - MLflow experiment 4330889115534288
   It appears under Agents in the workspace sidebar.
   Design (D-52): the phone's fast path stays the in-App agent with in-process gummi_model. Gummi Insights answers only deep data questions through the App's ask_data tool (8 s timeout, fallback to get_gold_summary), the evening recap, and judge Q&A in Databricks. Speed on the phone is unaffected.
2. Please build these, in this order, and send each ID when ready. Backend attaches them as supervisor tools.
   a) A UC SQL function in workspace.gummi_data:
      get_gold_summary(user_id STRING, days INT) RETURNS TABLE, returning stream_gold_accuracy rows for that user, plus the sample = 'out-of-sample', user_id = 'ALL' rollup. This is also the agent's required evening_recap tool (CONTRACT section 7).
   b) A UC SQL function in workspace.gummi_data:
      meal_response_stats(user_id STRING) RETURNS TABLE, giving per-meal carbs, actual peak rise, predicted peak, and the Gummi, CGM-only and last-value errors.
   c) A Genie space "Gummi Data" over stream_gold_accuracy, stream_gold_fleet, stream_silver_grades, stream_silver_predictions, stream_silver_meals, stream_silver_cgm and replay_meals.
      - Instructions: accuracy is always shown next to CGM-only and last value, replay accuracy is labeled out-of-sample, units are mg/dL, and it never gives treatment, medication or insulin advice.
      - Add 8 to 10 sample questions, for example "Which participant does Gummi predict best?", "How did breakfast predictions do today?", "When does Gummi beat CGM-only?"
      - Run a Genie benchmark eval (databricks genie genie-create-eval-run) for the "visibly measured" story.
   d) An AI/BI dashboard "Gummi live accuracy" on the gold tables, with:
      - Gummi vs CGM-only vs last value, by participant and by meal or quiet window
      - grades over time
      - pipeline lag
      - events per minute
      It stays open live during the demo.
   e) A Knowledge Assistant over a volume holding data/reports: model evaluation, walk_effect.md with the Buffey et al. 2022 citation, the IMU50 check, and the limits paragraph. Label DRAFT numbers as draft until Pranav approves them.
3. Grants for the App's service principal (aa7965f7-bb19-4209-a927-cafe95785e49):
   - EXECUTE on both functions
   - CAN RUN on the Genie space
   - SELECT on the tables behind them (it already has SELECT on gummi_data)

D. Timing and coordination
1. Clean slate: Backend will tell you before the real replay first writes to landing/events/, so you can full-refresh gummi_stream and clear your old test files first. Mock events keep going to landing/mock_events/ (D-50).
2. For rehearsal, filming and judging, Backend asks you to deploy gummi_stream in continuous mode and stop it afterward.
3. Backend's next steps:
   - real model plus real replay of 15 participants in the App: hot state, three-way grading, cgm_only_curve stored per prediction, overlay_walks
   - the real chat and event agent on databricks-gpt-oss-120b with MLflow tracing
   - MLflow GenAI evaluation with custom judges: no medication advice, every number from a tool, the estimate labeled, baselines present
Action needed from you: B first, then C.2 a, b, c, d, e. Send IDs and before/after numbers as each is ready.
Blocks me until: not blocking
Proof: commits 4e0db33, 86d0549 and 5a0e0d5 on backend/work. "databricks supervisor-agents list-supervisor-agents" shows Gummi Insights. The eval_results query is in this session (Gummi beats both baselines at 30, 60, 90, 120 and 180 min, in both windows).
===================
