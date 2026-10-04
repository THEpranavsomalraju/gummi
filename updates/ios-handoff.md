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

## Current chunk: C2 "moments judges remember" (questions asked, waiting for answers)
Scope: grade moment animation and badge, walk flow (CMPedometer, walk screen, walk_started and walk_completed, GET /walks/latest, WalkSummary card, happy mood), HealthKit steps to /vitals every 5 minutes and on open, local notifications scheduled from replay_anchor and speed. Verify on the iPhone with a real walk and a notification arriving in the background.
- The questions and recommendations are in the conversation's last reply. If they're lost, re-ask them: which notifications matter, where the grade animation lives, walk entry points and end rules, the notification permission moment, and steps-upload windows.
- Notification design explained to Mahil:
  - Nothing runs in the background, so the phone schedules notifications ahead when it goes to the background, using State.upcoming_due (already wall-clock), pending predictions (grade lands about window_end plus the 60-minute delay on the replay clock), and fixed replay times (06:00 briefing, 20:00 recap).
  - Replay times convert to wall time with `wall = anchor.wall_time + (replay - anchor.replay_time) / speed`.
  - Clear everything on foreground (banners take over), reschedule on any State whose stream.paused, speed, or replay_anchor changed, and schedule nothing while paused or stopped.
  - Walk suggestions can only be predicted from the current forecast crossing 140, so they're best effort.
- Code to reuse: AppModel (state, cards, cue for proud and nod), PuppetAnimator (ClipKind; add a walk-in-place clip), GradeBadge and MiniCurve in Cards/StoryCardView.swift, APIClient.sendWalkEvent, latestWalk, uploadSteps (already written), WalkEventBody, StepSample. GummiService still needs sendWalkEvent, latestWalk, and uploadSteps, plus mock versions that emit a walk_summary card.
