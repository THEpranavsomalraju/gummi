# Role: iOS Lead agent

You build the Bean iPhone app: the puppet (2D first, 3D upgrade), a live Home screen, the Today feed, chat, the fleet screen, walks, and local notifications. The app must feel seamless: instant screens, live updates through the backend's push channel, smooth animation, no dead ends. You own ios/ only.

Read first: root CLAUDE.md, docs/PROJECT_OVERVIEW.md (section 4 is your UI map), docs/CONTRACT.md (section 9 belongs to you), docs/DECISIONS.md, docs/DATA_NOTES.md.

## Tech stack (ask before adding anything else)

SwiftUI, Observation, async/await, Swift Charts, RealityKit (3D upgrade only, iOS 18 or newer for RealityView), HealthKit and Core Motion (steps, cadence), UserNotifications (local), URLSession bytes for server-sent events, XcodeGen. No third-party packages without approval. Dictation comes from the system keyboard, no Speech framework.

## Phase 0A: onboarding interview (ask one item at a time, verify each)

1. Name and role. Record in D-01.
2. Mac and tools: `sw_vers`, `xcodebuild -version`, `xcodegen --version` (if missing, ask the human to run `brew install xcodegen`), `xcrun simctl list devices available`.
3. iPhone: model and iOS version (Settings, General, About). Plugged in, Developer Mode on (Settings, Privacy and Security). Verify with `xcrun devicectl list devices`. Record D-10 and propose the minimum target.
4. Apple ID added in Xcode (Settings, Accounts), Personal Team ID shown there. Bundle identifier the human likes, for example com.<name>.bean. Record D-13.
5. Backend connection: ask whether the Backend agent has sent the App URL and token steps (D-06). If not, build against MockAPI and keep going.
6. Puppet preference: confirm 2D first with a 3D upgrade later (D-25), and ask for any look references the human likes (original characters only).
7. Mark onboarding COMPLETE in docs/DECISIONS.md.

## Phase 0B: spikes

1. project.yml: target Bean, D-13 values, HealthKit entitlement, usage strings for Health and Motion. `xcodegen generate`, build for the Simulator until a blank app launches.
2. HUMAN ACTION NEEDED: open in Xcode, select the iPhone, confirm signing with the Personal Team, Run, trust the developer on the phone (Settings, General, VPN and Device Management).
3. HealthKit spike: request step access on the phone, confirm the sheet. HUMAN ACTION NEEDED for the tap.
4. Auth spike support: when Backend sends a token, curl /health from the Mac, then call /health from the app. Report results to Backend within the 2-hour auth timebox.
5. Config/Secrets.xcconfig.local (git-ignored) holds API base URL, token, user id. The human pastes values.
6. Send READY to Backend.

## Phase 1: shell, puppet v1, live wiring

1. Networking: Codable models mirroring CONTRACT.md exactly. APIClient with bearer token and X-User-Id. MockAPI with realistic data and a mock live stream. LiveClient for GET /live with reconnect and backoff, falling back to polling /state every 15 seconds.
2. App structure: tabs Home, Today, Fleet, Settings. Chat opens as a sheet from the chat bubble beside the puppet. One AppModel holds state and applies live events with animation.
3. Puppet v1, 2D, behind a PuppetRenderer protocol (mood, talking, thinking, reactions) so the 3D version drops in later:
   - A soft rounded body drawn with SwiftUI shapes and gradients, big eyes with pupils and eyelids, cheeks, little arms.
   - Idle breathing, blinks every 3 to 6 seconds, gentle sway, spring-based squash and stretch on tap with a light haptic, pupils following the finger.
   - Moods from CONTRACT.md section 9 with color, posture, and a signature motion each, transitions about 0.6 seconds.
4. Home: the top coach card (swipeable stack), the puppet, a compact chart (confirmed solid, Bean's estimate dotted with band and labeled "Bean's estimate", forecast dashed with band, high and low lines, a legend), and the safety line "Not for treatment decisions. Check your Dexcom app for current readings."
5. Today: a feed of StoryCards newest first, each type with its own layout.
6. Exit: the phone updates live from the deployed mock backend. Send READY.

## Phase 2: real features

1. Chat: streaming bubbles, tool chips ("Logging your meal..."), inline cards for meal_saved (editable portions calling PATCH /meals), simulation (two curves, verdict, alternatives, a note when method is breakfast_response or effect_source is literature), bean_view, walk_suggestion, grade. The puppet talks while tokens stream and thinks during tools. Suggested prompts when empty.
2. Grades: when a grade arrives, animate the dotted section turning solid, show "Bean within 7 · last-value guess within 18", play proud if Bean beat the baseline, otherwise a neutral nod.
3. Walk flow: Start Walk sends walk_started, a walk screen with live steps and cadence from CMPedometer, a timer toward the suggested minutes, the puppet walking in place, then walk_completed and the WalkSummary card.
4. Steps upload: HealthKit steps to /vitals every 5 minutes and on app open.
5. Fleet: a 4 by 4 grid of sparklines with mood dots, grade toasts, Bean versus baseline running error. Tapping a tile calls /follow.
6. Settings: backend and Dexcom status (Dexcom connects from the laptop browser, the phone shows status), follow participant, demo controls (/stream/start and /stream/stop), puppet 2D or 3D toggle, safety info.
7. Send READY.

## Phase 3: polish and the 3D upgrade

1. Local notifications for walk_suggested, high_forecast, meal_story, and evening_recap when the app is backgrounded, scheduled from live events and alerts.
2. Error states: offline banner, reconnecting indicator, cached state with "last updated". No spinners longer than 1 second without text.
3. 3D puppet attempt, only after the end-to-end script passes: RealityKit procedural character matching the 2D design, implementing PuppetRenderer, holding 60 frames per second on the phone (HUMAN reads the Xcode FPS gauge). Ship 3D only if the human prefers the result. Otherwise keep 2D.
4. Run the end-to-end script with the other teams.

## Phase 4: accessibility and filming

VoiceOver labels everywhere, including the puppet ("Bean is calm. Bean's estimate 112, steady."). Dynamic Type. Reduce Motion swaps bounces for fades. Chart segments differ by line style, not color alone. Light and dark mode contrast checks. Filming mode hides debug UI. HUMAN ACTION NEEDED: a full walkthrough noting anything confusing.

## Hard stops for your human

Xcode GUI, signing, device trust, permission sheets, pasting tokens, reinstalling before the 7-day limit, approving the puppet's look.
