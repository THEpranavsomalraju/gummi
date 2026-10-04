=== LEAD UPDATE ===
From: Backend agent
To: Data agent (via human)
Type: REQUEST
Phase: 2/3
Summary: The real replay is running and writing to a NEW landing folder, landing/events_live/. Please point gummi_stream at it, turn on continuous mode and full-refresh: that is the clean slate, and no files get deleted. Also: three of your sub-agents are now attached to Gummi Insights, and the supervisor answers live questions.
Details:
A. What changed and why (Pranav approved; nothing of yours was deleted)
1. Your test files: all 210 files in landing/events/ are COPIED to landing/test_archive_20261003/. The originals are still in events/; I did not delete anything.
2. Instead of clearing events/, the App now writes the real replay to /Volumes/workspace/gummi_data/landing/events_live/ (app.yaml GUMMI_LANDING_DIR). Your fixtures never mix with real data, and events/ stays as your test history.
3. Replay started on the deployed App at day6T05:00, 60x, 15 participants, CGM delay 60 min. After 75 s: 26 files and 231 events landed, 23 predictions, 3 grades, 1 walk alert. Event format is unchanged from my last update (your item 7 rules, sources replay/app, ids m_/pr_/g_/c_ with the meal_id, nowcasts pr_<pid>-now_<n>, released_at = real UTC).
4. Until gold catches up with this session, /fleet shows the App's own live numbers (same grade() output). It switches to stream_gold_accuracy automatically once gold's ALL rollup holds at least half the session's grades, so stale or test rows never reach the projector.
B. Ask 1 (now): repoint the pipeline. I couldn't change your pipeline myself.
1. Set landing_path to /Volumes/workspace/gummi_data/landing/events_live/ in data/resources/gummi_stream.pipeline.yml, so a bundle deploy doesn't revert it. The deployed pipeline config currently says .../landing/events/.
2. Deploy with --var="continuous=true".
3. Run a full refresh of all tables.
4. Reply "clean" with the bronze row count after about 2 minutes. I'll check end-to-end lag on the projector; the App computes pipeline_lag_seconds from max(released_at) in stream_bronze_events.
5. Stop continuous mode after our test to save quota; I'll ping you before rehearsal.
C. Agent Bricks: what's done on my side
1. Attached to supervisor "Gummi Insights" (becc8b0e-f2aa-45dd-bfd5-a4fe1fc166a4):
   - tool gummi-data = your Genie space "Gummi Data" (01f1bf87ea5918298b59e25b38538d16)
   - tool gold-summary = workspace.gummi_data.get_gold_summary
   - tool meal-stats = workspace.gummi_data.meal_response_stats
2. The dashboard "Gummi live accuracy" (01f1bf883268170693784c519c8eb10b) would not attach through the API ("Tool spec must be provided" for every field name I tried). If you know the spec field, attach it as tool "accuracy-dashboard"; otherwise Pranav adds it in the UI.
3. End-to-end test, question "Across all participants, how accurate is Gummi compared with the baselines?":
   - the supervisor chose get_gold_summary itself, read gold and answered with all three numbers, split meal/quiet, labeled out-of-sample
   - it took 55 s cold, so it stays off the phone's fast path (D-52)
   - it read your 14 fixture grades, which is exactly why B matters
D. Still open from my 20:10 request (your queue; I'm not blocking on them)
1. The big-spike bias fix (keep the same interface, report before/after with fold spread).
2. The Knowledge Assistant over data/reports. Send its ID and I'll attach it.
3. App service principal (aa7965f7-bb19-4209-a927-cafe95785e49): EXECUTE on both functions and CAN RUN on the Genie space, if not done yet. The App's ask_data tool calls the supervisor; the evening recap calls get_gold_summary.
E. Branches: backend/work has data/work and ios/work merged; your 42 tests pass there. Please "git merge origin/backend/work" into data/work before your next push. Decision ranges: Data D-38 to D-49 (then D-70s), Backend D-50 to D-59, iOS D-60 to D-69.
Action needed from you: B now (repoint, continuous, full refresh, reply "clean"), then D.
Blocks me until: B blocks only the projector's gold-sourced accuracy and the lag number. The replay, phone and fleet run meanwhile.
Proof: App /engine landing.directory = .../landing/events_live, files_written 26, events_written 231. "databricks supervisor-agents list-tools" shows gummi-data, gold-summary, meal-stats. Commit 3e39e5f on backend/work.
===================
