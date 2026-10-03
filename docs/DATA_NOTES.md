# Data Notes

Facts from dataset pages, papers, and vendor docs. VERIFY means check against the real files or services before use.

## 1. BIG IDEAs Lab Glycemic Variability and Wearable Device Data, v1.1.3

- Page: https://physionet.org/content/big-ideas-glycemic-wearable/1.1.3/
- Files: https://physionet.org/files/big-ideas-glycemic-wearable/1.1.3/
- Full mirror command (about 34 GB, do NOT run on a laptop without checking space): `wget -r -N -c -np https://physionet.org/files/big-ideas-glycemic-wearable/1.1.3/`
- Zip: 4.7 GB. BVP and ACC files take most of the space.
- License: Open Data Commons Attribution v1.0. Cite the dataset, Bent et al. 2021 (npj Digital Medicine 4:89), and PhysioNet.

Cohort: 16 post-menopausal women aged 35 to 65, HbA1c 5.2 to 6.4 percent, about 8 to 10 days each.

Devices: Dexcom G6 every 5 minutes. Empatica E4 with BVP 64 Hz, HR 1 Hz, IBI, EDA and TEMP 4 Hz, ACC 32 Hz.

Layout: folders 001 to 016 with one CSV per signal (the page lists ACC.csv, BVP.csv, Dexcom.csv, EDA.csv, HR.csv, IBI.csv, TEMP.csv, Food_Log_<ID>.csv), plus Demographics.csv in the root. VERIFY exact names, since older versions may append IDs. Food_Log_001.csv is confirmed.

Food log columns: date, time_of_day (VERIFY, an older version shows "time"), time_begin, time_end, logged_food, amount, unit, searched_food, calorie, total_carb, dietary_fiber, sugar, protein, total_fat. The standardized breakfast appears as logged_food "Standard Breakfast" (participant 001: 0.75 cup Kellogg's Frosted Flakes, 26 g carbs, plus milk on a separate row). VERIFY across participants.

Dates are shifted for privacy. v1.1.3 fixed misaligned food log dates.

Files Bean needs: Dexcom, Food_Log, Demographics, SHA256SUMS.txt, LICENSE.txt. HR only for the ablation. ACC, BVP, EDA, TEMP, IBI not needed.

## 2. Prior research Bean must respect

Seyedebrahimi, Ojeda, Zarrintaj (2026), "A Leakage-Controlled Evaluation of Multimodal Sensor Fusion for Wrist-Worn Glucose Estimation", medRxiv, doi 10.64898/2026.08.03.26359550. Code: https://github.com/mirmehdi/PhysioFusion

- 15 participants after excluding one with 75 percent completeness and a 22-hour gap. VERIFY which (D-20).
- CGM is the master clock. Contiguous segments split at gaps over 15 minutes. 24 readings of history.
- Five-fold subject-grouped CV. 30-minute-ahead RMSE: linear regression 13.90 plus or minus 0.58, persistence 16.49. Heavier models did not beat linear.
- Wrist signals added nothing. Wrist-only 22.58 equals time-of-day 22.63 and the mean 22.76.
- E4 IBI unfit for HRV at 5-minute resolution.
- Food logs were not used. Meals drive the biggest deviations.

Implications: glucose from CGM history plus meals. Bean's research question: do logged meals improve on CGM history? Baselines always shown: mean, last value (persistence), CGM-only linear regression. Never quote the original paper's 84 or 87 percent figures, which came from within-subject or record-wise splits.

Expectation management: in this flat cohort, long horizons drift toward the mean. Quiet periods flatter any method. Grade meal windows separately from quiet windows.

## 3. Dexcom API

- OAuth 2.0 authorization code flow. v3 endpoints: /v3/users/self/egvs, /events, /calibrations, /alerts, /devices, /dataRange. Supports G6, G7, G7 15-day, Dexcom ONE, ONE+.
- Sandbox host sandbox-api.dexcom.com with simulated users such as SandboxUser7 for G7. Expect fixed date ranges and repeating sensor sessions, not live data. VERIFY with /dataRange.
- One-hour delay in the US, three hours elsewhere, enforced on upload time. Third-party apps are not for real-time treatment decisions.
- EGV range 40 to 400 mg/dL. Each EGV has systemTime (UTC) and displayTime (local).

## 4. IMU50 (only if T-2 requires both datasets)

- https://zenodo.org/records/21468410, CC BY 4.0. One file, IMU50.zip, 46.7 GB. Internal structure undocumented on the record page. VERIFY by listing the zip with HTTP range reads.
- 50 healthy volunteers, Actigraph Leap wrist, about 136 hours each. Accelerometer and gyroscope 128 Hz, PPG 25 Hz, skin temperature per minute, hourly METs and calories from Actigraph's Freedson algorithms, metadata (age, sex, weight, height, BMI, hip and waist, education, lifestyle). No glucose. No activity labels.
- Honest job if used: check that Bean's cadence-to-intensity bands agree with wrist motion during walking-like minutes in a small sample. Say exactly that in the pitch.

## 5. Databricks Free Edition

- Serverless compute only. No GPU serving.
- Outbound internet limited to trusted domains until the workspace owner completes LinkedIn verification.
- Streaming: notebooks and jobs support only AvailableNow and Once triggers. Continuous streaming uses a Lakeflow declarative pipeline in continuous mode.
- Apps: limited count, possible runtime window, redeploy before demos.
- No SLA, fair usage quotas, compute may stop for the day if quotas run out.

## 6. Walk effect

The prior work found accelerometry adds nothing to 30-minute forecasts. Bean uses a literature-based post-meal walking effect, cited, labeled "literature" in the UI, until a person's own data passes a permutation test (meals with a walk after versus without). With about 10 days per person, expect "not enough data yet" for most people and show that message honestly.
