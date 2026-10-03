# Decisions Log

Agents append rows. Status values: DECIDED (a human chose), ASSUMED (an agent chose a reversible default, humans review), PENDING (needs a human).

## Team answers needed (humans fill these in)

| ID | Question | Answer |
|---|---|---|
| T-1 | Progress: workspace created? LinkedIn verification done? Dexcom developer app created? Xcode project on the phone? BIG IDEAs downloaded? | PENDING |
| T-2 | Did organizers require using both datasets (BIG IDEAs and IMU50)? Decides whether IMU50 stays. | PENDING |
| T-3 | Output of `databricks serving-endpoints list --profile bean` | PENDING (Backend agent collects) |
| T-4 | Real header row and first 3 lines of one Dexcom file and one food log | PENDING (Data agent collects) |
| T-5 | Who holds which role, plus comfort with Swift, Spark, FastAPI | Backend Lead: the teammate who shared these files. Others PENDING |
| T-6 | Agree with the reframe: non-insulin users, coaching first, nowcast as the engine? | PENDING (files assume yes) |

## Onboarding status

| Role | Onboarding interview | Done at |
|---|---|---|
| iOS Lead | INCOMPLETE | |
| Backend Lead | INCOMPLETE | |
| Data Lead | INCOMPLETE | |

## Decisions

| ID | Decision | Status | Answer | By | When |
|---|---|---|---|---|---|
| D-01 | Names per role | PENDING | | | |
| D-02 | Workspace URL and owner | PENDING | | | |
| D-03 | Live store | DECIDED | In-memory hot state in the App plus Delta tables through the landing volume and pipeline. No Lakebase. | team review | |
| D-04 | LLM serving endpoint (tool calling required) | PENDING | | | |
| D-05 | Model hosting | DECIDED | bean_model runs inside the App process on CPU | team review | |
| D-06 | iPhone token type and delivery | PENDING (auth spike) | | | |
| D-07 | Unity Catalog catalog | PENDING | | | |
| D-08 | Nutrition source | DECIDED | LLM estimate plus 30 seed foods, editable portions. No USDA. | team review | |
| D-09 | Modeling libraries on serverless | PENDING | | | |
| D-10 | iPhone iOS version, Xcode version, minimum target | PENDING | | | |
| D-11 | Walk effect source | PENDING | Default "literature" with citation until a personal permutation test passes | | |
| D-12 | High and low lines | ASSUMED | 140 and 70 mg/dL | docs | |
| D-13 | Bundle ID and Personal Team ID | PENDING | | | |
| D-14 | Final name | PENDING | codename Bean | | |
| D-15 | Followed participant and replay day for the demo | PENDING (Data proposes 3) | | | |
| D-16 | Repo URL | PENDING | | | |
| D-17 | Dexcom OAuth path | ASSUMED | Connect from the App's web page in a laptop browser, callback at <APP_URL>/api/v1/dexcom/callback. Verify in the auth spike. | docs | |
| D-18 | Dexcom sandbox user, data range, live or repeating | PENDING (expect repeating, fixed range) | | | |
| D-19 | IMU50 scope | PENDING (depends on T-2). If required: small validation of cadence bands only. | | | |
| D-20 | BIG IDEAs participant exclusions | PENDING | | | |
| D-21 | Pipeline mode: continuous, or triggered every minute | PENDING (streaming spike) | | | |
| D-22 | Replay speed, delay, start day, LLM budget for event-driven cards | ASSUMED | 60x, 60 minutes, D-15 day, LLM only for followed users | docs | |
| D-23 | Genie available in Free Edition for ask_data | PENDING (stretch) | | | |
| D-24 | Forecast horizon | DECIDED | 2 hours | team review | |
| D-25 | Puppet | DECIDED | 2D SwiftUI puppet first, 3D RealityKit upgrade behind the same interface | team review | |

## Status board

| Role | Phase | Last update | Blocked on |
|---|---|---|---|
| iOS Lead | 0 | | |
| Backend Lead | 0 | | |
| Data Lead | 0 | | |
