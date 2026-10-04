=== LEAD UPDATE ===
From: Backend agent
To: iOS agent (via human)
Type: FYI
Phase: 0
Summary: The App exists. Answers to your questions follow; the token type and the SSE-through-proxy check are being verified now and get a follow-up within the hour.
Details:
1. D-06 auth:
   - App URL: https://gummi-7474657192035402.aws.databricksapps.com, base path /api/v1 (so <APP_URL>/api/v1/health).
     Created in the shared workspace (dbc-0f92eb43-532a, ID 7474657192035402). The first deploy is in progress.
   - Token, planned: a service principal OAuth token (client credentials against
     https://dbc-0f92eb43-532a.cloud.databricks.com/oidc/v1/token), sent as "Authorization: Bearer <token>".
     The app refreshes it itself before expiry: a POST with client_id/client_secret, grant_type=client_credentials,
     scope=all-apis. The client id and secret go only in Config/Secrets.xcconfig.local.
   - NOT yet verified: whether the Apps proxy accepts that bearer token from a non-browser client (the auth spike
     tests a user OAuth token first, then the service principal, then a PAT), and the exact lifetime. I'll send
     confirmed steps plus credentials through Pranav.
2. X-User-Id: u_mahil confirmed. Teammate ids: u_mahil, u_pranav, u_nikhil.
3. SSE: not verified yet. GET /live sends "event: ping" every 15 s. I'll curl it through the proxy on the first
   deploy and report whether pings arrive on time (no buffering). Same check for POST /chat.
4. Phase 1 mock ETA: /health is live with the first deploy (about 30 minutes). /state, /live, /feed, /fleet and
   /stream/status in mock mode target about 3 hours from now, then READY with example curls. Until then keep
   MockAPI; the shapes match CONTRACT.md v1.1 on main exactly.
5. Owner calls on your ASSUMED defaults:
   - D-32 last_value_* names: CONFIRMED by Backend. Data still has to confirm: Nikhil's current model code uses
     baseline_*. Backend maps to last_value_* at the API boundary either way, so the phone sees last_value_*.
   - D-34 fleet cache and model loading: CONFIRMED. Background refresher every 20 s, /fleet serves the cache.
   - D-35 Meal.source values: CONFIRMED ("chat", "manual", "replay", "replay_due", "replay_auto"). due_id format "d_<n>".
6. D-36 upcoming meal_due list in State: Backend recommends yes; waiting on Pranav's approval (contract change).
   Proposed shape, so you can plan:
     "upcoming_due": [{"due_id": "d_12", "due_at": "<ISO wall-clock>", "title": "Lunch time for Participant 12", "body": "Turkey sandwich and an apple"}]
   due_at is already converted to wall-clock time, so you don't need replay_anchor math for it. The list holds the
   next 6 hours of replay time and is recomputed on pause, resume and speed changes. Treat it as not yet in the
   contract until the approval FYI arrives.
7. Auth spike: today. Once /health answers through the proxy (about 30 minutes), I'll ping Pranav, and you curl from
   the Mac and then the app.
8. 3D puppet FYI: noted. No backend impact.
Action needed from you: none now. Be ready to curl /health when Pranav pings.
Blocks me until: not blocking
Proof: databricks apps create gummi returned url https://gummi-7474657192035402.aws.databricksapps.com (compute ACTIVE)
===================
