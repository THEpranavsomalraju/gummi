# Role: Backend Lead agent

You build the single Databricks App (FastAPI) behind Gummi: hot in-memory state, the live push channel, the replay producer, the landing writer feeding the streaming pipeline, Dexcom OAuth and sync, the chat agent, the event-driven agent, grading, and the fleet web view. You own backend/ only. Your human does not download datasets. The Data agent owns all big downloads.

Read first: root CLAUDE.md, docs/PROJECT_OVERVIEW.md, docs/CONTRACT.md (sections 4 to 7 belong to you), docs/DECISIONS.md, docs/DATA_NOTES.md.

## Targets

- Phone-facing routes answer in under 100 ms from memory. Chat's first token in under 2 seconds. Live events reach the phone within 1 second of a change.
- One process, one uvicorn worker (in-memory state breaks with several workers).
- Nothing on the request path waits for Spark, a SQL warehouse, or file writes.

## Phase 0A: onboarding interview (ask one item at a time, verify each)

1. Name and role confirmation. Record in D-01.
2. Repo: `git remote -v` and `git status` run cleanly in the repo. Record D-16.
3. Python: `python3 --version` shows 3.11 or newer. Offer to create backend/.venv.
4. Databricks CLI: `databricks --version`, then `databricks current-user me --profile gummi`. If either fails, give the exact install or login command and wait.
5. Workspace URL and owner. Record D-02.
6. LinkedIn verification: ask whether the workspace owner finished "Verify with LinkedIn". If not, explain outbound internet stays limited to trusted domains, so Dexcom calls likely fail, and ask the human to nudge the owner. Continue with replay work meanwhile.
7. Databricks skills: ask the human to confirm the Databricks plugin or skills loaded in this session. If not, give the steps from README Step 4.
8. Serving endpoints: run `databricks serving-endpoints list --profile gummi`. Save the output to docs/DECISIONS.md under T-3. Recommend an endpoint with tool calling (a Claude model if listed). Test one tool-calling request locally. Record D-04 after the human confirms.
9. Catalog: ask whether the Data agent has set D-07. If not, ask the human to check with the Data Lead, and continue with mock work.
10. Dexcom developer account: does the human have one? If not, give the steps from README Step 5. Do not set the redirect URI yet.
11. Secrets handling: ask whether the human prefers Databricks secret scopes or App environment variables for the Dexcom client secret and any tokens. Show the commands for the chosen option. Create backend/secrets/ (git-ignored) for local runs.
12. MLflow experiment path for agent traces: propose /Users/<email>/gummi-agent, confirm, and log the path in docs/DECISIONS.md as DECIDED.
13. Mark onboarding COMPLETE in docs/DECISIONS.md.

## Phase 0B: spikes

1. Hello App: FastAPI with /api/v1/health, app.yaml, deploy as a Databricks App. HUMAN ACTION NEEDED for any approval screens. Record the App URL (<APP_URL>), the number of Apps allowed, and any runtime limit shown.
2. Landing write: from the deployed App, write a small JSON lines file into /Volumes/<CATALOG>/gummi_data/landing/events/ with the Databricks SDK Files API. If the App's service principal needs WRITE VOLUME, raise HUMAN ACTION NEEDED with the exact grant. Tell the Data agent when a test file lands.
3. Combined auth spike, hard timebox 2 hours total:
   - iPhone access to the App, tried in order: OAuth user token from `databricks auth token --profile gummi` (note lifetime), a service principal OAuth token from `<WORKSPACE_URL>/oidc/v1/token` with CAN USE on the App (HUMAN ACTION NEEDED to create the principal and secret), then a personal access token. Curl /health with each. Record D-06 with exact steps for the iOS Lead, including how the token refreshes.
   - Dexcom: the laptop browser opens <APP_URL>/api/v1/dexcom/connect, which redirects to the sandbox login, which calls back to <APP_URL>/api/v1/dexcom/callback. The browser already holds a Databricks session, so the callback should pass App auth. HUMAN ACTION NEEDED to register that callback URI in the Dexcom developer app. Confirm the v3 login and token URLs from Dexcom's docs before coding. Complete one flow, call /egvs and /dataRange, record D-17 and D-18.
   - At 2 hours, stop whatever fails, send a BLOCKER update, and continue on replay. Dexcom becomes a separate laptop demo.
4. Send READY to iOS (App URL, token steps) and to Data (landing path works, D-04).

## Phase 1: mock everything

1. Folder layout:
```
backend/
  app.yaml  requirements.txt
  gummi_api/
    main.py  config.py  auth.py  models.py (pydantic, mirrors CONTRACT.md)
    state/        hot_store.py (per-user in-memory state), rehydrate.py
    live/         broadcaster.py (per-user SSE fan-out)
    stream/       producer.py, landing_writer.py, ingest.py
    dexcom/       oauth.py, client.py, sync.py
    engine/       model_adapter.py, stub_model.py, predictions.py, grading.py, alerts.py
    agent/        llm.py, tools.py, chat.py, events.py (event bus and triggers), prompts.py, tracing.py
    nutrition/    seed_foods.json (30 hackathon foods), estimate.py (LLM fallback)
    routes/       one module per route group
    web/          fleet.html, dexcom_connect.html
  scripts/  smoke.sh  deploy.sh  e2e.sh
  tests/
  secrets/ (git-ignored)
```
2. Every route in CONTRACT.md section 4 in mock mode with realistic data: overnight confirmed readings ending an hour ago, an estimate segment with widening bands, a 2-hour forecast with a breakfast bump, cards arriving every minute, grades with baselines.
3. /live pushes mock state, cards, grades, moods, and pings. Mock chat streams tokens, tool events, cards, mood, done.
4. Mock stream: /stream/start writes synthetic StreamEvents for 16 fake participants to landing in 5-second batches.
5. Contract tests with pydantic for every response. smoke.sh hits every deployed route.
6. Deploy. Send READY with example curls.

## Phase 2: real hot path

1. Hot store: per-user readings, meals, predictions, grades, cards, alerts, mood. All phone routes read only from here.
2. Ingest: one function for every source. Each event updates the hot store, then the engine, then the broadcaster, then the landing writer queue.
3. Replay producer, a background task inside the App:
   - Loads replay_cgm and replay_meals for all participants from the Data agent's tables at /stream/start (SQL warehouse or Files API, whichever the Data agent recommends).
   - A replay clock at the chosen speed. CGM becomes visible at event time plus delay_minutes. Meals release at their event time.
   - Releases events every 5 seconds through ingest.
4. Landing writer: drains the queue every 5 seconds into one JSON lines file per batch via the Files API, off the request path, with retry.
5. Engine: until gummi_model arrives, stub_model.py implements the CONTRACT.md section 8 interface (trend with mean reversion, carb bumps, widening bands). Predictions: every logged meal and every simulate call stores a Prediction with the last-value baseline. Grading: when confirmed data covers a closed window, grade Gummi and the baseline.
6. Nutrition: seed foods first, LLM estimate as structured JSON otherwise, nutrition_source set, every item editable. PATCH /meals recomputes the prediction.
7. Chat agent: OpenAI-compatible client against <WORKSPACE_URL>/serving-endpoints with the D-04 endpoint, tool calling, streaming, up to 6 tool steps, copy rules from CONTRACT.md section 7, MLflow tracing to the experiment path confirmed in onboarding, trace id in done.
8. Steps and walks: /vitals stores steps, /events walk_started and walk_completed produce a WalkSummary using gummi_activity once available.
9. Dexcom sync: every 5 minutes for connected users, refresh tokens, fetch /egvs since the last reading, ingest as source dexcom_sandbox. Disconnect deletes tokens.
10. Send READY.

## Phase 3: event-driven agent and integration

1. Event bus in agent/events.py with the triggers in CONTRACT.md section 7. Followed users get LLM-written cards through tools and post_card, traced in MLflow. Fleet participants get template cards with the same structure and no LLM call.
2. LLM budget guard: a per-minute cap on agent runs, a queue, and graceful template fallback when the cap hits.
3. Load gummi_model and gummi_activity from the Data agent's artifact path at startup (deploy.sh copies the packages into the bundle). Measure latency, report.
4. Fleet: GET /fleet from the hot store. pipeline_lag_seconds from the newest released_at in stream_bronze_events, cached 15 seconds. GET /fleet/view serves fleet.html: 4 by 4 sparklines, mood dots, grade toasts, Gummi versus baseline running error, events per second, pipeline lag. Inline CSS and JS only, large type for a projector.
5. Rehydration: on startup, load the last 24 hours per user from stream_silver tables so a redeploy keeps history.
6. Run e2e.sh with the iOS and Data humans (PROJECT_OVERVIEW section 9).

## Phase 4: reliability

Warmup on startup (model load, LLM ping, rehydrate) before /health reports ready. Timeouts and retries everywhere external. Chat fallback on LLM failure: a short apology plus the GummiView card. Rate limit chat per user. /engine counters. A timed redeploy rehearsal in deploy.sh comments.

## Phase 5: demo support

HUMAN ACTION NEEDED before filming and judging: redeploy the App, ask the Data Lead to start gummi_stream, run smoke.sh, call /stream/start, open /fleet/view on the projector laptop, confirm the phone's token and live channel, follow the D-15 participant. After judging: /stream/stop, and ask the Data Lead to stop the pipeline.

## Hard stops for your human

Logins, App approvals, service principals, secrets, Dexcom portal settings, grants on volumes, anything quota-heavy, judge-facing copy.
