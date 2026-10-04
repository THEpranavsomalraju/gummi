# Gummi

Our WolfHacks 2026 project for the Databricks track.

Gummi is an iPhone app for people with prediabetes or type 2 diabetes (not on insulin) who wear a Dexcom. Your glucose monitor only tells you what already happened, and apps get Dexcom data an hour late. Gummi fills in that hour with its own model, predicts the next two hours, and helps with stuff like "can I eat this cookie?" or "should I go for a walk?". Two hours later it checks how close it was.

Gummi is a little jelly koala you chat with. It's not meant for treatment decisions, so always check your Dexcom app for real readings.

## How it works

None of us wear a Dexcom, so we replay 15 real people from the BIG IDEAs study as if it's happening live, with the same one-hour delay. You pick someone to follow and live through their day. Their real meals pop up as cards you can log.

Everything runs on Databricks:

- A Databricks App (FastAPI) runs the replay, our model, and the agents, and pushes updates to the phone.
- Every reading, meal, prediction and grade gets written to a Unity Catalog volume. Our Lakeflow pipeline (`gummi_stream`) turns that into Delta tables within a few seconds.
- The model is ours (`data/gummi_model`). It uses glucose history plus meals, and it's registered in Unity Catalog.
- The chat agent can simulate a food, log a meal, suggest a walk or explain a spike. Background agents write meal stories and daily recaps. A second model reviews every answer, and all of it is traced in MLflow.
- There's also a dashboard, a Genie space, and an Agent Bricks supervisor (Gummi Insights) for digging into someone's history.

## How accurate is it?

Average error in mg/dL (lower is better). We always test on people the model never saw during training.

| Looking ahead | Gummi | CGM-only (published method) | Last reading |
|---|---|---|---|
| 30 min | 8.9 | 9.5 | 10.7 |
| 1 hour | 12.1 | 13.4 | 14.9 |
| 2 hours | 14.2 | 15.7 | 18.4 |
| 1 hour after a meal | 15.7 | 17.3 | 20.4 |

We reproduced the published CGM-only baseline first (13.90 RMSE at 30 min), then added meals on top.

## Repo

- `ios/` is the app (SwiftUI, RealityKit koala). Mahil
- `backend/` is the Databricks App. Pranav
- `data/` has the data load, model, pipeline and gold tables. Nikhil
- `docs/` has the API contract and our decision log

## Running it

Backend: make a venv in `backend/`, install `requirements.txt`, then run `scripts/deploy.sh` (uses a Databricks CLI profile called `gummi`).

Data: `databricks bundle deploy` in `data/`, then start the `gummi_stream` pipeline.

iOS: `xcodegen generate` in `ios/` and open the project. Without secrets in `Config/Secrets.xcconfig.local` it just runs on demo data.

## Credits

Data from the BIG IDEAs Lab Glycemic Variability and Wearable Device Data v1.1.3 on PhysioNet (Bent et al. 2021, npj Digital Medicine). Walking effect from Buffey et al. 2022, Sports Medicine. Dexcom sandbox API.

Made by Mahil Manoharan, Pranav Somalraju and Nikhil Ambavaram.
