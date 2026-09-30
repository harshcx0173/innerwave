# InnerWave Office Work — Login, Signup and Cross-Device Playback

Last updated: 29 September 2026

This file records the complete work conversation, decisions, implementation, setup, verification, and handoff beginning with the request for login/signup on web and mobile.

## 1. Conversation and decision timeline

### 1.1 Login, signup and Spotify-style sync request

User request:

> Web and mobile dono mein login/signup chahiye. Spotify ki tarah same ID se mobile aur PC login hone par play/pause, current song controls, volume aur related playback actions automatically sync hone chahiye.

Response and decision:

- Supabase was selected for authentication, database state, Realtime Broadcast, and Presence.
- The design uses one **active playback device**. Other signed-in devices act as remote controllers.
- Both devices display the same current track, queue, position, and playback state.
- Selecting “Play on this device” transfers playback ownership and resumes from the synchronized position.
- The existing web YouTube IFrame transport and Flutter device-side audio extraction remain separate. Expiring audio URLs are never sent between devices.

### 1.2 Scope clarification: app volume, not system volume

User clarification:

> System ko Spotify bhi control nahi kar sakta; synchronization sirf apni apps ke andar chahiye.

Response and decision:

- Only the InnerWave player volume is synchronized.
- Windows, Android, iOS, speaker, and hardware master volume are not changed.
- Mobile received a player-level volume property and control in the InnerWave Connect sheet.

### 1.3 Authentication requirements

User clarification:

> Email verification rakhna hai aur Sign in with Google bhi chahiye.

Response and decision:

- Email/password signup requires Supabase email confirmation.
- Signup displays a “Verify your email” screen when Supabase returns no active session.
- Google OAuth is implemented on both web and Flutter.
- The Flutter OAuth callback is `com.innerwave.mobile://login-callback/`.

### 1.4 Google Cloud and Supabase provider setup

User shared screenshots while creating:

- A Google OAuth **Web application** client named for InnerWave/Supabase.
- The Supabase callback URL as the Google authorized redirect URI.
- The Supabase Google provider configuration screen.

Response and guidance:

- Confirmed that a Web application OAuth client is correct for Supabase’s server-side OAuth callback.
- Confirmed the Supabase callback URI format.
- Asked the user to enable the Google provider with the Web client ID and secret.
- Recommended keeping nonce bypass disabled and “allow users without email” disabled.
- Warned that the Google OAuth client secret shared in chat must be rotated and must never be committed.

Security record:

- The Google OAuth client secret is intentionally **not reproduced in this file**.
- It was not added to the codebase.
- The user should rotate the exposed credential in Google Cloud if it has not already been rotated.

### 1.5 Supabase and deployment information

User provided:

- Supabase project URL: `https://gbqmtmcjqdqgfkzuwqot.supabase.co`
- A Supabase publishable client key.
- Production frontend: `https://innerwave-tau.vercel.app/`
- Existing API backend: `https://innerwave.onrender.com`

Response and implementation:

- The publishable key is used only in client configuration. No service-role key is used.
- Web values are read through `NEXT_PUBLIC_*` variables.
- Flutter supports `--dart-define` overrides and includes the supplied publishable client configuration as a default.
- A safe `.env.local.example` template was added; the real `.env.local` stays ignored by Git.

### 1.6 Implementation approval

After the provider configuration was completed, the user replied “Done” and then supplied the publishable key and production URL. Work continued with the agreed Supabase architecture.

## 2. Architecture implemented

### 2.1 Authentication

```text
Web / Flutter
      │
      ├── Email + password signup
      │       └── Mandatory verification email
      ├── Email + password sign-in
      ├── Google OAuth
      └── Supabase Auth session
```

- Auth sessions persist and refresh automatically.
- Unauthenticated users see the auth screen instead of the music application.
- Authenticated account metadata supplies the display name.
- Web local display-name overrides are scoped by user ID to prevent one account inheriting another account’s local name.

### 2.2 InnerWave Connect

```text
Signed-in web ─────┐
                   ├── Private Realtime topic
Signed-in mobile ──┘   innerwave:<user-id>:playback
                          │
                          ├── Presence: online devices
                          ├── Broadcast: commands and live state
                          └── Postgres: reconnect/refresh snapshot
```

- Each installation receives a stable device ID stored locally.
- Presence advertises device ID, readable name, platform, and online timestamp.
- `active_device_id` determines which device owns the real audio transport.
- A controller sends targeted commands to the active device.
- The active device executes commands and broadcasts the resulting canonical state.
- State revisions reject older updates and origin IDs prevent normal echo loops.
- The active device broadcasts live state approximately every second.
- A durable state snapshot is upserted approximately every five seconds.

### 2.3 Synchronized state and controls

Implemented synchronization for:

- Current track metadata
- Full current queue
- Queue index
- Play and pause
- Next and previous
- Seek position and duration
- InnerWave app volume
- Queue reordering
- Active playback device
- Queue continuation token
- Refresh/reconnect recovery

Flutter also routes its existing repeat, shuffle, remove-from-queue, and clear-upcoming actions through the remote-command boundary. Web currently has no repeat/shuffle UI, so those two mobile-only controls apply when Flutter is the active player.

### 2.4 Playback transfer behavior

- Choosing another online device stores and broadcasts the latest track, queue, position, play state, and volume.
- The old device pauses its local transport.
- The selected device loads its own platform-specific transport and resumes from the transferred position.
- Transfer-to-self is handled explicitly, including when the track ID has not changed.
- A browser may require one user gesture because browsers can block autoplay.

### 2.5 Existing queue and streaming behavior preserved

- Web continues using the YouTube IFrame player.
- Flutter continues resolving streams directly on the listener’s device with the vendored `youtube_explode_dart` `visionOs` client.
- Render is still used for catalog/home/search/related/queue metadata, not as the primary mobile audio extractor.
- Quick Picks, Because You Listened, Covers and Remixes, Trending Songs for You, Long Listens, personal shelves, and eligible discovery shelves still start a song-radio queue.
- Albums and playlists still preserve explicit collection order.
- Controller devices do not independently load more queue results or rebuild radio queues; only the active player owns queue continuation.

## 3. Database and security changes

File: `supabase/migrations/001_auth_and_connect.sql`

### Tables

- `public.profiles`
  - User ID linked to `auth.users`
  - Display name
  - Avatar URL
  - Created/updated timestamps
- `public.playback_sessions`
  - One row per user
  - Active device ID
  - JSON playback snapshot
  - Revision number
  - Updated timestamp

### Policies and trigger

- Row Level Security is enabled.
- Authenticated users can access only their own profile and playback session.
- A trigger creates or updates a profile from Supabase Auth metadata.
- Existing auth users are backfilled when the migration runs.
- Private Realtime policies authorize Broadcast and Presence only when the topic user ID matches `auth.uid()`.
- Topic format is `innerwave:<auth-user-id>:playback`.

## 4. Web changes

### New files

- `frontend/src/lib/supabase.ts`
  - Browser Supabase singleton.
  - Persistent session, token refresh, and OAuth URL detection.
- `frontend/src/context/auth-context.tsx`
  - Loads and observes Supabase sessions.
  - Email sign-in/signup, Google OAuth, sign-out, and display-name resolution.
- `frontend/src/components/auth-screen.tsx`
  - InnerWave-themed login/signup UI.
  - Name, email, password, Google sign-in, errors, and verification confirmation.
- `frontend/src/components/auth-gate.tsx`
  - Loading/authenticated/unauthenticated routing gate.
- `frontend/src/context/connect-context.tsx`
  - Device ID, private channel, Presence, command routing, state broadcasts, device transfer, and durable snapshot storage.
- `frontend/.env.local.example`
  - Safe environment variable template without private secrets.

### Updated files

- `frontend/src/app/page.tsx`
  - Provider order: Auth → AuthGate → Player → Connect → MusicApp.
- `frontend/src/context/player-context.tsx`
  - Added `PlayerSnapshot` and `PlayerCommand`.
  - Separated local playback actions from public command dispatch.
  - Added command interceptor for remote-controller mode.
  - Added remote command and remote snapshot application.
  - Prevented controller devices from starting the YouTube transport or loading radio continuation.
  - Added transfer-safe seek/play behavior.
- `frontend/src/components/topbar.tsx`
  - Added InnerWave Connect status button.
  - Added online device picker, active “Playing” indicator, and sign-out action.
- `frontend/src/components/music-app.tsx`
  - Uses Supabase account display name.
  - Local name override is now account-scoped.
  - The old mandatory local-name onboarding no longer appears after authenticated login.
- `frontend/src/app/globals.css`
  - Auth screen and device menu styling.
- `frontend/package.json` and `package-lock.json`
  - Added `@supabase/supabase-js`.
- `frontend/.gitignore`
  - Keeps local env files ignored while allowing `.env.local.example` to be committed.

## 5. Flutter changes

### New files

- `mobile/lib/core/config/supabase_config.dart`
  - Supabase URL, publishable key, optional Dart define overrides, and mobile callback URI.
- `mobile/lib/core/auth/auth_controller.dart`
  - Session listener, signup, signin, Google OAuth, sign-out, and account display name.
- `mobile/lib/core/auth/auth_screen.dart`
  - Flutter login/signup and email-verification UI.
  - Includes Google sign-in.
- `mobile/lib/core/sync/playback_sync_controller.dart`
  - Stable device identity.
  - Private Realtime channel.
  - Presence device list.
  - Targeted playback commands.
  - Active-device transfer.
  - Live and durable state synchronization.

### Updated files

- `mobile/lib/main.dart`
  - Initializes Supabase before AudioService.
  - Adds AuthController and PlaybackSyncController providers.
  - Uses AuthGate before MainNavigationShell.
  - Adds InnerWave Connect sheet with account, device selection, app-volume slider, and sign-out.
- `mobile/lib/core/audio/player_provider.dart`
  - Adds app volume state and `setVolume`.
  - Adds command interception and local/remote execution guard.
  - Adds playback snapshots and remote snapshot restoration.
  - Adds transfer start position and autoplay control to stream loading.
  - Ignores local audio callbacks when the device is only a controller.
  - Keeps existing local YouTube stream-resolution behavior.
- `mobile/android/app/src/main/AndroidManifest.xml`
  - Adds the OAuth deep-link intent filter.
- `mobile/ios/Runner/Info.plist`
  - Registers the OAuth URL scheme.
- `mobile/pubspec.yaml` and `pubspec.lock`
  - Adds `supabase_flutter`.
- Generated desktop plugin registrant files
  - Updated automatically because of the Supabase Flutter dependency.
- `mobile/test/widget_test.dart`
  - Updated smoke test to test the auth entry UI without requiring an AudioService instance.

## 6. Supabase dashboard steps

Run `supabase/migrations/001_auth_and_connect.sql` once in the Supabase SQL editor.

Authentication → URL Configuration:

```text
Site URL:
https://innerwave-tau.vercel.app

Redirect URLs:
https://innerwave-tau.vercel.app/auth/callback
http://localhost:3000/auth/callback
com.innerwave.mobile://login-callback/
```

Authentication → Providers:

- Email: keep Confirm email enabled.
- Google: keep the configured Web OAuth client enabled.
- Do not enable skip nonce checks unless a verified platform-specific need appears.
- Do not allow users without an email.

Realtime:

- Use private channels.
- The SQL migration provides the topic authorization policies.

## 7. Vercel variables

Add the following variables and redeploy:

```text
NEXT_PUBLIC_API_URL=https://innerwave.onrender.com
NEXT_PUBLIC_SUPABASE_URL=https://gbqmtmcjqdqgfkzuwqot.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<Supabase publishable key>
NEXT_PUBLIC_SITE_URL=https://innerwave-tau.vercel.app
```

The publishable key may be present in browser/mobile clients. A Supabase service-role key and the Google OAuth client secret must never be present in frontend or Flutter source.

## 8. Verification performed

- `npm run lint`: passed with no findings after final fixes.
- `npm run build`: passed.
  - Next.js production compilation passed.
  - TypeScript passed.
  - Static page generation passed.
- `flutter test`: all 3 tests passed.
- `flutter analyze`: zero compile errors.
  - Remaining warnings/info are pre-existing fullscreen-player deprecations/unused helpers and informational issues in the vendored YouTube package.
- `git diff --check`: passed; only Windows line-ending notices were printed.
- Secret scan found no Google OAuth secret, `client_secret`, or Supabase service-role credential in source files.

## 9. Disk management performed

- Checked free space on all available drives.
- Removed only generated, reproducible artifacts after verification:
  - `frontend/.next`
  - `mobile/build`
- Approximately 3.3 GB was recovered from drive D.
- Dependency folders were retained to avoid unnecessary future downloads.
- The separately preserved test APK was not deleted.

## 10. Manual end-to-end test checklist

1. Run the SQL migration.
2. Add every redirect URL and verify email confirmation is enabled.
3. Add Vercel environment variables and redeploy.
4. Create a new account using email/password.
5. Open the verification email and complete confirmation.
6. Sign in on production web.
7. Sign in to the same account on Flutter mobile.
8. Confirm both devices appear in InnerWave Connect.
9. Start a discovery song and confirm the song-radio queue remains correct.
10. Test play/pause, next, previous, seek, and app volume from the controller device.
11. Transfer playback from mobile to web and web to mobile.
12. Refresh the controller and active player separately and verify track, queue, and position restoration.
13. Test Google login on web and mobile.
14. If web transfer does not autoplay, click play once to satisfy the browser autoplay policy.

## 11. Known limitations and future improvements

- Presence represents currently connected app instances; it is not a permanent device registry.
- Network latency may cause a short delay before a controller reflects the active player’s newest position.
- Browser autoplay policies can block a transfer until the first user gesture.
- Web currently has no dedicated repeat/shuffle UI, although Flutter keeps its existing controls.
- Multi-device conflict resolution uses revision ordering and one active-device ID; a future server-side compare-and-swap/RPC can make simultaneous transfers even stricter.
- Playlists, likes, history, and personalized preferences are still mostly local and can be migrated to user-owned Supabase tables later.

## 12. Related documentation

- `PROJECT_STATUS.md`: overall project status.
- `AUTH_CONNECT_WORK_LOG.md`: concise authentication and sync implementation handoff.
- `STREAMING_QUEUE_WORK_LOG.md`: streaming and queue work.
- `AntigravityOfficeWork.md`: earlier office implementation log.

## 13. Git handoff

- Repository: `https://github.com/harshcx0173/innerwave.git`
- Branch: `main`
- Git author: `harshcx0173 <harshcx0173@gmail.com>`
- Local-only `.env.local` remains ignored and is not part of the commit.
- Google OAuth client secret is excluded from the repository and this work log.
