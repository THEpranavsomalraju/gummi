# iOS handoff (for the next session or another agent)

Updated 2026-10-04. Read root CLAUDE.md, ios/CLAUDE.md, docs/CONTRACT.md (1.5), and docs/DECISIONS.md (iOS rows D-60s, D-90s, D-120s, D-150 to D-160) first.

## Rules Mahil set
- Follow the chunk protocol for every pasted chunk: restate the goal, ask numbered questions with recommendations, stop; show a plan (plan mode if more than 3 files) and wait for "go"; verify each step; end with "CHUNK DONE".
- Commits: succinct messages, never a Co-Authored-By or any Claude attribution. Push only after asking.
- The gummi-iphone client secret lives only in git-ignored ios/Config/Secrets.xcconfig.local. Never print or commit it. Before each commit: `SEC=$(sed -n 's/^GUMMI_CLIENT_SECRET = //p' ios/Config/Secrets.xcconfig.local); git diff --cached | grep -qF "$SEC" && echo STOP`.
- Never start or stop the shared backend stream without asking Pranav or Mahil.
- Edit only ios/, updates/, and iOS rows in docs/DECISIONS.md (iOS ID blocks: D-150 to D-159 is full, D-160 used; next free iOS block is D-161 onward unless the leads say otherwise).

## Build and run
- `cd ios && xcodegen generate` after adding files (the .xcodeproj is git-ignored).
- Tests: `xcodebuild -project Gummi.xcodeproj -scheme Gummi -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (92 pass as of a724f62).
- Phone: Mahil's iPhone 17 Pro, devicectl id 61637233-C9FF-5F56-B26C-E92C79E36DC5, xcodebuild destination id 00008150-00186960216A401C. Build with `-destination 'generic/platform=iOS' -derivedDataPath build/device -allowProvisioningUpdates`, then `xcrun devicectl device install app --device <devicectl id> build/device/Build/Products/Debug-iphoneos/Gummi.app` and `xcrun devicectl device process launch --terminate-existing --device <id> com.mahilmanoharan.gummi`. Free Personal Team: installs expire after 7 days.
- Debug launch args: `-gummi.mode mock|live`, `-gummi.tab today`, `-gummi.sheet follow|chat`, `-gummi.chat "q1|q2"`, `-gummi.chatDetent large`, `-gummi.screen playground`.

## State of the app
- Done: networking (APIClient, LiveClient SSE, TokenProvider), MockAPI (scripted p_012 day 6 plus scripted chat), the 3D jelly koala (approved, D-151), Home, Today, Follow picker, banners, chat (D-155 to D-160).
- Last fix (this commit): the Home chat bubble is always tappable and only dims while Gummi moves; before, idle animations kept it hidden, so taps fell through to Gummi.
- Not yet on the phone: the bubble fix (the phone was unavailable). Install and have Mahil confirm.
- Open with Backend: the Lead Update updates/outbox/20261004-0230-ios-to-backend-REQUEST.md (chat contract gaps, and live p_012 estimate stale by 65 hours with a band of -631 to 878).
- Unpushed commits on ios/work: b2fe9e8, 6405faa, a724f62, plus this one. Ask Mahil before pushing.

## Chunk C2 (built, waiting on the iPhone check)
- Built: the grade moment (Home/GradeMoment.swift), the walk flow (Walk/), steps upload (Health/StepsUploader.swift), and notifications (Notifications/NotificationPlanner.swift). Decisions D-161 to D-164. 104 tests pass.
- Mahil still needs to verify on the iPhone:
  1. A real walk from Today: Start a walk, walk 2+ minutes, End walk. The summary, the Nice walk card, and a happy Gummi should appear.
  2. Mock mode with p_012 followed: press home, and a meal due notification should arrive within about a minute (mock runs at 360x).
  3. The Health, Motion, and notification permission prompts.
- More debug args: `-gummi.sheet walk`, `-gummi.fakeSteps YES`, `-gummi.noPrompts YES`.
- Known limit: notifications use the State from when the app was backgrounded, so replay changes made from another device while the app is suspended aren't reflected.
- Next chunks: Pranav's new tabs (Home, Food, Activity, Day from GET /day) together with the food log (D-152); plan with Mahil.

## Chunk C3 (built; the end-to-end run waits for the App)
- Built: Settings with Dexcom status and demo controls (Settings/), the connection capsule, app_unavailable mapping, CONTRACT 1.6 adoption (stale data, tool labels, SavedMeal, empty turns, reliable false), demo day 4 in the mock and the default start. Decisions D-165 to D-167, D-62 updated. 111 tests pass.
- The App is down (Free Edition daily limit, Pranav's BLOCKER). The run log is in updates/e2e-20261004.md. When Pranav says "App back up", run it with the humans. If the workspace moves, the App URL and the gummi-iphone client id and secret change; Mahil pastes the new ones into ios/Config/Secrets.xcconfig.local.
- More debug args: `-gummi.tab settings`, `-gummi.forceConnection reconnecting|offline|asleep`.
