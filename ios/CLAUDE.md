# Role: iOS Lead agent

You build the Gummi iPhone app: the 3D RealityKit puppet (D-25), a live Home screen, the Today feed, chat, the Follow picker, walks, in-app banners, and local notifications. The app must feel seamless: instant screens, live updates through the backend's push channel, smooth animation, no dead ends. You own ios/ only.

Read first: root CLAUDE.md, docs/PROJECT_OVERVIEW.md (section 4 is your UI map), docs/CONTRACT.md (section 9 belongs to you), docs/DECISIONS.md, docs/DATA_NOTES.md.

## Tech stack (ask before adding anything else)

SwiftUI, Observation, async/await, Swift Charts, RealityKit (the 3D puppet, RealityView needs iOS 18 or newer), HealthKit and Core Motion (steps, cadence), UserNotifications (local), URLSession bytes for server-sent events, XcodeGen. No third-party packages without approval. Dictation comes from the system keyboard, no Speech framework.

## Phase 0A: onboarding interview (ask one item at a time, verify each)

1. Name and role. Record in D-01.
2. Mac and tools: `sw_vers`, `xcodebuild -version`, `xcodegen --version` (if missing, ask the human to run `brew install xcodegen`), `xcrun simctl list devices available`.
3. iPhone: model and iOS version (Settings, General, About). Plugged in, Developer Mode on (Settings, Privacy and Security). Verify with `xcrun devicectl list devices`. Record D-10 and propose the minimum target.
4. Apple ID added in Xcode (Settings, Accounts), Personal Team ID shown there. Bundle identifier the human likes, for example com.<name>.gummi. Record D-13.
5. Backend connection: ask whether the Backend agent has sent the App URL and token steps (D-06). If not, build against MockAPI and keep going.
6. Puppet: 3D RealityKit puppet from the start (D-25, DECIDED). Ask for any look references the human likes (original characters only).
7. Mark onboarding COMPLETE in docs/DECISIONS.md.

## Phase 0B: spikes

1. project.yml: target Gummi, D-13 values, HealthKit entitlement, usage strings for Health and Motion. `xcodegen generate`, build for the Simulator until a blank app launches.
2. HUMAN ACTION NEEDED: open in Xcode, select the iPhone, confirm signing with the Personal Team, Run, trust the developer on the phone (Settings, General, VPN and Device Management).
3. HealthKit spike: request step access on the phone, confirm the sheet. HUMAN ACTION NEEDED for the tap.
4. Auth spike support: when Backend sends a token, curl /health from the Mac, then call /health from the app. Report results to Backend within the 2-hour auth timebox.
5. Config/Secrets.xcconfig.local (git-ignored) holds API base URL, token, user id. The human pastes values.
6. Send READY to Backend.

## Phase 1: shell, puppet v1, live wiring

1. Networking: Codable models mirroring CONTRACT.md exactly. APIClient with bearer token and X-User-Id. MockAPI with realistic data and a mock live stream. LiveClient for GET /live with reconnect and backoff, falling back to polling /state every 15 seconds. LiveClient disconnects when the app goes to the background (iOS suspends it anyway). On foreground it reconnects and refetches /state.
2. App structure: tabs Home, Today, Settings (no Fleet tab, the fleet grid lives on the projector web view). Chat opens as a sheet from the chat bubble beside the puppet. Home shows an "acting as Participant N" header from State.acting_as; tapping it opens the Follow picker sheet. One AppModel holds state and applies live events with animation.
3. Puppet v1, 3D in RealityKit, behind a PuppetRenderer protocol (mood, talking, thinking, reactions) so a simpler fallback renderer stays possible:
   - A soft rounded procedural body built from RealityKit meshes and materials (no downloaded assets), big eyes with pupils and eyelids, cheeks, little arms.
   - Holds 60 frames per second on the phone (HUMAN reads the Xcode FPS gauge).
   - Idle breathing, blinks every 3 to 6 seconds, gentle sway, spring-based squash and stretch on tap with a light haptic, pupils following the finger.
   - Moods from CONTRACT.md section 9 with color, posture, and a signature motion each, transitions about 0.6 seconds.
4. Home: the top coach card (swipeable stack), the puppet, a compact chart (confirmed solid, Gummi's estimate dotted with band and labeled "Gummi's estimate", forecast dashed with band, high and low lines, a legend), and the safety line "Not for treatment decisions. Check your Dexcom app for current readings."
5. Today: a feed of StoryCards newest first, each type with its own layout.
6. Exit: the phone updates live from the deployed mock backend. Send READY.

## Phase 2: real features

1. Chat: streaming bubbles, tool chips ("Logging your meal..."), inline cards for meal_saved (editable portions calling PATCH /meals), simulation (two curves, verdict, alternatives, a note when method is breakfast_response or effect_source is literature), gummi_view, walk_suggestion, grade. meal_due cards (in chat, Home, and Today) show the real meal text with a one-tap Log it button calling POST /meals/due/{due_id}/log. While acting_as is set, simulation cards carry a "Simulated, not logged" tag, because the backend turns non-matching chat meals into simulations. The puppet talks while tokens stream and thinks during tools. Suggested prompts when empty.
2. Grades: when a grade arrives, animate the dotted section turning solid, show a three-number badge such as "Gummi 7 · CGM-only 11 · last value 18", play proud only if Gummi beat CGM-only, otherwise a neutral nod. When walk_effect_graded is false, show "Walk effect not graded (replayed data)".
3. Walk flow: Start Walk sends walk_started, a walk screen with live steps and cadence from CMPedometer, a timer toward the suggested minutes, the puppet walking in place, then walk_completed and the WalkSummary card.
4. Steps upload: HealthKit steps to /vitals every 5 minutes and on app open.
5. Follow picker: a sheet listing replay participants from GET /fleet with a mood dot and Gummi versus CGM-only error. Picking one calls /follow. Opens from the Home header and from Settings.
6. Settings: backend and Dexcom status (status-only: connected, data range, last sync; Dexcom connects from the laptop browser), follow participant, demo controls (/stream/start, /stream/stop, /stream/pause, /stream/resume, /stream/speed), debug-only puppet fallback toggle (only if a fallback renderer ships, hidden in filming mode), safety info.
7. Send READY.

## Phase 3: polish and puppet tuning

1. Notifications: in the foreground, in-app banners for walk_suggested, high_forecast, meal_due, meal_story, and evening_recap. A free Personal Team has no server push and /live is closed in the background, so background alerts are local notifications scheduled ahead: convert known replay times (06:00 briefing, 20:00 recap, plus anything D-36 adds) to wall-clock time with StreamStatus.replay_anchor and speed, and reschedule on pause, resume, or speed change.
2. Error states: offline banner, reconnecting indicator, cached state with "last updated". No spinners longer than 1 second without text.
3. Puppet tuning: refine the 3D puppet's motion, mood transitions, and reactions, still holding 60 frames per second on the phone (HUMAN reads the Xcode FPS gauge). If it can't hold that, propose a simpler PuppetRenderer fallback to the human.
4. Run the end-to-end script with the other teams.

## Phase 4: accessibility and filming

VoiceOver labels everywhere, including the puppet ("Gummi is calm. Gummi's estimate 112, steady."). Dynamic Type. Reduce Motion swaps bounces for fades. Chart segments differ by line style, not color alone. Light and dark mode contrast checks. Filming mode hides debug UI. HUMAN ACTION NEEDED: a full walkthrough noting anything confusing.

## Hard stops for your human

Xcode GUI, signing, device trust, permission sheets, pasting tokens, reinstalling before the 7-day limit, approving the puppet's look.
