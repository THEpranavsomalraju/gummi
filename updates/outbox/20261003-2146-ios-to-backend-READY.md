=== LEAD UPDATE ===
From: iOS agent
To: Backend agent (via human)
Type: READY
Phase: 0
Summary: iOS Phase 0B is done. The Gummi app runs on Mahil's iPhone 17 Pro, fetches its own gummi-iphone token, and gets HTTP 200 from /health through the Apps proxy. CONTRACT 1.3 is received and pulled into ios/work.
Details:
1. App: XcodeGen project, bundle com.mahilmanoharan.gummi, free Personal Team, iOS 18.0 minimum. It runs on the iOS 26.4 and 18.6 Simulators and on the iPhone 17 Pro (iOS 26.6.2).
2. Auth (D-06): TokenProvider (ios/Gummi/Networking/TokenProvider.swift) POSTs client_credentials with scope all-apis to the workspace /oidc/v1/token. It caches the token until 5 minutes before expires_in and has invalidate() for the retry-once-on-401 path. The client id and secret live only in the git-ignored ios/Config/Secrets.xcconfig.local.
3. App-side proof: on the iPhone, "Ping backend" returned HTTP 200 from GET /api/v1/health with X-User-Id u_mahil (confirmed by Mahil). From the Mac with the same credentials: token 200 in 0.33 s (expires_in 3600); /health, /state, /stream/status and /fleet all 200 at 136 to 200 ms; 401 without a token; /live?ping_seconds=2 sent state at 0.21 s and ping at 2.73 s.
4. HealthKit step read works on the phone. Steps go to /vitals in Phase 2.
5. CONTRACT 1.3 (D-51) is accepted on the iOS side. ios/work fast-forwarded to backend/work 87da092, so iOS builds against 1.3 and the new decision ID ranges (iOS D-60 to D-69).
6. Note: /health reports X-Gummi-Mode "live" (version 0.2.0), not "mock". iOS shows whatever the header says in a debug badge, so no action is needed unless that's unexpected.
Action needed from you: none
Blocks me until: not blocking. Next, iOS starts Phase 1 (Codable models for 1.3, APIClient, SSE LiveClient, app shell, puppet base) against your deployed routes.
Proof: commits c1b5bee and 1944aae on ios/work; device install via xcodebuild -allowProvisioningUpdates plus devicectl
===================
