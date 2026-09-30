# InnerWave Auth & Connect Work Log

Date: 29 September 2026

## Goal

Add one verified InnerWave account for web and Flutter, Google sign-in, and Spotify-Connect-style control between signed-in devices without changing the existing YouTube streaming or song-radio queue architecture.

## Implemented

- Supabase email/password authentication on web and Flutter.
- Email verification flow remains enforced by Supabase; signup shows a dedicated “check your inbox” state.
- Google OAuth on web and Flutter.
- Android and iOS callback scheme: `com.innerwave.mobile://login-callback/`.
- Account-scoped web display name so another signed-in user does not inherit the previous user’s local name.
- `profiles` and `playback_sessions` database schema with user-owned RLS.
- Private Supabase Realtime channel per user: `innerwave:<user-id>:playback`.
- Presence-based list of online web/mobile devices.
- Exactly one active playback device. Other devices act as remote controllers.
- Synced current song, complete queue, queue index, play/pause, next/previous, seek position, app volume, and queue reordering.
- Durable playback snapshot in Postgres for refresh/reconnect recovery.
- State broadcast every second and durable snapshot approximately every five seconds while the device is active.
- Command origin/target IDs and increasing revisions prevent normal echo loops and stale state application.
- “InnerWave Connect” device picker and sign-out UI on both platforms.
- Flutter stream extraction remains local via the existing `visionOs` client; Realtime never carries stream URLs.
- Discovery shelves still start a song-based radio queue, while albums/playlists preserve their collection order.

## Main files changed

- `supabase/migrations/001_auth_and_connect.sql`: profiles, durable playback session, RLS, private Realtime authorization.
- `frontend/src/context/auth-context.tsx`: session and auth actions.
- `frontend/src/context/connect-context.tsx`: web presence, device transfer, broadcast commands/state, durable snapshot.
- `frontend/src/context/player-context.tsx`: local/remote command boundary and snapshot application.
- `frontend/src/components/auth-screen.tsx`: web sign-in/signup/verification UI.
- `frontend/src/components/topbar.tsx`: web device picker and logout.
- `mobile/lib/core/auth/*`: Flutter auth controller and UI.
- `mobile/lib/core/sync/playback_sync_controller.dart`: Flutter Realtime device coordination.
- `mobile/lib/core/audio/player_provider.dart`: remote commands, transfer-safe playback, and app volume.
- Android manifest and iOS Info.plist: OAuth deep links.

## Supabase dashboard setup required

1. Run `supabase/migrations/001_auth_and_connect.sql` once in the Supabase SQL editor.
2. Authentication → URL Configuration:
   - Site URL: `https://innerwave-tau.vercel.app`
   - Redirect URL: `https://innerwave-tau.vercel.app/auth/callback`
   - Redirect URL: `http://localhost:3000/auth/callback`
   - Redirect URL: `com.innerwave.mobile://login-callback/`
3. Authentication → Providers → Email: keep **Confirm email** enabled.
4. Authentication → Providers → Google: keep the configured Web OAuth client enabled.
5. Realtime settings: use private channels; the migration authorizes only the signed-in user’s own topic.

## Vercel environment variables required

```text
NEXT_PUBLIC_API_URL=https://innerwave.onrender.com
NEXT_PUBLIC_SUPABASE_URL=https://gbqmtmcjqdqgfkzuwqot.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<Supabase publishable key>
NEXT_PUBLIC_SITE_URL=https://innerwave-tau.vercel.app
```

Redeploy Vercel after adding the variables.

## Verification completed

- `npm run lint`: passed.
- `npm run build`: passed; production Next.js bundle and TypeScript compilation succeeded.
- `flutter test`: passed, 3/3 tests.
- `flutter analyze`: 0 compile errors. Existing warnings/info remain in legacy fullscreen player and the vendored YouTube package.

## Manual verification still required

- Run the SQL migration and dashboard URL configuration above.
- Create an email account, click its verification link, then sign in on web and mobile.
- Google sign in once on web and once on mobile.
- Open both devices on the same account, select each device in turn, and verify play/pause, seek, next/previous, volume, and queue transfer.
- Browser autoplay policy can require one initial click after transferring playback to web.
- Google OAuth intentionally opens the system browser on mobile; the registered deep link returns to InnerWave after authentication.
- Use the verification screen’s resend action if an older confirmation email was generated before the production callback was allow-listed.

## Security note

Only the Supabase publishable key belongs in clients. Never add a Supabase service-role key or Google OAuth client secret to this repository. The previously shared Google client secret should be rotated in Google Cloud if it has not already been rotated.
