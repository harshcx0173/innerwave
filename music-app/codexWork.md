# InnerWave Codex Work Log

## Session metadata

- Date: 30 September 2026
- Time zone: Asia/Calcutta (`UTC+05:30`)
- Work started: `2026-09-30 11:01:33 +05:30`
- First implementation checkpoint: `2026-09-30 11:17:57 +05:30`
- Code/test/device work completed: `2026-09-30 11:23:07 +05:30`
- Repository: `https://github.com/harshcx0173/innerwave.git`
- Branch: `main`
- Starting commit: `8e9195c feat: add Supabase auth and cross-device playback sync`
- Requested safety threshold: stop safely when the primary Codex window reaches **40% remaining**.
- Primary usage at start: **2% used / 98% remaining**.
- Primary usage during the implementation checkpoint: **18% used / 82% remaining**.

## User report

The user reported three authentication redirect problems:

1. On `https://innerwave-tau.vercel.app/`, **Continue with Google** redirected to localhost.
2. Email signup confirmation also redirected to localhost.
3. On Flutter mobile, Continue with Google opened Chrome instead of returning to InnerWave.

The user also requested:

- Stop work and report when only 40% of the primary Codex limit remains.
- Work safely and preserve progress.
- Create this new `codexWork.md` file containing the entire task timeline, answers, diagnosis, changes, functionality, verification, and timestamps, similar to the previous office work log.

## Initial response and working assumptions

The initial response explained:

- The three symptoms likely shared one Supabase configuration cause.
- Supabase falls back to its configured Site URL when a requested `redirectTo` URL is not allow-listed.
- Opening Chrome for Google OAuth on mobile is expected when using `LaunchMode.externalApplication`; the bug is failure to return from Chrome to the app after authentication.
- Code and dashboard redirect settings both needed verification.

## Investigation timeline

### `2026-09-30 11:01–11:04 +05:30` — Usage and source audit

- Checked Codex usage before modifying code.
- Confirmed 98% of the primary five-hour window remained.
- Verified the Git worktree was clean at commit `8e9195c`.
- Inspected:
  - `frontend/src/context/auth-context.tsx`
  - `frontend/src/lib/supabase.ts`
  - `frontend/.env.local.example`
  - `mobile/lib/core/auth/auth_controller.dart`
  - `mobile/lib/core/config/supabase_config.dart`
  - Android manifest, application ID, and MainActivity
- Confirmed web was asking Supabase to redirect to `window.location.origin`.
- At initial diagnosis, mobile was asking Supabase to redirect to `com.innerwave.mobile://login-callback/`; the trailing slash was later confirmed to mismatch the saved Supabase allow-list entry.
- Confirmed Android source registered the same scheme and host.
- Confirmed Android application ID and Kotlin package are both `com.innerwave.mobile`.

### Live Supabase project check

Queried the public Supabase Auth settings endpoint using the publishable client key.

Confirmed:

- Google provider: enabled
- Email provider: enabled
- Signup: enabled
- Email auto-confirm: disabled, so verification is mandatory
- No private/service-role credential was used

The public settings endpoint does not expose Site URL or Additional Redirect URLs.

### Official documentation verification

Checked current official Supabase documentation for:

- Auth redirect URL allow-list behavior
- Site URL behavior
- Mobile deep-link callback URLs
- Flutter/native OAuth return flow

The documentation confirms that custom web and mobile redirect targets must be added under Authentication → URL Configuration, and that native OAuth launches a browser before deep-linking back to the app.

### Supabase dashboard inspection

- Opened the exact project URL Configuration page.
- The browser reached the Supabase dashboard login screen.
- Because the dashboard session was not authenticated, the Site URL and redirect allow-list could not be read or changed during this step.
- No password, saved credential, OTP, or authentication dialog was automated.
- The user must sign in to the dashboard before the remaining configuration can be saved.

## Root cause evidence

### Web redirects

The production code was already sending the active Vercel origin. Redirecting to localhost despite that request strongly indicates that the requested production URL was not accepted by the Supabase redirect allow-list, causing fallback to the configured localhost Site URL.

### Mobile redirect

At `2026-09-30` the connected Android phone was queried with:

```text
com.innerwave.mobile://login-callback
```

Before reinstalling the new build, Android returned:

```text
No activity found
```

This proved that the phone was running an older InnerWave APK that did not contain the new OAuth deep-link intent filter, even though the current source code did.

Therefore the mobile issue had two relevant conditions:

1. Supabase must allow the mobile callback URL.
2. The updated InnerWave APK containing the callback intent filter must be installed.

## Code changes

### 1. Dedicated web authentication callback

Changed `frontend/src/context/auth-context.tsx`:

- Added `authCallbackUrl()`.
- The callback is derived from the browser’s current origin:

```text
<current-origin>/auth/callback
```

- Production Google OAuth now requests:

```text
https://innerwave-tau.vercel.app/auth/callback
```

- Production email verification requests the same callback.
- Local development requests:

```text
http://localhost:3000/auth/callback
```

Using the active origin avoids hardcoding localhost into production behavior and also supports the real deployed host.

### 2. New callback route

Created:

```text
frontend/src/app/auth/callback/page.tsx
```

The route:

- Reads OAuth errors returned in the callback query.
- Exchanges a PKCE authorization `code` when present.
- Reads an implicit-flow session when Supabase has already restored it from the URL.
- Listens for a late `SIGNED_IN`/session event.
- Redirects authenticated users to `/`.
- Shows a branded progress screen while finishing sign-in.
- Shows a recoverable error state instead of leaving the user on a blank callback page.
- Includes a 15-second timeout with a safe return-to-sign-in action.

### 3. Web verification-email recovery

Changed:

- `frontend/src/context/auth-context.tsx`
- `frontend/src/components/auth-screen.tsx`

Added:

- `resendVerification(email)` using Supabase `auth.resend` with type `signup`.
- The resend request uses the new `/auth/callback` URL.
- The verification screen now offers **Resend verification email**.
- Errors and loading state are displayed.

This allows the user to replace a confirmation email that was generated with the old localhost redirect.

### 4. Flutter verification-email recovery

Changed:

- `mobile/lib/core/auth/auth_controller.dart`
- `mobile/lib/core/auth/auth_screen.dart`

Added:

- `resendVerification(email)` with `OtpType.signup`.
- Mobile resend uses `com.innerwave.mobile://login-callback`.
- The mobile verification screen now includes a resend button, loading state, error output, and success Snackbar.

### 5. Environment template correction

Changed `frontend/.env.local.example`:

- Replaced the localhost example for `NEXT_PUBLIC_SITE_URL` with:

```text
https://innerwave-tau.vercel.app
```

- Documented that auth callback URLs are derived from the active browser origin.

## Android rebuild and direct device verification

### Build

Built the updated application with:

```text
flutter build apk --debug
```

Result:

```text
Built build\app\outputs\flutter-apk\app-debug.apk
```

### Installation

Replaced the existing app on connected device `RZGL504NCFW` using ADB.

Result:

```text
Performing Streamed Install
Success
```

### Deep-link verification after installation

Android package resolution then returned:

```text
com.innerwave.mobile/.MainActivity
```

The callback was launched once with ADB and Android reported:

```text
Status: ok
LaunchState: COLD
Activity: com.innerwave.mobile/.MainActivity
Complete
```

This verifies that the updated installed APK owns `com.innerwave.mobile://login-callback` and Android can return Chrome OAuth to InnerWave.

## Required Supabase dashboard configuration

The following values must be saved in Supabase → Authentication → URL Configuration.

### Site URL

```text
https://innerwave-tau.vercel.app
```

### Redirect URLs

```text
https://innerwave-tau.vercel.app/auth/callback
http://localhost:3000/auth/callback
com.innerwave.mobile://login-callback
```

Optional broader development/deployment patterns may be added only when genuinely needed. Exact production callbacks are preferred because they reduce redirect scope.

After saving the dashboard settings:

- Redeploy the Vercel frontend containing the new callback route.
- Use **Resend verification email** for any account whose older confirmation email contains localhost.
- On mobile, Continue with Google will still open Chrome initially. After Google/Supabase finishes, Chrome should open the registered InnerWave callback and return to the app.

## Verification results

### Web

- `npm run lint`: passed.
- `npm run build`: passed.
- TypeScript: passed.
- Static route generation: passed.
- New generated route confirmed:

```text
/auth/callback
```

### Flutter

- `flutter test`: all 3 tests passed.
- `flutter analyze`: zero compile errors.
- Analyzer still reports pre-existing informational/deprecation findings in fullscreen UI and vendored `youtube_explode_dart`; this auth task introduced no compile errors.
- Debug APK build: passed.
- ADB installation: passed.
- Android callback ownership: verified.
- Android callback launch: verified.

## Security decisions

- The previously exposed Google OAuth client secret was not used or reproduced.
- No service-role key was added.
- Only the existing Supabase publishable client key was used for the public Auth settings check.
- Supabase dashboard login credentials were not requested, read, or automated.
- The dashboard redirect configuration remains blocked until the user signs into Supabase.

## Disk-safety plan

- Generated `frontend/.next` and `mobile/build` folders are reproducible.
- After code verification and any required APK preservation, generated build folders will be removed to recover disk space.
- Source, dependency locks, the installed phone app, and documentation will be preserved.

## Current status at first checkpoint

Completed:

- Root cause isolated.
- Web callback code hardened.
- Web and mobile verification resend added.
- Web lint/build passed.
- Flutter tests passed.
- Flutter compile analysis has zero errors.
- Updated APK built and installed.
- Android deep-link return verified at OS level.

Remaining external step:

- Sign in to the Supabase dashboard and save the exact Site URL and Redirect URLs listed above.

This file will be updated with the final timestamp, Git commit, deployment/push status, disk cleanup, usage checkpoint, and final live-test result before the task is closed.

## Final session update

### Git

- Implementation commit created: `97964da fix(auth): correct web and mobile callback recovery`
- Final work-log commit created: `672fdab docs: record auth redirect diagnosis and verification`.
- Both commits were pushed to `origin/main` successfully.
- Git author remains `harshcx0173 <harshcx0173@gmail.com>`.

### Production deployment verification

- Verified at `2026-09-30 11:27:15 +05:30`.
- Requested `https://innerwave-tau.vercel.app/auth/callback` directly after the GitHub push.
- Production returned HTTP `200`.
- Returned HTML contained the new “Finishing sign in” callback UI.
- This confirms Vercel deployed the callback route successfully.

### Disk cleanup

After all builds, tests, APK installation, and deep-link verification completed:

- Removed generated `frontend/.next`: approximately `120.5 MB`.
- Removed generated `mobile/build`: approximately `2257.1 MB`.
- Total recovered in this cleanup: approximately `2.38 GB`.
- The newly built APK had already been installed successfully on the connected phone before cleanup.

### Usage safety checkpoint

- Primary usage after final GitHub/remote verification: **38% used / 62% remaining**.
- The requested stop point was 40% remaining.
- The threshold was not reached, so the work completed safely without an emergency stop.

### Final blocker and next action

The local code, production build, Flutter build, installed Android deep link, and automated tests are complete. The only remaining blocker is authenticated access to the Supabase dashboard.

The Supabase URL Configuration login tab was intentionally left open. After the user signs in, save:

```text
Site URL
https://innerwave-tau.vercel.app

Redirect URLs
https://innerwave-tau.vercel.app/auth/callback
http://localhost:3000/auth/callback
com.innerwave.mobile://login-callback
```

Then test:

1. Production Google login returns to `/auth/callback` and then `/`.
2. Resent email confirmation returns to `/auth/callback` and then `/`.
3. Mobile Google login opens Chrome and then returns to the installed InnerWave app.

## Mobile OAuth trailing-slash fix — 2026-09-30 11:54:40 +05:30

### User report

- The production web Google login was retested by the user and works correctly.
- The Flutter app still completed Google OAuth at `http://localhost:3000` instead of returning to InnerWave.

### Server-level diagnosis

The source and installed Android app were checked first:

- Flutter sent `com.innerwave.mobile://login-callback/`.
- Android registered scheme `com.innerwave.mobile` with host `login-callback`.
- The installed package resolved that deep link to `com.innerwave.mobile/.MainActivity`.

A read-only OAuth cancellation probe was then run against the Supabase Auth authorize/callback flow. Only the final destination origin/path was printed; no access token, provider token, refresh token, or OAuth state was logged.

Results:

```text
https://innerwave-tau.vercel.app/auth/callback
  -> accepted unchanged

com.innerwave.mobile://login-callback/
  -> rejected/fell back to http://localhost:3000

com.innerwave.mobile://login-callback
  -> accepted unchanged
```

This proves the remaining issue was an exact-string mismatch: the Supabase redirect allow-list contained the no-trailing-slash callback while Flutter sent the trailing-slash callback.

### Code and documentation changes

- Updated `mobile/lib/core/config/supabase_config.dart` so `mobileCallback` is exactly `com.innerwave.mobile://login-callback`.
- Added a code comment explaining that a trailing slash is a different Supabase redirect and may fall back to the configured Site URL.
- Corrected the canonical callback in `AUTH_CONNECT_WORK_LOG.md`, `codeworkoffice.md`, `PROJECT_STATUS.md`, and this work log.
- No queue, streaming, player, web auth, database, or cross-device sync behavior was changed.

### Verification

- `flutter test`: all 3 tests passed.
- `flutter analyze --no-fatal-infos --no-fatal-warnings`: zero compile errors; only 22 pre-existing warnings/info remain.
- `flutter build apk --debug`: passed.
- `adb install -r`: succeeded on device `RZGL504NCFW`.
- Android resolved the exact callback to `com.innerwave.mobile/.MainActivity`.
- ADB callback launch completed successfully with `Status: ok` and `LaunchState: COLD`.
- Supabase cancellation probe confirmed the exact no-slash callback no longer falls back to localhost.

### Disk and usage safety

- Disk before the rebuild: C `19.52 GB` free, D `46.33 GB` free, E `2.12 GB` free, F `24.93 GB` free.
- After APK installation, permanently removed only generated `mobile/build` (`2257.0 MB`); D increased to `47.53 GB` free.
- Primary Codex window after diagnosis/build: `52% used / 48% remaining`.
- The requested `40% remaining` stop threshold had not been reached at this checkpoint.

### Git delivery

- Commit: `d334f42 fix(auth): align mobile OAuth callback`.
- Pushed successfully to `origin/main` (`ec0b323..d334f42`).
- Git author verified as `harshcx0173 <harshcx0173@gmail.com>`.
- The updated APK was installed on the connected phone before generated build cleanup.

## Production Connect API diagnosis — 2026-09-30 12:04:22 +05:30

### User report

- Web and mobile authentication now work.
- `GET /rest/v1/playback_sessions` and `POST /rest/v1/playback_sessions` return HTTP 404.
- “Choose where music plays. Controls stay synced.” does not function.

### Verified root cause

Read-only calls using the public publishable key returned:

```text
public.profiles          -> 404 PGRST205
public.playback_sessions -> 404 PGRST205
```

Supabase message:

```text
Could not find the table 'public.playback_sessions' in the schema cache
```

This proves the entire production Auth/Connect migration has not been applied. The frontend URL, REST path, logged-in user filter, and client key are reaching the correct Supabase project; the database objects do not exist there.

### Required production action

Run the complete file below once in the Supabase SQL Editor for project `gbqmtmcjqdqgfkzuwqot`:

```text
supabase/migrations/001_auth_and_connect.sql
```

The complete migration is required because it creates:

- `public.profiles`
- `public.playback_sessions`
- authenticated-user grants
- owner-only RLS policies
- profile trigger/backfill
- private Realtime Broadcast and Presence policies on `realtime.messages`

The Supabase CLI is not installed and no Supabase management access token/database password is present locally, so the migration cannot be safely applied from the terminal. The local migration file and the project SQL Editor were opened in Codex for the user. After the user runs it, recheck both REST resources and then test web/mobile Presence, device transfer, play/pause, seek, volume, and state persistence.

### Code status

- No application-code change is required for this 404.
- The checked-in migration already contains the missing schema and policies.
- No secret, access token, refresh token, or user session value was printed or stored.

## Logout/login playback recovery — 2026-10-02 13:37:01 +05:30

### User report and constraint

- After signing out and signing back in on web or mobile, the previous session's song remained stuck and neither that song nor newly selected songs would play.
- The user explicitly instructed that this work must **not** be pushed to GitHub.

### Root causes

1. Web player state and listening history used global browser storage keys, so one authenticated session could restore another session's stale local player snapshot.
2. Flutter player state, queue, history, play counts, and likes used global `SharedPreferences` keys instead of account-specific keys.
3. Flutter's long-lived `PlayerProvider` survived logout and retained the previous queue, audio transport, MediaStyle notification, command interceptor, and local-playback ownership state.
4. `playback_sessions.active_device_id` could continue pointing to a device that had gone offline during logout. After login, controls were intercepted and sent to that offline device, leaving the current device paused and apparently frozen.
5. Rapid logout/login events could overlap asynchronous reconnect/reset operations.
6. If durable Supabase playback-session storage was temporarily unavailable, Flutter reconnect could abort before establishing safe local playback.

### Implemented changes

#### Web

- `frontend/src/context/player-context.tsx`
  - Player persistence is now namespaced by authenticated user ID: `innertube-player-session-v2:<user-id>`.
  - Listening history is now namespaced as `innerwave-history:<user-id>`.
  - On account identity change, transport, queue, timing, continuation, error, autoplay, seen IDs, local-playback ownership, and command interception are reset before restoring that account's snapshot.
- `frontend/src/components/music-app.tsx`
  - Home recommendations and Library history now read the same per-user history key.
- `frontend/src/context/connect-context.tsx`
  - Presence sync detects when the persisted active device is offline.
  - If the current browser is online and the active device is absent, playback ownership is automatically reclaimed by the current browser.

#### Flutter mobile

- `mobile/lib/core/audio/player_provider.dart`
  - Added explicit authenticated session ownership with generation-based race protection.
  - Logout/account changes stop audio and clear the current song, queue, queue continuation, stream/queue requests, lyrics, timers, error, position, duration, cached ownership, history, likes, and notification state from memory.
  - Session, history, play counts, liked IDs, and liked songs are now stored under per-user keys.
  - Async persistence refuses to write if the authenticated owner changes while an operation is in flight.
- `mobile/lib/core/audio/innerwave_audio_handler.dart`
  - Added `clearMediaItem()` so logout removes the stale system media item and resets MediaSession controls to idle.
- `mobile/lib/core/sync/playback_sync_controller.dart`
  - Auth changes now await player-owner reset/restore before reconnecting.
  - Added reconnect-generation checks so an older logout/login task cannot overwrite a newer session.
  - Disconnect restores safe local playback and clears stale active-device/revision state.
  - Presence automatically reclaims playback when the stored active device is no longer online.
  - Failure to read durable `playback_sessions` is logged and falls back to local playback instead of breaking the player.

### Verification

- Frontend `npm run lint`: passed.
- Frontend clean `npm run build`: passed, including TypeScript and static generation.
- An initial build encountered a stale generated `.next/dev/types/validator.ts`; removing only `.next` and rebuilding resolved it, confirming no source TypeScript failure.
- Flutter `flutter test`: all 3 tests passed.
- Flutter analyzer: zero compile errors; remaining findings are existing style/deprecation/vendor information.
- Flutter debug APK: built successfully.
- Final APK: installed successfully on connected device `RZGL504NCFW`.
- Installed app process launched successfully and `com.innerwave.mobile/.MainActivity` was the foreground activity.

### Disk and delivery status

- Removed generated `frontend/.next`: `124.2 MB`.
- Removed generated `mobile/build`: `2257.8 MB`.
- Final free space: C `16.63 GB`, D `46.88 GB`, E `2.12 GB`, F `24.39 GB`.
- Primary Codex usage checkpoint before documentation: `54% used / 46% remaining`.
- No Git commit was created and nothing was pushed to GitHub, as explicitly requested.
- Pre-existing uncommitted Antigravity changes were preserved.

## Cross-device seekbar and synced-lyrics stabilization — 2026-10-02 13:52:28 +05:30

### User report

- During web/mobile synchronization, the seekbar repeatedly moved forward and backward.
- Synced lyrics repeatedly scrolled down, returned to the current timeline, and moved down again.
- During the same session, the web reported `playerRef.current?.setVolume is not a function` and `seekTo is not a function` from `YoutubeTransport`.
- The user changed the safety stop threshold to **10% primary usage remaining**.
- GitHub push remains explicitly prohibited.

### Root causes

1. The inactive web device correctly received one-second remote snapshots, but its hidden local YouTube iframe still emitted its own 500ms timer values. Both sources wrote `currentTime`, creating the forward/backward seekbar loop; lyrics followed the oscillating timeline.
2. A normal Realtime `state` event was allowed to replace the active-device ID. A delayed state packet from the previous owner could therefore undo a newer device transfer.
3. Equal revision packets were accepted, allowing duplicate/colliding state application.
4. Offline-device reclaim ran immediately and independently on each device. During presence convergence, multiple clients could temporarily see only themselves and claim playback simultaneously.
5. Web lyrics used `scrollIntoView`, which could scroll ancestors beyond the lyrics container.
6. The YouTube iframe player object can exist before its methods are ready. Optional chaining protected only the object, not missing `setVolume`/`seekTo` methods.

### Implemented fixes

- `frontend/src/context/player-context.tsx`
  - Hidden/local YouTube timer callbacks are ignored while that browser is not the active playback device.
  - Account-reset state updates are deferred inside the effect timer, satisfying React's effect-state rule.
- `frontend/src/context/connect-context.tsx`
  - Presence reclaim waits 800ms for the presence set to stabilize.
  - Online device IDs are sorted and only one deterministically elected device may reclaim an absent owner.
  - Initial no-owner state allows local playback until election completes.
  - Normal state packets must come from their declared active device, must match the currently known owner, and must have a strictly newer revision.
  - Only `active_device` transfer events may change an existing owner.
- `mobile/lib/core/sync/playback_sync_controller.dart`
  - Added the same delayed deterministic presence election.
  - Added strict owner validation and strictly increasing revision checks.
  - No-owner startup remains locally playable while presence converges.
  - Presence reclaim timer is cancelled during disconnect/dispose.
- `frontend/src/components/queue-panel.tsx`
  - Synced lyrics now scroll only their own panel using a calculated panel-local offset; ancestor/page scrolling is avoided.
- `frontend/src/components/youtube-transport.tsx`
  - Player commands are gated by an explicit ready state and method-existence checks.
  - Pending load, seek, volume, and play/pause/stop intent are queued until `onReady` returns a valid player target.
  - Stale/disposed iframe callbacks are rejected, timer getters are guarded, and cleanup safely destroys only the created player.

### Verification

- Frontend ESLint: passed.
- Frontend TypeScript (`tsc --noEmit --incremental false`): passed.
- Local dev server: HTTP 200 and rendered the InnerWave auth screen.
- Read-only browser runtime check after hot reload: zero console errors; the reported `setVolume` and `seekTo` TypeErrors did not recur.
- Flutter tests: all 3 passed.
- Flutter analyzer: zero compile errors; only 20 existing info/deprecation/vendor findings remain.
- Flutter debug APK build: passed.
- Phone installation could not be completed because ADB reported no connected device at install time.
- Updated local APK artifact: `InnerWave-streaming-queue-debug.apk` (`165.2 MB`).

### Disk, Git, and usage status

- Removed generated `mobile/build`: `2105.0 MB`.
- Final measured free space: C `16.40 GB`, D `46.84 GB`, E `2.12 GB`, F `24.39 GB`.
- `frontend/.next` was left in place because the user's dev server is currently running and actively uses it.
- Final primary usage checkpoint: `77% used / 23% remaining`; the new 10% stop threshold was not reached.
- No commit was created and nothing was pushed to GitHub.

## Web admin analytics, live presence and location fallback — 2026-10-02 17:44:13 +05:30

### Conversation and decisions

- The user requested a web-only admin panel showing total users, currently active users, active listeners, per-user playback, and each user's location.
- Exact device/browser location is the first choice. When the user denies location or location is unavailable, the backend-captured request IP is the fallback shown to the administrator.
- Denying location does **not** remove the user from the music app; the latest decision replaced forced exit with IP fallback.
- The requested admin route is `/musicadmin`.
- The supplied administrator email is used as the sole allow-listed admin identity. The supplied password is intentionally **not** written to source code, documentation, environment templates, or Git; Supabase Auth stores and validates it.
- The user clarified that the safety stop threshold applies to the five-hour Codex window: stop when 30% remains.

### Implemented architecture

- `supabase/migrations/002_admin_presence.sql`
  - Adds `public.user_presence` with one row per user/device, listening state, track metadata, location permission, GPS coordinates/accuracy, request IP and heartbeat timestamps.
  - Adds owner-only insert/update RLS and admin-email-only select RLS.
  - Adds an admin select policy for `public.profiles`, allowing an exact registered-user count without exposing user data to normal listeners.
- `backend/app/main.py`
  - Adds authenticated `POST /api/presence`.
  - Verifies the Supabase bearer session against `/auth/v1/user`; it never trusts a client-provided user ID or email.
  - Captures the request IP server-side and writes presence through the caller's JWT/RLS permissions.
  - Adds admin-only `GET /api/admin/overview`, verifies the allow-listed admin email again, aggregates multi-device rows per user, and defines active as a heartbeat within 90 seconds.
  - GPS is returned as the preferred source. Raw IP is returned to the admin response only when GPS is not available.
- `frontend/src/components/presence-reporter.tsx`
  - Requests browser geolocation, tracks changes, and sends authenticated presence every 30 seconds.
  - Reports current track/listening state; denied/unavailable location naturally uses backend IP fallback.
- `frontend/src/app/musicadmin/page.tsx` and `frontend/src/components/admin-dashboard.tsx`
  - Adds the protected `/musicadmin` route with an admin-specific login.
  - Prefills only the admin email; the password field is always blank and never embedded.
  - Shows total users, active users, active listeners, available locations, user/device status, current track, GPS accuracy/map links or IP fallback, and last-active time.
  - Refreshes live data every 15 seconds.
- `mobile/lib/core/sync/playback_sync_controller.dart`
  - Adds foreground location permission/reporting and a 30-second authenticated presence heartbeat.
  - Current track and listening state are included without interrupting playback if analytics fails.
- Mobile platform configuration
  - Adds `geolocator`, Android coarse/fine location permissions, and the iOS when-in-use purpose description.

### Configuration and deployment required

1. Run `supabase/migrations/002_admin_presence.sql` once in the production Supabase SQL Editor.
2. Redeploy Render so the new presence/admin endpoints are live. Optional environment overrides are documented in `backend/.env.example`.
3. Set `NEXT_PUBLIC_ADMIN_EMAIL=harsh.b.mevada@gmail.com` in Vercel (the same safe default exists in code) and redeploy the frontend.
4. Ensure the administrator account exists in Supabase Auth with the requested email and a private password. No password is present in the repository.
5. Rebuild/reinstall the Flutter app so the new native location permissions and geolocation plugin are included.

### Verification status at documentation time

- Backend Python compilation passed.
- Frontend production build passed and generated `/musicadmin` successfully.
- Mobile focused analyzer passed with zero issues.
- Flutter tests passed: 3/3.
- Frontend lint initially found two React effect-state findings; fixes were applied and the final rerun is recorded below after completion.
- Final frontend ESLint rerun passed with zero errors.
- Final Next.js production build passed TypeScript/static generation and included `/musicadmin`.
- Backend imported successfully in the project virtualenv; `/api/presence` and `/api/admin/overview` were confirmed in the FastAPI route table.
- Generated `mobile/build` (1282.8 MB), `frontend/.next` (204.7 MB), and Python bytecode cache were removed after verification. D drive free space recovered to 46.82 GB.
- Five-hour Codex usage checkpoint after implementation: 6% used / 94% remaining, above the requested 30% remaining stop threshold.
- No Git commit or push was performed for the admin-panel changes.

## Admin missing mobile users/location repair — 2026-10-02 18:25:05 +05:30

### User report

- A newly created mobile user did not appear in `/musicadmin` after refresh.
- The user was also absent from `public.profiles` in Supabase.
- Mobile GPS/location was not visible in the admin dashboard.

### Root cause and resilience gaps

1. The admin overview used `profiles` as its only base user list. If the Auth-to-profile trigger was missing or had not run, both that user and an otherwise valid `user_presence` row were hidden.
2. The production database needs an explicit trigger repair/backfill because an Auth user already exists without a profile row.
3. The installed phone build could still be the pre-location APK; native permission/plugin changes only take effect after rebuilding and reinstalling.
4. Mobile presence requests ignored non-2xx responses, making missing migration/RLS/deployment failures invisible in device logs.

### Implemented repair

- Added `supabase/migrations/003_repair_profiles_presence.sql`:
  - recreates the `on_auth_user_created` trigger;
  - backfills every existing `auth.users` row into `public.profiles`;
  - updates existing profile metadata safely;
  - adds owner insert policy as a resilience fallback;
  - is idempotent and safe to rerun.
- Updated `backend/app/main.py` so presence-only users are merged into the admin list even if a profile row is temporarily missing.
- Updated mobile `PlaybackSyncController` to log presence HTTP failures and response bodies without interrupting music playback.

### Verification and device delivery

- Backend compile/import passed.
- Flutter focused analyzer passed with zero issues.
- Flutter tests passed: 3/3.
- Latest debug APK built successfully and installed on connected Samsung `SM-S931B`.
- App data was cleared during the approved reinstall, so the mobile app requires sign-in again and will request location permission on the first authenticated session.
- Production still requires running migration `003_repair_profiles_presence.sql` and redeploying the backend repair before the dashboard can reflect the fix.

## Mobile presence RLS diagnosis — 2026-10-02

- The user's attached `flutter run` output confirmed `Geolocator position updates started`, proving the native location plugin and permission path are active.
- The actual failure was backend HTTP 403 with PostgreSQL code `42501`: `new row violates row-level security policy for table "user_presence"`.
- PostgREST upsert uses `ON CONFLICT` and needs to inspect the caller's existing row. The schema had owner INSERT/UPDATE policies and admin SELECT, but no owner SELECT policy.
- Added idempotent migration `004_presence_upsert_policy.sql`, granting authenticated users SELECT access only to their own presence rows. Admin-only cross-user visibility remains unchanged.
- Production recovery order is now: run `003_repair_profiles_presence.sql` for profiles/trigger/backfill, then run `004_presence_upsert_policy.sql` for presence heartbeat upserts.

## Location permission re-enable recovery — 2026-10-02

- The user requested that a listener who previously denied location should automatically return to GPS display in `/musicadmin` after re-enabling permission.
- Web `PresenceReporter` now restarts its geolocation watcher during the 30-second heartbeat whenever the previous watcher ended through denial, timeout, or unavailability.
- Mobile `PlaybackSyncController` now rechecks both OS permission and the device location-service state every 30 seconds.
- When permission/service becomes available again, the mobile position stream restarts automatically and immediately sends fresh coordinates.
- When permission is revoked or location services are disabled, stale coordinates are cleared and the next heartbeat falls back to server-captured IP.
- Backend upsert overwrites the same user/device row, so the admin panel changes from IP fallback back to GPS without logout/relogin.
- Frontend ESLint and production build passed. Flutter focused analyzer passed with zero issues and Flutter tests passed 3/3.
