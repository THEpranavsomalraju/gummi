# Gummi Contract

Contract version: 1.4 (draft, frozen at the end of Phase 0)
Changelog: 1.4 (2026-10-03, Backend Lead, answers iOS CONTRACT CHANGE REQUEST 1-6): documentation only, no shape changes. Grade.gummi_beats_cgm_only nullable; WalkSummary.intensity and effect_source values listed; DexcomStatus.environment values; date query format; MealItem.unit may be ""; SSE comment lines.
Changelog: 1.3 (2026-10-03, Backend Lead, human-delegated, answers iOS REQUEST 20261003-1815): State gains replay_now and stream; Grade gains gummi_beats_cgm_only and gummi_beats_last_value; Meal gains is_standard_breakfast; chat card_type gains "meal_due"; meal_due cards resolve by upsert; attachments keys per card type; walk_completed body; nullable fields marked; error codes listed. All additive.
Changelog: 1.2 (2026-10-03, Backend Lead, human-approved D-36): State gains upcoming_due for background meal_due notifications. Additive, no other shape changes.
Section owners: API and agent (Backend Lead), model interface, pipeline, and data tables (Data Lead), puppet moods and UI copy (iOS Lead).
Changes: CONTRACT CHANGE REQUEST to the owner (docs/PROJECT_OVERVIEW.md section 8).
Placeholders resolved in docs/DECISIONS.md: <WORKSPACE_URL>, <APP_URL>, <CATALOG>, <LLM_ENDPOINT>.

## v1.1 changes

v1.1, agreed by all three leads.

1. Out-of-sample replay: 5 participant-grouped fold models plus a participant-to-fold map. Each replay participant is predicted only by the fold model that never saw them. The full model serves teammate users and the Dexcom sandbox. Fleet and gold accuracy are labeled "out-of-sample" (D-26).
2. Acting-as: following p_xxx means acting as p_xxx. Replay withholds p_xxx's meals and pushes a meal_due card with a one-tap log. Unlogged after 10 replay minutes, the backend logs it as replay_auto. Non-matching chat meals become simulations (D-27).
3. Walk honesty: phone walks overlay the followed participant. Graded windows overlapping a phone walk on replayed data get walk_effect_graded false and are excluded from accuracy tables (D-28).
4. Notifications: in-app banners in the foreground, local notifications scheduled ahead from StreamStatus.replay_anchor in the background (D-29).
5. Databricks in the loop: /fleet accuracy comes from stream_gold_accuracy via the SQL warehouse. New tool get_gold_summary, required by evening_recap. gummi_model loads from the Unity Catalog volume and is registered in MLflow.
6. Stronger baseline: every prediction and grade carries Gummi, CGM-only, and last value. Proud only when Gummi beats CGM-only.
7. Replay controls: POST /stream/pause, /stream/resume, /stream/speed.
8. Dexcom sandbox is status-only by default, optional time-shifted mode (D-30).
9. Fleet grid lives only on the projector web view. The phone gets a Follow picker (D-31).

Defaults set while writing v1.1, ASSUMED until the owner confirms: last_value_* field names (D-32), CGM-only definition (D-33), fleet cache and model loading (D-34), Meal.source values and due_id (D-35), background meal_due notifications (D-36, DECIDED in 1.2: State.upcoming_due), excluded participants not replayed (D-37).

## 1. Conventions

- Times: ISO 8601 with offset in responses, UTC in storage. Replay participants live on a replay clock mapped to today's date.
- Glucose: mg/dL, one decimal.
- IDs: users "u_<name>" for teammates, "p_<participant_id>" for replay participants.
- Errors: HTTP status plus `{"error": {"code": "...", "message": "..."}}`.
- Every response carries `X-Gummi-Mode: mock | live`.
- Nullable (1.3): every field marked "or null" below may be null. In particular: State.following, acting_as, replay_now, alert, top_card; Prediction.meal_id, cgm_only_peak_mg_dl; Grade.cgm_only_mae_mg_dl and Grade.gummi_beats_cgm_only (both null when no CGM-only curve was stored; treat null as "not proud" and show "CGM-only n/a"); State.today.*_mae_mg_dl (null before the first grade of the day); FleetEntry.data_through, *_mae_mg_dl and last_grade (null before data or the first grade); StreamStatus.replay_clock, replay_anchor.*, pipeline_lag_seconds (null when stopped or unknown); DexcomStatus.data_through, last_sync, last_error; StoryCard.attachments, trace_id. Before any CGM data, State.gummi_view is null and confirmed, estimate, forecast are empty.
- Error codes (1.3): bad_request (400), unauthorized (401, from the App; the Databricks proxy's own 401 has an empty body), not_found (404), method_not_allowed (405), due_already_logged (409), no_cgm_data (409: simulate or chat simulation while not following anyone), invalid (422), rate_limited (429), internal (500), warming_up (503: /stream/start before the model and replay tables finish loading; /health then reports status "warming_up"), llm_unavailable (503, chat only, sent as an SSE error event). GET /walks/latest returns 404 not_found before the first walk.
- Comparisons: every accuracy number carries three values: gummi, cgm_only (the published CGM-only linear method, one model per horizon, fold-matched, D-33), and last_value (persistence). Numbers for replay participants are labeled "out-of-sample".

## 2. Auth

- Base URL `<APP_URL>/api/v1`. Header `Authorization: Bearer <token>` (D-06). Header `X-User-Id: <user_id>`.
- Dexcom secrets and user tokens never leave the backend.

## 3. Objects

### GlucosePoint
`{ "t": "...", "glucose_mg_dl": 104.0, "kind": "confirmed" }`
kind: "confirmed" (Dexcom or replayed CGM), "estimate" (Gummi's view of the delay gap), "forecast".

### BandPoint
`{ "t": "...", "glucose_mg_dl": 128.0, "band_low_mg_dl": 114.0, "band_high_mg_dl": 143.0, "kind": "estimate" }`

### GummiView (Gummi's estimate for now, always labeled in the UI)
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
  "cgm_only_peak_mg_dl": 139.0, "last_value_peak_mg_dl": 121.0, "status": "pending" }
```
kind: "meal", "nowcast". status: "pending", "graded". cgm_only_peak_mg_dl comes from model.cgm_only_forecast at made_at. last_value_peak_mg_dl is the last-value guess (the last confirmed reading at made_at).

### Grade
```json
{ "grade_id": "g_1", "prediction_id": "pr_1", "kind": "meal", "graded_at": "...",
  "points": 24, "gummi_mae_mg_dl": 7.1, "cgm_only_mae_mg_dl": 11.2, "last_value_mae_mg_dl": 18.4,
  "gummi_peak_error_mg_dl": 4.0, "within_band_pct": 88.0, "walk_effect_graded": true,
  "gummi_beats_cgm_only": true, "gummi_beats_last_value": true,
  "message": "I predicted 168 for the pizza. It was 172. CGM-only said 139, last value said 121." }
```
gummi_beats_cgm_only and gummi_beats_last_value (1.3) come straight from gummi_model.grade; the proud mood fires only when gummi_beats_cgm_only is true, on the phone and on the backend. walk_effect_graded is false when the window overlaps a phone walk on replayed data. The card then says "Walk effect not graded (replayed data)", and accuracy tables exclude the window.

### StoryCard (pushed to Today and Home)
```json
{ "card_id": "c_1", "type": "meal_story", "created_at": "...", "title": "Your pizza, two hours later",
  "body": "Peak 172 at 1:40 PM. Your walk after lunch likely helped.", "mood": "proud",
  "attachments": { "grade": "Grade", "meal": "Meal", "curve": ["GlucosePoint"] },
  "actions": [{ "label": "Ask Gummi why", "kind": "open_chat", "prompt": "Why did I peak at 172?" }],
  "trace_id": "tr_abc", "generated_by": "agent" }
```
type: "morning_briefing", "meal_due", "meal_logged", "prediction", "meal_story", "grade", "walk_suggested", "walk_summary", "evening_recap", "dexcom_status".
generated_by: "agent" (LLM with tools) or "template" (fleet participants and fallbacks).
actions[].kind: "open_chat", "log_due_meal" (carries "due_id", calls POST /meals/due/{due_id}/log).
attachments keys (1.3), each optional: meal_logged -> "meal" (Meal), "prediction" (Prediction); prediction -> "prediction"; grade and meal_story -> "grade" (Grade), "meal" (Meal), "curve" ([GlucosePoint]); walk_summary -> "walk" (WalkSummary); walk_suggested -> "alert" (Alert); meal_due, morning_briefing, evening_recap, dexcom_status -> none.
Upsert (1.3): cards are keyed by card_id. A card event with a card_id the phone already holds replaces it. When a due meal is logged (replay_due or replay_auto), Backend re-sends that meal_due card with actions [] and a body ending "Logged.", then sends a new meal_logged card.
meal_due example: `{ "type": "meal_due", "title": "Lunch time for Participant 3", "body": "Turkey sandwich and an apple", "actions": [{ "label": "Log it", "kind": "log_due_meal", "due_id": "d_12" }] }`

### Alert
`{ "alert_id": "...", "type": "walk_suggested", "message": "...", "created_at": "...", "expires_at": "...", "action": {"label": "Start walk", "kind": "start_walk", "minutes": 10} }`
type: "walk_suggested", "high_forecast", "low_forecast", "dexcom_gap". action.kind: "start_walk", "open_chat", "dismiss".

### DexcomStatus
`{ "connected": true, "environment": "sandbox", "data_through": "...", "delay_minutes": 60, "last_sync": "...", "last_error": null, "source": "dexcom_api", "ingest_mode": "status_only" }`
environment: "sandbox" or "production". source: "dexcom_api", "replay", "none". ingest_mode: "status_only" (default: connection, data range, and last sync only, never feeds coaching or hot state) or "time_shifted" (optional, labeled "Sandbox (time-shifted)").

### State (GET /state and the "state" live event)
```json
{ "user_id": "...", "following": "p_003", "acting_as": "p_003", "dexcom": "DexcomStatus",
  "gummi_view": "GummiView",
  "confirmed": ["GlucosePoint, past 6 hours"],
  "estimate": ["BandPoint, data_through to now"],
  "forecast": ["BandPoint, now to +2 hours"],
  "mood": "rising", "alert": null, "top_card": "StoryCard or null",
  "pending_predictions": ["Prediction"],
  "today": { "time_in_range_pct": 82.0, "peak_mg_dl": 151.0, "meals": 2, "steps": 4210, "walks": 1,
             "gummi_mae_mg_dl": 7.4, "cgm_only_mae_mg_dl": 10.8, "last_value_mae_mg_dl": 13.9 },
  "profile": { "high_line_mg_dl": 140.0, "low_line_mg_dl": 70.0 },
  "upcoming_due": [{ "due_id": "d_12", "due_at": "...", "title": "Lunch time for Participant 12", "body": "Turkey sandwich and an apple" }],
  "replay_now": "...", "stream": "StreamStatus",
  "model_version": "gummi_model_v1", "server_time": "..." }
```
acting_as: the replay participant the user acts as (user_id), or null.
server_time is the wall clock. replay_now (1.3) is the replay clock mapped to today (D-45), the "now" for the chart, estimate, and forecast while acting as a replay participant; null when not acting as anyone or the stream is stopped. stream (1.3) is the current StreamStatus, so every state event carries it.
upcoming_due (1.2, D-36): the acted-as participant's withheld meals coming due in the next 6 replay hours, oldest first, empty when not acting as anyone or the stream is stopped or paused. due_at is wall-clock time (already converted from the replay clock), so the phone schedules local notifications straight from it. Recomputed and pushed in a state event on every pause, resume, speed change, follow, and when a meal comes due. Steps and walks in today belong to the teammate user and display as an overlay on the followed participant.

### Meal
```json
{ "meal_id": "m_9", "eaten_at": "...", "source": "chat",
  "items": [{ "name": "pizza", "quantity": 2, "unit": "slice", "carbs_g": 70.0, "sugar_g": 8.0,
              "fiber_g": 4.0, "protein_g": 24.0, "fat_g": 20.0, "calories": 570,
              "nutrition_source": "seed | llm_estimate | dataset", "editable": true }],
  "totals": { "carbs_g": 70.0, "sugar_g": 8.0, "fiber_g": 4.0, "protein_g": 24.0, "fat_g": 20.0, "calories": 570 },
  "is_standard_breakfast": false, "prediction_id": "pr_1" }
```
MealItem.unit is always a string and may be "" when the source has no unit; quantity is always a number.
is_standard_breakfast (1.3): true for the study's standardized breakfast (Data's silver_meals flag), false otherwise.
source: "chat", "manual", "replay" (meals of participants nobody follows), "replay_due" (the user tapped Log it on a meal_due card), "replay_auto" (auto-logged 10 replay minutes after it came due) (D-35).

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
intensity: "sedentary" (0 steps/min), "light" (1 to 99), "moderate" (100 to 129), "vigorous" (130+) (D-44). effect_source: "literature" or "your data" (with a space).

### StreamEvent (one JSON line in the landing volume)
```json
{ "event_id": "ev_...", "source": "replay", "user_id": "p_003", "kind": "cgm",
  "t": "...", "released_at": "...", "payload": { "glucose_mg_dl": 104.0 } }
```
source: "replay", "dexcom_sandbox", "iphone", "app". kind with payload: "cgm" {glucose_mg_dl}, "meal" (Meal), "steps" {value, start, end}, "walk" (WalkSummary), "prediction" (Prediction), "grade" (Grade), "card" (StoryCard minus attachments), "chat" {role, text}.
Path: /Volumes/<CATALOG>/gummi_data/landing/events/<YYYYMMDDTHHMMSS>_<source>_<seq>.jsonl, one file per 5-second batch.

### FleetEntry, StreamStatus
FleetEntry: `{ "user_id": "p_003", "display_name": "Participant 3", "mood": "calm", "data_through": "...", "sparkline": ["GlucosePoint"], "grades": 14, "gummi_mae_mg_dl": 8.2, "cgm_only_mae_mg_dl": 10.1, "last_value_mae_mg_dl": 12.6, "last_grade": "Grade or null" }`
Accuracy fields come from stream_gold_accuracy (out-of-sample). Sparkline and mood come from hot state.
StreamStatus: `{ "running": true, "paused": false, "speed": 60, "delay_minutes": 60, "participants": 16, "replay_clock": "day3T08:15", "replay_anchor": { "replay_time": "...", "wall_time": "..." }, "events_released": 18450, "events_per_second": 3.2, "pipeline_lag_seconds": 22 }`
replay_anchor pairs a replay time with a wall-clock time. With speed, the phone converts any replay time to wall-clock time to schedule local notifications. It changes on pause, resume, and speed changes.

## 4. Endpoints (owner: Backend)

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | /health | | `{"status","mode","version"}` |
| GET | /state | | State |
| GET | /live | | server-sent events, section 5 |
| GET | /feed?date= | | `{"cards": [StoryCard]}`. date is YYYY-MM-DD in the profile timezone, compared with the local date of created_at. While acting as a replay participant, dates are on the replay clock mapped to today (D-45), so today's date shows the replayed day. Same rule for /grades and /meals |
| GET | /predictions?status= | | `{"predictions": [Prediction]}` |
| GET | /grades?date= | | `{"grades": [Grade]}` |
| POST | /meals | `{"items": [...], "eaten_at": "...", "source": "manual"}` | Meal |
| PATCH | /meals/{meal_id} | `{"items": [...]}` | Meal (prediction recomputed) |
| DELETE | /meals/{meal_id} | | `{"deleted": true}` |
| GET | /meals?date= | | `{"meals": [Meal]}` |
| POST | /meals/due/{due_id}/log | | Meal (source "replay_due"). 409 due_already_logged if it was logged already |
| POST | /simulate | `{"items": [...], "eat_at": null}` | Simulation |
| POST | /vitals | `{"samples": [{"type": "steps", "value": 112, "start": "...", "end": "..."}]}` | `{"accepted": n}` |
| POST | /events | `{"type": "walk_started", "at": "..."}` or `{"type": "walk_completed", "at": "...", "started_at": "...", "steps": 1180, "cadence_spm": 107}` | `{"ok": true}`. The WalkSummary arrives as a walk_summary card and from GET /walks/latest |
| GET | /walks/latest | | WalkSummary |
| POST | /chat | `{"message": "...", "conversation_id": null}` | server-sent events, section 6 |
| GET | /profile, PUT /profile | Profile | Profile |
| POST | /follow | `{"user_id": "p_003"}`, or `{"user_id": null}` to unfollow | State |
| POST | /stream/start | `{"speed": 60, "delay_minutes": 60, "start_at": "day3T06:00"}` | StreamStatus |
| POST | /stream/stop | | StreamStatus |
| POST | /stream/pause | | StreamStatus |
| POST | /stream/resume | | StreamStatus |
| POST | /stream/speed | `{"speed": 10}` | StreamStatus |
| GET | /stream/status | | StreamStatus |
| GET | /fleet | | `{"entries": [FleetEntry], "fleet_gummi_mae_mg_dl", "fleet_cgm_only_mae_mg_dl", "fleet_last_value_mae_mg_dl", "stream": StreamStatus}`. Accuracy from stream_gold_accuracy via the SQL warehouse, refreshed in the background every 15 to 30 seconds, never on the request path (D-34). |
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
Mood ownership (1.3): State.mood and mood events are the truth, including the 20-second proud expiry, which Backend runs. The phone adds only thinking and talking locally.
Lines starting with ":" are SSE comments (the stream opens with ": connected"); clients ignore them.
The iPhone reconnects with backoff. Fallback: poll GET /state every 15 seconds while the channel is down. iOS suspends backgrounded apps, so the phone closes /live in the background and reconnects plus refetches /state on foreground.

## 6. Chat (POST /chat, server-sent events)

```
event: token   data: {"text": "..."}
event: tool    data: {"name": "log_meal", "status": "start" | "end"}
event: card    data: {"card_type": "meal_saved" | "simulation" | "gummi_view" | "walk_suggestion" | "grade" | "meal_due", "payload": {...}}
event: mood    data: {"mood": "thinking"}
event: done    data: {"conversation_id": "...", "trace_id": "..."}
event: error   data: {"code": "...", "message": "..."}
```

## 7. Agent (owner: Backend)

Tools (shared by chat and the event-driven agent):

| Tool | Purpose |
|---|---|
| get_state | GummiView, recent confirmed readings, pending predictions |
| get_history(hours) | readings, meals, walks, grades in a window |
| log_meal(items, eaten_at) | save a meal, create a meal prediction |
| simulate_food(items, eat_at) | Simulation plus a stored prediction |
| suggest_walk() | minutes, start time, expected effect with source |
| explain_spike(around_time) | meal, activity, and model contributions around a peak |
| grade_prediction(prediction_id) | Grade, when the window has closed |
| today_summary() | totals plus Gummi versus CGM-only and last-value accuracy |
| get_gold_summary(user_id, days) | accuracy and meal stats from the gold tables (stream_gold_accuracy) |
| post_card(type, title, body, attachments, actions) | publish a StoryCard (event-driven agent only) |
| ask_data(question) | Genie space query, only if D-23 enables Genie |

Triggers for the event-driven agent (followed users only, LLM budget per D-22):

| Trigger | Action |
|---|---|
| First reading after 06:00 replay or local time | morning_briefing card |
| Meal due (a withheld food-log meal of the acted-as participant reaches its time) | meal_due card with the real meal text and a Log it action. Not logged within 10 replay minutes: log it with source "replay_auto" |
| Meal logged | meal_logged card with the prediction |
| Meal window closes (2 hours after eating, confirmed data covers the window) | grade_prediction, explain_spike, meal_story card |
| Forecast peak within 60 minutes crosses the high line, cooldown 45 minutes | walk_suggested alert and card |
| Walk completed | walk_summary card |
| 20:00 | evening_recap: predicted versus actual from get_gold_summary (required), one lesson, one small experiment for tomorrow |

Agent copy rules: every number from a tool. Gummi's estimate is "likely" or "estimate". Dexcom values are "Dexcom reading". No medication or insulin advice. Past or present eating gets logged, food questions get simulated. Walk effects state their source.
Simulation rule: while acting as a replay participant, a free-text chat meal that does not match the due meal becomes a simulation, not a logged meal, and the reply says so ("I simulated that, since Participant 3's real meals come from the study log").

## 8. Model interfaces (owner: Data)

```python
from gummi_model import GlucoseModel, UserContext
model = GlucoseModel.load(artifact_dir)   # loads the full model, all 5 fold models, and the participant-to-fold map

model.fold_of(user_id) -> int | None                     # fold for a replay participant, None for teammates and the sandbox
m = model.for_user(user_id)                              # fold model that never saw user_id, or the full model

ctx = UserContext(user_id, profile, cgm_df, meals_df, walks_df, personal)  # cgm_df: confirmed only

m.estimate_gap(ctx, now) -> list[BandPoint]              # data_through to now
m.forecast(ctx, now, minutes=120, extra_meals=None, extra_walks=None) -> list[BandPoint]
m.cgm_only_forecast(ctx, now, minutes=120) -> list[BandPoint]   # CGM-only linear baseline, fold-matched
m.gummi_view(ctx, now) -> GummiView
m.simulate(ctx, now, items_macros, eat_at) -> dict        # curves, peak, method
m.grade(prediction, confirmed_df) -> dict                 # Gummi, CGM-only, and last-value errors
m.update_personal(ctx, grades) -> dict                    # personal offset and carb factor
m.walk_effect(ctx, minutes, intensity) -> dict            # drop and effect_source
model.version -> str
```
artifact_dir: /Volumes/<CATALOG>/gummi_ml/artifacts/gummi_model_v1/ in the Unity Catalog volume. The model is also registered in MLflow. The package code ships in the App bundle (D-34).
Latency: estimate plus forecast under 50 ms per user, simulate under 100 ms. Pure Python plus numpy and pandas plus saved coefficients.

```python
from gummi_activity import intensity_from_cadence, summarize_walk
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
| proud | grade with Gummi beating CGM-only | gold sparkle, spin |
| happy | walk done or 3 hours in range | green, hops |
| sleepy | 23:00 to 06:00 with no new data | dim, half-closed eyes |
| thinking | UI only, during agent or chat tools | eyes up, hmm |

Priority: low, high, proud (20 seconds), dipping, rising, happy, sleepy, calm.

## 10. Tables (owner: Data, written by the pipeline)

`<CATALOG>.gummi_data`: volumes raw_bigideas, landing (and raw_imu50 only if D-19). Batch tables: bronze_cgm, bronze_food_log, bronze_demographics, bronze_hr (ablation only), silver_cgm_5min, silver_meals, replay_cgm, replay_meals. Stream tables: stream_bronze_events, stream_silver_cgm, stream_silver_meals, stream_silver_predictions, stream_silver_grades, stream_silver_cards, stream_gold_fleet, stream_gold_accuracy.
stream_gold_accuracy: Gummi, CGM-only, and last-value errors by participant and window type, labeled out-of-sample, excluding windows with walk_effect_graded false. Read by /fleet and get_gold_summary.
`<CATALOG>.gummi_ml`: volume artifacts (gummi_model_v1/ holds the full model, 5 fold models, and the participant-to-fold map). Tables eval_results, ablation_results, breakfast_response.
Exact columns get written here in Phase 1 with a version bump.
