# Gummi: Project Overview

## 1. Product

Gummi is a CGM coach on the iPhone for adults with prediabetes or type 2 diabetes who do not take insulin and wear a Dexcom. A cute, interactive puppet fronts the experience. Gummi predicts where glucose heads after meals, nudges a walk before a predicted spike, answers "can I eat this right now?", and grades every prediction against what actually happened. An agent acts on its own when events happen and posts story cards to the user's day: a morning briefing, a meal story when a meal's two-hour window closes, a grade when delayed readings arrive, an evening recap with one lesson and one small experiment for tomorrow.

Pitch line: "Gummi is a CGM coach that predicts, acts, and checks its own work."

The nowcast engine: Dexcom's API gives third-party apps data one hour late in the US, on purpose, so apps never drive real-time treatment. Gummi respects that. Gummi never replaces the Dexcom readout. Internally, Gummi estimates the missing hour so the coach reasons about the present. The UI shows Gummi's estimate small and clearly labeled, and puts coaching first.

Why this user: Gummi's model trains on BIG IDEAs, a cohort with high-normal to prediabetic glucose. That matches people with prediabetes or type 2 not on insulin. A type 1 user swinging 40 to 400 sits far outside the training data, so Gummi excludes insulin users.

## 2. Hackathon context

- WolfHacks 2026, Databricks track: software on Databricks using agentic AI on wearable streaming data. Goals: an agent producing actionable insights, an app exploring complex datasets with AI, an agentic system using tools, data, and APIs for multi-step tasks.
- Data: BIG IDEAs (Dexcom G6, Empatica E4, food logs, 16 people). IMU50 (wrist IMU, PPG, METs) only if organizers require both datasets (T-2).
- Judging: Track, Technology, Design, Execution.
- Demo: a recorded video of a full day plus a live segment with the real app on Databricks.

## 3. What judges must see

1. A delightful puppet: idle breathing, blinks, taps, moods tied to glucose, a proud spin when a prediction lands close.
2. A live, seamless app: new readings, cards, and grades appear without refresh, through a push channel from the backend.
3. Coaching first: the Home screen leads with the latest coach card, then the puppet, then a compact chart.
4. Predict, then grade: "Can I eat this?" and every meal produce a prediction. Two hours later Gummi grades the prediction: "I predicted 168 for the pizza. It was 172. A last-value guess said 120."
5. The event-driven agent: cards appear because events happened, not because someone typed. The MLflow trace shows the agent's tool calls.
6. A walk loop: forecast crosses the high line, Gummi suggests a walk, live steps count up, the walk card shows minutes and intensity, the forecast responds (labeled "literature" or "your data").
7. Streaming at scale: 16 BIG IDEAs participants stream through a Databricks streaming pipeline at once, shown on a fleet view with grades landing and a running accuracy number next to the baseline.
8. A real Dexcom connection through the official sandbox.
9. Honest science: participant-grouped evaluation, the reproduced published baseline, the meal ablation result, baselines next to every number.

## 4. UI map (iPhone)

- Home: the latest coach card on top (swipeable stack), the puppet in the middle, a compact chart at the bottom (confirmed Dexcom solid, Gummi's estimate dotted with band, forecast dashed with band, 2 hours ahead), the safety line "Not for treatment decisions. Check your Dexcom app for current readings." A chat bubble button beside the puppet opens chat.
- Today: a vertical feed of story cards for the day: briefing, meals, predictions, grades, walks, recap.
- Chat: a sheet over Home. Streaming replies, cards inline, editable meal portions. Keyboard dictation works through the system keyboard.
- Fleet: a 4 by 4 grid of mini charts for the streaming participants, grade toasts, running error versus baseline, events per second, pipeline lag. Tap a tile to follow that participant on the phone.
- Settings: connection status (backend, Dexcom), follow participant, demo controls, puppet 2D or 3D, safety info.

## 5. Architecture

```
SOURCES (no physical Dexcom needed)
  A. Replay producer: 16 BIG IDEAs participants (CGM + meals), released at a chosen speed,
     CGM delayed one hour like the real Dexcom API
  B. Dexcom sandbox: real OAuth, real API, simulated users
  C. iPhones: real steps and walks, live
          |
          v
DATABRICKS APP (FastAPI, single worker)                      backend/
  Ingest (one code path for A, B, C)
  HOT STATE in memory: per-user readings, meals, predictions, grades, mood, cards
  gummi_model in process (CPU, milliseconds): estimate, forecast, simulate, grade
  Event bus -> event-driven agent (LLM on a Databricks serving endpoint, MLflow tracing)
  Chat agent (same tools)
  GET /live (server-sent events) pushes state, cards, mood, grades to iPhones
  Fleet web view for the projector
  Landing writer: every event, prediction, grade, card -> JSON lines batch every 5 s
          |
          v
UNITY CATALOG VOLUME <CATALOG>.gummi_data.landing / events/
          |
          v
LAKEFLOW DECLARATIVE PIPELINE "gummi_stream" (continuous mode if allowed, D-21)   data/
  Auto Loader -> stream_bronze_events
  -> stream_silver_cgm, stream_silver_meals, stream_silver_predictions, stream_silver_grades, stream_silver_cards
  -> stream_gold_fleet, stream_gold_accuracy (Gummi versus baseline by participant and window type)
          |
          v
DELTA TABLES (durable history, rehydration on App restart, Genie space if available)
MLFLOW: gummi_model registered, evaluation runs, agent traces
```

Why this shape: the phone never waits on Spark. The App answers in milliseconds from memory and pushes updates instantly. The pipeline makes every event durable, queryable, and visible in Databricks within seconds, which is the streaming story judges look for.

## 6. Streaming and Free Edition limits

- Free Edition runs serverless compute only.
- Serverless notebooks and jobs support only AvailableNow and Once streaming triggers. Time-based triggers fail with INFINITE_STREAMING_TRIGGER_NOT_SUPPORTED. Every Structured Streaming query in notebooks or jobs sets `.trigger(availableNow=True)`.
- Continuous streaming on serverless runs as a Lakeflow declarative pipeline in continuous mode (D-21). Fallback: the same pipeline in triggered mode every minute.
- Outbound internet is limited to trusted domains until the workspace owner completes LinkedIn verification.
- Apps: limited count per account, and apps may stop after a runtime window. One App serves everything. Redeploy before filming and judging.
- Model serving: no GPU. gummi_model runs inside the App on CPU.
- Fair usage quotas: run the continuous pipeline only during rehearsal, filming, and judging. Event-driven LLM calls run only for followed users. Fleet participants get template cards without LLM calls.
- Event volume: 16 participants at 60x speed is about 3 CGM events per second. Never stream raw accelerometer samples.

## 7. Phases

Each phase ends with READY from every lead and a merge to main.

### Phase 0: onboarding and spikes
- Every agent: onboarding interview from its role file, then spikes.
- Combined auth spike, hard timebox 2 hours, Backend lead with iOS support: App reachable from the iPhone with a bearer token, token lifetime, Dexcom sandbox OAuth through the App's web page. If not working at 2 hours: run on replay, show the Dexcom connection separately from a laptop browser.
- Backend: App deploys, writes to the landing volume, serving endpoint chosen.
- Data: download path chosen and tested, real file headers printed, streaming spike pipeline reads a test file from landing.
- iOS: app on the iPhone, HealthKit steps permission works.
Exit: no PENDING item blocks Phase 1.

### Phase 1: skeletons and data
- Backend: every route in mock mode, including /live pushing mock updates, mock stream to landing.
- Data: BIG IDEAs loaded, published baseline reproduced near 13.9 mg/dL RMSE at 30 minutes, gummi_stream pipeline running on mock events, exploration findings shared.
- iOS: app shell, 2D puppet with moods, Home, Today, chat UI on mock, live channel connected.
Exit: the phone updates live from the deployed App with mock data.

### Phase 2: core
- Data: gummi_model v1 (estimate, 2-hour forecast, simulate, grade, personal offset), meal ablation result, breakfast-response fallback, replay tables.
- Backend: replay producer, hot state, real grading with baselines, prediction tracking, chat agent with tools and tracing, Dexcom sync, landing writer.
- iOS: real data on Home and Today, chat cards, grade animations, fleet screen, walk flow with live steps.
Exit: each piece works on real or replayed data.

### Phase 3: agent and integration
- Backend: event bus and event-driven agent (morning, meal window, grade, high forecast, evening recap), fleet web view, rehydration on restart.
- Data: gold accuracy tables, Genie space if available (D-23), walk effect source settled (D-11).
- iOS: local notifications from cards and alerts, follow participant, polish, 3D puppet attempt if Phase 3 core passes.
Exit: the end-to-end script in section 9 passes on the phone.

### Phase 4: proof and polish
- Data: final evaluation charts for slides, honest summary paragraph.
- Backend: warmup, timeouts, retries, /engine counters.
- iOS: accessibility pass, error states, filming mode.
Exit: a teammate runs the app through a full replay day with no crash.

### Phase 5: video and pitch
- Film, edit, rehearse the live segment, run the pre-demo checklist.

## 8. Protocols

ASSUMED entries: small reversible choices get logged in docs/DECISIONS.md as ASSUMED with one line of reasoning, then work continues.

Human checkpoint:
```
=== HUMAN ACTION NEEDED ===
Who: <role>
Why: <one sentence>
Steps:
  1. <exact step>
Tell me afterward: <what to paste back>
I am paused on this task. Meanwhile I am working on: <next unblocked task or "nothing">
===========================
```

Question:
```
=== QUESTION ===
Context: <one or two sentences>
Options:
  A) <option> (recommended, because ...)
  B) <option>
Reply with a letter or your own answer. If no reply in 20 minutes, I proceed with A and log it as ASSUMED.
================
```
Exception: questions about secrets, money, deletions, contract changes, or judge-facing claims never auto-proceed.

Lead Update (file in updates/outbox/<YYYYMMDD-HHMM>-<from>-to-<to>-<type>.md, printed in full):
```
=== LEAD UPDATE ===
From: <role> agent
To: <role> agent (via human)
Type: READY | BLOCKER | REQUEST | CONTRACT CHANGE REQUEST | CONTRACT CHANGE APPROVED | FYI | QUESTION
Phase: <n>
Summary: <one sentence>
Details: <exact names, paths, routes, versions, numbers>
Action needed from you: <ask or "none">
Blocks me until: <time or "not blocking">
Proof: <command output, URL, screenshot path>
===================
```
Contract changes go to the section owner (API: Backend, model and data tables: Data, puppet and UI copy: iOS), who edits docs/CONTRACT.md, bumps the version, and sends an FYI to the third team.

## 9. End-to-end script (Phase 3 exit)

1. Start the gummi_stream pipeline and the replay producer. The fleet view fills, grades land.
2. On the phone, follow the D-15 participant. Home shows the morning briefing card and the puppet waking up.
3. In chat, log "two waffles and coffee". A meal card appears with editable portions and a prediction.
4. Ask "can I eat a cookie now?" Two curves, a verdict, alternatives.
5. The forecast crosses the high line. A walk card and a local notification appear. Start the walk, steps count live, the walk summary appears.
6. Two hours of replay later, the meal story card and the prediction grade appear on their own, with the baseline next to Gummi.
7. Evening recap card appears.
8. In Databricks, stream tables grow, the MLflow trace for the meal story shows the agent's tool calls.
9. Connect the Dexcom sandbox from the laptop browser, and the phone shows Dexcom connected.

## 10. Video and live segment

Video: morning briefing, chat meal logging, "can I eat this", walk nudge and walk, the meal story and grade arriving on their own, the fleet view on 16 participants, the evening recap, a quick Databricks tour (pipeline graph, tables growing, MLflow trace).

Live segment: the real phone on stage, ask Gummi one question, show a grade landing on the fleet view, show the pipeline graph running. Say plainly: "No one here wears a Dexcom. Gummi uses Dexcom's sandbox for the real connection and streams 16 real participants from the BIG IDEAs study through Databricks."

## 11. Judge questions, one-line answers (fill numbers from real results)

1. Why not just open the Dexcom app? Dexcom shows the number. Gummi coaches: predictions, walk nudges, "can I eat this", and checks its own predictions.
2. Dexcom delays data on purpose. Are you working around that? No. Gummi never shows its estimate as your current glucose and never supports treatment decisions. The estimate powers coaching only.
3. Who is the user? Adults with prediabetes or type 2 not on insulin, matching the cohort Gummi trains on.
4. How accurate is Gummi versus repeating the last value? Every grade shows both. Overall: Gummi X mg/dL, last-value Y mg/dL, after meals: Gummi X2, last-value Y2.
5. Trained on 16 women. Does it generalize? Not proven beyond this cohort. Evaluation is participant-grouped, and the personal offset adapts per user. We say so on the slide.
6. Does logging meals help? Our ablation: <result with fold spread>.
7. Where does the walk effect come from? <literature citation> until a person's own data passes a permutation test. The label shows which.
8. What does IMU50 contribute? <only if used: validates the cadence-to-intensity bands against wrist data>.
9. What's agentic beyond a chatbot? An event-driven agent investigates on its own when meals end, readings arrive, or the day closes, and grades its own predictions.
10. Where's the streaming, and why Databricks? Events land in a volume, a Lakeflow declarative pipeline turns them into streaming tables in Unity Catalog, MLflow tracks the model and every agent run.
11. What if the LLM gets the food wrong? Every meal card has editable portions, and the prediction updates.
12. Privacy? The demo uses a public de-identified dataset and Dexcom's sandbox. Dexcom tokens stay server-side. Disconnect deletes stored tokens.
13. What is live and what is replayed? The app, backend, pipeline, agent, steps, and Dexcom sandbox connection are live. Glucose data is replayed from BIG IDEAs.

## 12. Scope

Kept: puppet (2D first, 3D upgrade), live push, coach cards, chat, predict-then-grade, event-driven agent, walk loop, fleet, streaming pipeline, Dexcom sandbox, participant-grouped evaluation, meal ablation.
Cut: fingersticks, USDA lookup (LLM plus 30 seed foods plus editable portions), Lakebase (Delta plus in-memory hot state), Kalman filter (simple personal offset), nightly job, heart rate in the model, Speech framework (system keyboard dictation), in-app proof screen (slides instead).
Stretch, only after Phase 4 exit: 3D puppet if not done, Genie tool in chat, Apple Watch steps, a personal walk-effect test shown in the app.
