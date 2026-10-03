# Bean Contract

Contract version: 1.0 (draft, frozen at the end of Phase 0)
Section owners: API and agent (Backend Lead), model interface, pipeline, and data tables (Data Lead), puppet moods and UI copy (iOS Lead).
Changes: CONTRACT CHANGE REQUEST to the owner (docs/PROJECT_OVERVIEW.md section 8).
Placeholders resolved in docs/DECISIONS.md: <WORKSPACE_URL>, <APP_URL>, <CATALOG>, <LLM_ENDPOINT>.

## 1. Conventions

- Times: ISO 8601 with offset in responses, UTC in storage. Replay participants live on a replay clock mapped to today's date.
- Glucose: mg/dL, one decimal.
- IDs: users "u_<name>" for teammates, "p_<participant_id>" for replay participants.
- Errors: HTTP status plus `{"error": {"code": "...", "message": "..."}}`.
- Every response carries `X-Bean-Mode: mock | live`.

## 2. Auth

- Base URL `<APP_URL>/api/v1`. Header `Authorization: Bearer <token>` (D-06). Header `X-User-Id: <user_id>`.
- Dexcom secrets and user tokens never leave the backend.

## 3. Objects

### GlucosePoint
`{ "t": "...", "glucose_mg_dl": 104.0, "kind": "confirmed" }`
kind: "confirmed" (Dexcom or replayed CGM), "estimate" (Bean's view of the delay gap), "forecast".

### BandPoint
`{ "t": "...", "glucose_mg_dl": 128.0, "band_low_mg_dl": 114.0, "band_high_mg_dl": 143.0, "kind": "estimate" }`

### BeanView (Bean's estimate for now, always labeled in the UI)
```json
{ "glucose_mg_dl": 128.4, "band_low_mg_dl": 112.0, "band_high_mg_dl": 145.0,
  "trend": "rising", "as_of": "...", "minutes_since_confirmed": 62, "confidence": "medium" }
```
trend: "rising_fast", "rising", "flat", "falling", "falling_fast". confidence: "high" (band < 25), "medium" (25 to 45), "low" (> 45).

### Prediction
```json
{ "prediction_id": "pr_1", "kind": "meal", "made_at": "...", "about": "Pizza, 2 slices",
  "meal_id": "m_9", "window_start": "...", "window_end": "...",
  "predicted_peak_mg_dl": 168.0, "predicted_curve": ["BandPoint"],
  "baseline_peak_mg_dl": 121.0, "status": "pending" }
```
kind: "meal", "nowcast". status: "pending", "graded". baseline_peak_mg_dl is the last-value guess (the last confirmed reading at made_at).

### Grade
```json
{ "grade_id": "g_1", "prediction_id": "pr_1", "kind": "meal", "graded_at": "...",
  "points": 24, "bean_mae_mg_dl": 7.1, "baseline_mae_mg_dl": 18.4,
  "bean_peak_error_mg_dl": 4.0, "within_band_pct": 88.0,
  "message": "I predicted 168 for the pizza. It was 172. A last-value guess said 121." }
```

### StoryCard (pushed to Today and Home)
```json
{ "card_id": "c_1", "type": "meal_story", "created_at": "...", "title": "Your pizza, two hours later",
  "body": "Peak 172 at 1:40 PM. Your walk after lunch likely helped.", "mood": "proud",
  "attachments": { "grade": "Grade", "meal": "Meal", "curve": ["GlucosePoint"] },
  "actions": [{ "label": "Ask Bean why", "kind": "open_chat", "prompt": "Why did I peak at 172?" }],
  "trace_id": "tr_abc", "generated_by": "agent" }
```
type: "morning_briefing", "meal_logged", "prediction", "meal_story", "grade", "walk_suggested", "walk_summary", "evening_recap", "dexcom_status".
generated_by: "agent" (LLM with tools) or "template" (fleet participants and fallbacks).

### Alert
`{ "alert_id": "...", "type": "walk_suggested", "message": "...", "created_at": "...", "expires_at": "...", "action": {"label": "Start walk", "kind": "start_walk", "minutes": 10} }`
type: "walk_suggested", "high_forecast", "low_forecast", "dexcom_gap". action.kind: "start_walk", "open_chat", "dismiss".

### DexcomStatus
`{ "connected": true, "environment": "sandbox", "data_through": "...", "delay_minutes": 60, "last_sync": "...", "last_error": null, "source": "dexcom_api" }`
source: "dexcom_api", "replay", "none".

### State (GET /state and the "state" live event)
```json
{ "user_id": "...", "following": "p_003", "dexcom": "DexcomStatus",
  "bean_view": "BeanView",
  "confirmed": ["GlucosePoint, past 6 hours"],
  "estimate": ["BandPoint, data_through to now"],
  "forecast": ["BandPoint, now to +2 hours"],
  "mood": "rising", "alert": null, "top_card": "StoryCard or null",
  "pending_predictions": ["Prediction"],
  "today": { "time_in_range_pct": 82.0, "peak_mg_dl": 151.0, "meals": 2, "steps": 4210, "walks": 1,
             "bean_mae_mg_dl": 7.4, "baseline_mae_mg_dl": 13.9 },
  "profile": { "high_line_mg_dl": 140.0, "low_line_mg_dl": 70.0 },
  "model_version": "bean_model_v1", "server_time": "..." }
```

### Meal
```json
{ "meal_id": "m_9", "eaten_at": "...", "source": "chat",
  "items": [{ "name": "pizza", "quantity": 2, "unit": "slice", "carbs_g": 70.0, "sugar_g": 8.0,
              "fiber_g": 4.0, "protein_g": 24.0, "fat_g": 20.0, "calories": 570,
              "nutrition_source": "seed | llm_estimate | dataset", "editable": true }],
  "totals": { "carbs_g": 70.0, "sugar_g": 8.0, "fiber_g": 4.0, "protein_g": 24.0, "fat_g": 20.0, "calories": 570 },
  "prediction_id": "pr_1" }
```

### Simulation
```json
{ "items": ["meal items"], "eat_at": "...",
  "baseline_curve": ["BandPoint"], "with_food_curve": ["BandPoint"],
  "peak_mg_dl": 171.0, "peak_at": "...", "verdict": "go_with_tweak",
  "summary": "With the cookie you'd likely peak near 170.",
  "alternatives": [{ "label": "Half portion", "peak_mg_dl": 152.0 },
                   { "label": "Walk 10 minutes after", "peak_mg_dl": 150.0, "effect_source": "literature" }],
  "method": "model | breakfast_response",
  "prediction_id": "pr_2" }
```
verdict: "go" (peak under high line), "go_with_tweak", "wait". method "breakfast_response" means scaled from the person's standardized breakfast response, and the card says so.

### WalkSummary
`{ "started_at": "...", "ended_at": "...", "minutes": 11, "steps": 1180, "cadence_spm": 107, "intensity": "moderate", "forecast_peak_drop_mg_dl": 14, "effect_source": "literature" }`

### StreamEvent (one JSON line in the landing volume)
```json
{ "event_id": "ev_...", "source": "replay", "user_id": "p_003", "kind": "cgm",
  "t": "...", "released_at": "...", "payload": { "glucose_mg_dl": 104.0 } }
```
source: "replay", "dexcom_sandbox", "iphone", "app". kind with payload: "cgm" {glucose_mg_dl}, "meal" (Meal), "steps" {value, start, end}, "walk" (WalkSummary), "prediction" (Prediction), "grade" (Grade), "card" (StoryCard minus attachments), "chat" {role, text}.
Path: /Volumes/<CATALOG>/bean_data/landing/events/<YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl, one file per 5-second batch.

### FleetEntry, StreamStatus
FleetEntry: `{ "user_id": "p_003", "display_name": "Participant 3", "mood": "calm", "data_through": "...", "sparkline": ["GlucosePoint"], "grades": 14, "bean_mae_mg_dl": 8.2, "baseline_mae_mg_dl": 12.6, "last_grade": "Grade or null" }`
StreamStatus: `{ "running": true, "speed": 60, "delay_minutes": 60, "participants": 16, "replay_clock": "day3T08:15", "events_released": 18450, "events_per_second": 3.2, "pipeline_lag_seconds": 22 }`

## 4. Endpoints (owner: Backend)

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | /health | | `{"status","mode","version"}` |
| GET | /state | | State |
| GET | /live | | server-sent events, section 5 |
| GET | /feed?date= | | `{"cards": [StoryCard]}` |
| GET | /predictions?status= | | `{"predictions": [Prediction]}` |
| GET | /grades?date= | | `{"grades": [Grade]}` |
| POST | /meals | `{"items": [...], "eaten_at": "...", "source": "manual"}` | Meal |
| PATCH | /meals/{meal_id} | `{"items": [...]}` | Meal (prediction recomputed) |
| DELETE | /meals/{meal_id} | | `{"deleted": true}` |
| GET | /meals?date= | | `{"meals": [Meal]}` |
| POST | /simulate | `{"items": [...], "eat_at": null}` | Simulation |
| POST | /vitals | `{"samples": [{"type": "steps", "value": 112, "start": "...", "end": "..."}]}` | `{"accepted": n}` |
| POST | /events | `{"type": "walk_started", "at": "..."}` | `{"ok": true}` |
| GET | /walks/latest | | WalkSummary |
| POST | /chat | `{"message": "...", "conversation_id": null}` | server-sent events, section 6 |
| GET | /profile, PUT /profile | Profile | Profile |
| POST | /follow | `{"user_id": "p_003"}` | State |
| POST | /stream/start | `{"speed": 60, "delay_minutes": 60, "start_at": "day3T06:00"}` | StreamStatus |
| POST | /stream/stop | | StreamStatus |
| GET | /stream/status | | StreamStatus |
| GET | /fleet | | `{"entries": [FleetEntry], "fleet_bean_mae_mg_dl", "fleet_baseline_mae_mg_dl", "stream": StreamStatus}` |
| GET | /fleet/view | | HTML for the projector (browser with Databricks sign-in) |
| GET | /dexcom/status | | DexcomStatus |
| GET | /dexcom/connect | | HTML page starting OAuth (laptop browser) |
| GET | /dexcom/callback | query code, state | HTML "Connected" page |
| POST | /dexcom/disconnect | | `{"ok": true}` (tokens deleted) |
| GET | /engine | | counters: events, predictions, grades, agent runs, last trace id |

Profile: `{ "user_id", "display_name", "high_line_mg_dl": 140.0, "low_line_mg_dl": 70.0, "timezone": "America/New_York", "onboarded": true }`

## 5. Live channel (GET /live, server-sent events)

```
event: state   data: State                  (on any change, at most once per second)
event: card    data: StoryCard
event: grade   data: Grade
event: alert   data: Alert
event: mood    data: {"mood": "proud"}
event: ping    data: {"t": "..."}           (every 15 seconds)
```
The iPhone reconnects with backoff. Fallback: poll GET /state every 15 seconds while the channel is down.

## 6. Chat (POST /chat, server-sent events)

```
event: token   data: {"text": "..."}
event: tool    data: {"name": "log_meal", "status": "start" | "end"}
event: card    data: {"card_type": "meal_saved" | "simulation" | "bean_view" | "walk_suggestion" | "grade", "payload": {...}}
event: mood    data: {"mood": "thinking"}
event: done    data: {"conversation_id": "...", "trace_id": "..."}
event: error   data: {"code": "...", "message": "..."}
```

## 7. Agent (owner: Backend)

Tools (shared by chat and the event-driven agent):

| Tool | Purpose |
|---|---|
| get_state | BeanView, recent confirmed readings, pending predictions |
| get_history(hours) | readings, meals, walks, grades in a window |
| log_meal(items, eaten_at) | save a meal, create a meal prediction |
| simulate_food(items, eat_at) | Simulation plus a stored prediction |
| suggest_walk() | minutes, start time, expected effect with source |
| explain_spike(around_time) | meal, activity, and model contributions around a peak |
| grade_prediction(prediction_id) | Grade, when the window has closed |
| today_summary() | totals plus Bean versus baseline accuracy |
| post_card(type, title, body, attachments, actions) | publish a StoryCard (event-driven agent only) |
| ask_data(question) | Genie space query, only if D-23 enables Genie |

Triggers for the event-driven agent (followed users only, LLM budget per D-22):

| Trigger | Action |
|---|---|
| First reading after 06:00 replay or local time | morning_briefing card |
| Meal logged | meal_logged card with the prediction |
| Meal window closes (2 hours after eating, confirmed data covers the window) | grade_prediction, explain_spike, meal_story card |
| Forecast peak within 60 minutes crosses the high line, cooldown 45 minutes | walk_suggested alert and card |
| Walk completed | walk_summary card |
| 20:00 | evening_recap: predicted versus actual, one lesson, one small experiment for tomorrow |

Agent copy rules: every number from a tool. Bean's estimate is "likely" or "estimate". Dexcom values are "Dexcom reading". No medication or insulin advice. Past or present eating gets logged, food questions get simulated. Walk effects state their source.

## 8. Model interfaces (owner: Data)

```python
from bean_model import GlucoseModel, UserContext
model = GlucoseModel.load(artifact_dir)

ctx = UserContext(user_id, profile, cgm_df, meals_df, walks_df, personal)  # cgm_df: confirmed only

model.estimate_gap(ctx, now) -> list[BandPoint]          # data_through to now
model.forecast(ctx, now, minutes=120, extra_meals=None, extra_walks=None) -> list[BandPoint]
model.bean_view(ctx, now) -> BeanView
model.simulate(ctx, now, items_macros, eat_at) -> dict    # curves, peak, method
model.grade(prediction, confirmed_df) -> dict             # Bean and baseline errors
model.update_personal(ctx, grades) -> dict                # personal offset and carb factor
model.walk_effect(ctx, minutes, intensity) -> dict        # drop and effect_source
model.version -> str
```
Latency: estimate plus forecast under 50 ms per user, simulate under 100 ms. Pure Python plus numpy and pandas plus saved coefficients.

```python
from bean_activity import intensity_from_cadence, summarize_walk
```
Cadence bands from published walking research (cited), optionally validated on IMU50 (D-19).

## 9. Puppet moods (owner: iOS)

| Mood | When | Look |
|---|---|---|
| calm | in range, flat | soft blue, slow breathing, gentle sway |
| rising | rising, forecast under high line | warm yellow, alert eyes, small bounces |
| high | forecast peak at or above high line | orange, puffed, fanning arms |
| dipping | falling fast after a peak | lavender, droopy, yawns |
| low | estimate or forecast at or below low line | pale blue, shivers |
| proud | grade with Bean beating the baseline | gold sparkle, spin |
| happy | walk done or 3 hours in range | green, hops |
| sleepy | 23:00 to 06:00 with no new data | dim, half-closed eyes |
| thinking | UI only, during agent or chat tools | eyes up, hmm |

Priority: low, high, proud (20 seconds), dipping, rising, happy, sleepy, calm.

## 10. Tables (owner: Data, written by the pipeline)

`<CATALOG>.bean_data`: volumes raw_bigideas, landing (and raw_imu50 only if D-19). Batch tables: bronze_cgm, bronze_food_log, bronze_demographics, bronze_hr (ablation only), silver_cgm_5min, silver_meals, replay_cgm, replay_meals. Stream tables: stream_bronze_events, stream_silver_cgm, stream_silver_meals, stream_silver_predictions, stream_silver_grades, stream_silver_cards, stream_gold_fleet, stream_gold_accuracy.
`<CATALOG>.bean_ml`: volume artifacts. Tables eval_results, ablation_results, breakfast_response.
Exact columns get written here in Phase 1 with a version bump.
