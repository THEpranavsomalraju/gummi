# Gummi

A glucose coach that predicts, acts, and checks its own work. Built on Databricks for WolfHacks 2026 (Databricks track).

Gummi is an iPhone app for adults with prediabetes or type 2 diabetes who don't take insulin and wear a Dexcom. A glucose monitor shows what already happened, and Dexcom shares readings with apps about an hour late. Gummi estimates that missing hour with its own model, forecasts the next two hours, and coaches from it: "can I eat this?", "should I walk?", "why did I spike?". Two hours after every prediction, it grades itself against what actually happened, next to two simpler methods.

Gummi is a jelly koala who talks to you in chat. It is not for treatment decisions; check your Dexcom app for current readings.

## How it works

```
BIG IDEAs replay (15 participants)  ─┐
Dexcom sandbox (OAuth)               ├─> Databricks App (FastAPI)  ──> iPhone (live push)
iPhone steps and walks               ─┘      gummi_model, agents
                                              │
                                              ▼
                     Unity Catalog volume ─> Lakeflow pipeline ─> bronze / silver / gold Delta tables
                                                                    │
                     MLflow (model, traces, reviews) <──────────────┤
                     AI/BI dashboard, Genie, Agent Bricks <─────────┘
```

- **Replay:** no one on the team wears a Dexcom, so 15 real participants from the BIG IDEAs study stream through as a live replay, with the real one-hour delay. Following a participant means living their day: their real meals come due as cards you log.
- **Model (`data/gummi_model`):** our own forecaster on glucose history plus logged meals. Each participant is predicted by a model that never saw them.
- **Agents:** a chat Coach with 9 tools (simulate a food, log a meal, suggest a walk, explain a spike, ...), background agents that write meal stories, walk nudges, and morning and evening recaps, a Reviewer that scores every answer in MLflow, and Gummi Insights (Agent Bricks supervisor over a Genie space and Unity Catalog functions).
- **Streaming:** every event, prediction and grade lands in a Unity Catalog volume, and the `gummi_stream` Lakeflow pipeline turns it into Delta tables within seconds. The gold accuracy table feeds the dashboard, the fleet view and the evening recap.

## Accuracy

Average error in mg/dL, lower is better. Participant-grouped 5-fold cross-validation, so every number is on people the model never saw.

| Looking ahead | Gummi (history + meals) | CGM-only (published method) | Last reading |
|---|---|---|---|
| 30 minutes | **8.9** | 9.5 | 10.7 |
| 1 hour | **12.1** | 13.4 | 14.9 |
| 2 hours | **14.2** | 15.7 | 18.4 |
| 1 hour, right after a meal | **15.7** | 17.3 | 20.4 |

We first reproduced the published CGM-only baseline (13.90 RMSE at 30 minutes), then added meals.

## Repo

| Folder | What | Owner |
|---|---|---|
| `ios/` | SwiftUI app, RealityKit jelly koala, live channel, chat | Mahil |
| `backend/` | Databricks App: replay engine, grading, agents, food log, day summary, system map, fleet view | Pranav |
| `data/` | Data load, `gummi_model`, Lakeflow pipeline, gold tables, Genie, dashboard | Nikhil |
| `docs/` | `CONTRACT.md` (API v1.6), `DECISIONS.md`, project overview, data notes | everyone |

## Running it

- **Backend:** `cd backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`, then `scripts/deploy.sh` (Databricks CLI profile `gummi`). Tests: `scripts/fetch_cache.py` once, then `pytest tests/`.
- **Data:** `cd data && databricks bundle deploy`, then start `gummi_stream` (continuous for demos).
- **iOS:** `cd ios && xcodegen generate`, open `Gummi.xcodeproj`. Secrets go in `ios/Config/Secrets.xcconfig.local` (git-ignored). Without them the app runs on built-in demo data.
- **Demo:** `backend/scripts/demo_stage.py stage`, then `go` on stage.

## Data and credits

BIG IDEAs Lab Glycemic Variability and Wearable Device Data v1.1.3 (PhysioNet, Open Data Commons Attribution v1.0; Bent et al. 2021, npj Digital Medicine 4:89). Walk effect: Buffey et al. 2022, Sports Medicine 52:1765-1787. Dexcom API sandbox.

Team: Mahil Manoharan (iOS), Pranav Somalraju (Backend), Nikhil Ambavaram (Data).
