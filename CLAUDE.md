# Gummi: shared rules for every agent

You are one of three Claude Code agents building Gummi for a hackathon. Your role file lives in your working folder (ios/, backend/, or data/).

Required reading, imported below:
@docs/PROJECT_OVERVIEW.md
@docs/CONTRACT.md
@docs/DECISIONS.md
@docs/DATA_NOTES.md

## What matters most

1. The iPhone experience feels seamless and alive: instant screens, live updates without pull-to-refresh, smooth animations, no dead ends, graceful errors.
2. The Databricks backend is technically sound, fast, and visibly Databricks: a real streaming pipeline, Unity Catalog tables, MLflow models and traces, an agent acting on events.
Every decision serves one of these two. When in doubt, choose the option a judge sees working.

## First thing in every session

If docs/DECISIONS.md shows your onboarding interview as incomplete, run the onboarding interview from your role file before any other work. Ask one item at a time, verify each answer with a command where possible, record answers in docs/DECISIONS.md, and store secrets only in git-ignored files.

## Decision rules

1. ASSUMED rule (default): for small or reversible choices (names inside your folder, library versions, layout details, thresholds already proposed in the docs), pick the sensible default, append a row to docs/DECISIONS.md marked ASSUMED with one line of reasoning, and keep working. Mention ASSUMED items in your next status report.
2. Hard stops: stop and use a HUMAN ACTION NEEDED block for secrets and credentials, logins and browser steps, money or quota-heavy jobs (anything expected over 15 minutes of compute or touching the full IMU50 archive), physical devices, permission grants, deleting tables or volumes, changing docs/CONTRACT.md, and anything visible to judges as a product claim (accuracy numbers, health claims, pitch copy).
3. Never invent facts: workspace URL, endpoint names, dataset file names or columns, bundle IDs, team IDs, redirect URIs, tokens. Look them up or ask.
4. Timebox: if a task runs more than 45 minutes past its estimate, stop and send a BLOCKER Lead Update with options.

## Working rules

1. Stay in your lane: edit only your role folder, updates/, and your rows in docs/DECISIONS.md.
2. Cross-team needs go through a Lead Update (format in docs/PROJECT_OVERVIEW.md). Never wait silently. If blocked, switch to the next unblocked task and say so.
3. Secrets stay out of git: .env, *.env, *.xcconfig.local, secrets/. Run git status before every commit.
4. Phases in order. Send READY at each phase end.
5. Verify every change by building, running, or testing. Report how you verified.
6. Plan mode for anything touching more than three files.

## Honesty rules (judges will probe these)

1. Gummi coaches. Gummi never shows an estimated value as the user's current glucose without the label "Gummi's estimate", never tells anyone to change medication or insulin, and every screen with glucose carries "Not for treatment decisions. Check your Dexcom app for current readings."
2. Target user: prediabetes or type 2 without insulin. Never market Gummi to insulin users.
3. Science: participant-grouped validation only. Every accuracy number sits next to its baselines (CGM-only linear regression and last-value guess). Walk effects carry their source label ("literature" or "your data").

## Git

Branches ios/work, backend/work, data/work. Pull main at each phase start, merge at each phase end after human approval. Never force push.

## Status

When the human types "status": current phase, done, in progress, blocked on (who), next three tasks, ASSUMED items since last status, open questions.
