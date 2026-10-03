# START HERE (for the three humans)

Everything your three Claude Code agents need lives in this folder. Read this file top to bottom before opening Claude Code. Steps marked HUMAN need a person at the keyboard.

Working codename: Gummi (project and puppet). Rename before Phase 1 if you want, and log the change as D-14.

## Gummi in one breath

Gummi is a CGM coach for people with prediabetes or type 2 diabetes who do not take insulin. Gummi lives on the iPhone as a cute interactive puppet. Gummi reads Dexcom data, predicts where glucose heads after meals, nudges walks before spikes, answers "can I eat this right now?", and grades every prediction against what actually happened. An AI agent acts on its own when events happen (a meal window closes, delayed readings arrive, the evening comes) and posts story cards to the user's day. The backend, the streaming pipeline, the models, and the agent run on Databricks.

Why a nowcast engine: Dexcom's API delivers data to third-party apps one hour late in the US, on purpose, so apps never drive real-time treatment. Gummi never replaces the Dexcom readout. Gummi's internal estimate of the missing hour lets the coach reason about the present with delayed data.

Nobody on the team needs a Dexcom. Live demo data comes from replaying 16 real participants from the BIG IDEAs study through Databricks as a stream. The Dexcom sandbox proves the real connection works.

## Do these FIRST (HUMAN, before anything else)

1. Workspace owner: sign up for Databricks Free Edition, then complete "Verify with LinkedIn" in the account. Free Edition limits outbound internet to a short list of trusted domains, and verification unlocks outbound internet access. Without the step, calls to Dexcom and PhysioNet may fail silently.
2. Answer the six team questions in docs/DECISIONS.md section "Team answers needed" (T-1 to T-6). Agents start Phase 0 anyway and log sensible defaults as ASSUMED, but these answers change real work.

## The three roles

| Role | Folder | Owns |
|---|---|---|
| iOS Lead | ios/ | Swift app, puppet (2D first, 3D upgrade), live home, Today feed, chat, fleet screen, walks, notifications |
| Backend Lead | backend/ | Databricks App (FastAPI), live push channel, replay producer, Dexcom OAuth and sync, event-driven agent, chat agent, fleet web view |
| Data Lead | data/ | BIG IDEAs ingestion, baseline reproduction, the glucose model, the streaming pipeline, replay tables, evaluation, IMU50 if required |

## Repo layout

```
gummi/
  README_START_HERE.md      this file
  CLAUDE.md                 shared agent rules, imports the docs
  docs/PROJECT_OVERVIEW.md  product, UI map, architecture, phases, protocols, judge Q&A
  docs/CONTRACT.md          API, events, tables, tools, model interface, puppet moods
  docs/DECISIONS.md         decisions and team answers
  docs/DATA_NOTES.md        dataset facts and prior research
  updates/outbox, inbox     lead-to-lead messages
  ios/CLAUDE.md  backend/CLAUDE.md  data/CLAUDE.md
```

Launching Claude Code inside a role folder loads that folder's CLAUDE.md plus the root CLAUDE.md, which imports the docs.

## Step 1. Every teammate: install basics (HUMAN, 15 minutes)

1. `xcode-select --install` (skip if already installed).
2. Homebrew: `brew --version`, else install from https://brew.sh.
3. Claude Code: `curl -fsSL https://claude.ai/install.sh | bash`, new Terminal, `claude --version`, then `claude` and log in.
4. Backend and Data Leads: Python 3.11 or newer (`python3 --version`, else `brew install python@3.11`).
5. Optional, for the skills fallback: `brew install node`.

## Step 2. Shared repo (HUMAN, 5 minutes, one teammate)

Create a private GitHub repo, copy this folder in (keep .gitignore), push, add teammates, everyone clones.

## Step 3. Databricks access (HUMAN, 10 minutes)

1. Workspace owner invites the other two teammates (workspace Settings, user management). Record the URL and owner in D-02.
2. Backend and Data Leads (iOS Lead too, for curl tests): `brew tap databricks/tap && brew install databricks`
3. `databricks auth login --host <WORKSPACE_URL> --profile gummi`, approve in the browser.
4. Test: `databricks current-user me --profile gummi`

## Step 4. Databricks skills for Claude Code (HUMAN, 5 minutes, Backend and Data Leads)

In Claude Code type `/plugin`, find the plugin named databricks made by Databricks, install, restart, and ask "Which Databricks skills do you have loaded?" Fallback from the repo root: `npx -y skills add databricks/databricks-agent-skills --agent claude-code`.

## Step 5. Dexcom developer app (HUMAN, 10 minutes, Backend Lead)

Register at https://developer.dexcom.com and create an app. Wait for the Backend agent to tell you the redirect URI before saving the app settings. Put the client ID and secret only in the git-ignored file the agent creates.

## Step 6. iOS Lead: Xcode and iPhone (HUMAN, 20 minutes)

1. Install Xcode from the Mac App Store, open once.
2. Xcode, Settings, Accounts: add your Apple ID (free Personal Team, HealthKit works on your own device).
3. Connect the iPhone, then Settings, Privacy and Security, Developer Mode: on, restart.
4. Record iOS and Xcode versions in D-10.
5. `brew install xcodegen`
6. Free Personal Team limits: apps expire after 7 days, no server push (Gummi uses its own live channel and local notifications).

## Step 7. Start the agents

```
cd gummi/ios       (or gummi/backend, or gummi/data)
claude
```
Paste, replacing ROLE:
```
Read the root CLAUDE.md, docs/PROJECT_OVERVIEW.md, docs/CONTRACT.md, docs/DECISIONS.md, docs/DATA_NOTES.md, and ROLE/CLAUDE.md. Summarize your role in 5 lines, list the decisions you need from me, then start Phase 0. Use the ASSUMED rule for small choices and stop only at hard stops.
```
Use plan mode (Shift+Tab) for big tasks.

## Step 7b. What each agent asks you first

Every agent opens Phase 0 with an onboarding interview: a checklist of everything it needs from you, each item verified with a command before moving on. Keep these handy:
- Everyone: your name and role, the repo URL, whether `claude --version` and git work.
- Backend Lead: workspace URL, CLI profile working, LinkedIn verification status, output of `databricks serving-endpoints list --profile gummi`, Dexcom developer account, where App secrets go.
- Data Lead: free disk space (`df -h ~`), whether downloads go straight into Databricks or through your laptop, the catalog name, whether organizers require both datasets.
- iOS Lead: Mac model, Xcode and iOS versions, iPhone plugged in with Developer Mode on, Apple ID added in Xcode, Personal Team ID, a bundle identifier you like.

## Big downloads belong to the Data Lead

The Data Lead's agent handles every dataset download. The Backend and iOS Leads never download datasets. The full BIG IDEAs mirror (`wget -r -N -c -np https://physionet.org/files/big-ideas-glycemic-wearable/1.1.3/`) pulls about 34 GB, so the Data agent first tries downloading only the needed files directly inside Databricks, and otherwise runs a filtered download after checking free disk space.

## Step 8. Moving messages between teams

Agents write Lead Updates into updates/outbox/ and print them. You forward the text to the right teammate. The receiver pastes it into their session starting with "Incoming Lead Update:". Push updates/ often.

## Golden rules

- Answer agent questions fast. Review the ASSUMED entries in docs/DECISIONS.md every couple of hours and overrule anything wrong.
- Secrets only in git-ignored files.
- Disputes: Backend decides API shapes, Data decides model behavior, iOS decides UI.
