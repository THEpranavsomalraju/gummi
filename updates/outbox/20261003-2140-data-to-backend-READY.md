=== LEAD UPDATE ===
From: Data agent
To: Backend agent (via human)
Type: READY
Phase: 3 (Data)
Summary: clean. gummi_stream now reads landing/events_live/, runs in continuous mode, and was fully refreshed. Bronze
holds 1,602 rows, all from events_live, with no fixture rows. Steady-state lag is about 6 s.
Details:
1. The repoint is in data/resources/gummi_stream.pipeline.yml (landing_path /Volumes/workspace/gummi_data/landing/
   events_live/), so a bundle deploy keeps it. It was deployed with continuous=true; the pipeline
   b11d910a-48c4-4396-922c-0c249303f33f shows continuous true. Full-refresh update:
   ef244449-6828-49c5-9b11-41f89911c0e0. Nothing was deleted; events/ and test_archive_20261003/ are untouched.
2. Counts:
   - About 2 minutes after the refresh started: 1,392 bronze rows from 140 files. A minute later: 1,602.
   - Rows whose source_file is outside events_live/: 0.
   - By kind at the first count: cgm 1,143, prediction 125, grade 89, meal 27, card 8.
3. Lag (ingested_at minus file landed_at):
   - Last 2 minutes: median 6 s, max 40 s while the backfill caught up.
   - stream_gold_fleet.pipeline_lag_seconds averages the last 10 minutes, so it still includes the backfill (about
     168 s) and settles within 10 minutes.
4. Gold already has the real session, all out-of-sample (mg/dL, DRAFT):

   | Window | Grades | Gummi | CGM-only | Last value |
   |---|---|---|---|---|
   | all | 98 | 13.9 | 14.7 | 15.3 |
   | meal | 49 | 19.4 | 20.6 | 24.8 |
   | quiet | 49 | 8.3 | 8.9 | 5.7 |

   The App is still on the v1.1 artifact; the big-meal model waits at gummi_model_v1_next (see my 21:30 update).
5. Continuous mode stays on for your projector test. Tell Nikhil when you are done and I stop it. You ping me
   before rehearsal.
6. Your list D is answered in my 21:30 update (20261003-2130-data-to-backend-READY.md):
   - spike fix with before and after and fold spread
   - Knowledge Assistant d8755a47-88a6-4c60-8942-99a903a99ad6, endpoint ka-d8755a47-endpoint
   - service principal grants: EXECUTE on both functions, CAN_RUN on Genie, CAN_QUERY on the Knowledge Assistant
   - The dashboard as a supervisor tool: I don't know a working API spec either, so Pranav adds it in the UI.
7. Note: the gummi_stream_spike test job still lands fixtures in events/, which the pipeline no longer reads, so its
   check step would now fail. It stays as a fixture archive; I will not run it against the live pipeline.
Action needed from you: check the lag on the projector, then tell Nikhil to stop continuous mode.
Blocks me until: not blocking
Proof: pipelines get b11d910a: continuous True, landing_path .../events_live/, state RUNNING; SQL counts as above.
===================
