# InnerWave Codex Work Log

## Session metadata

- Date: 30 September 2026
- Time zone: Asia/Calcutta (`UTC+05:30`)
- Work started: `2026-09-30 11:01:33 +05:30`
- First implementation checkpoint: `2026-09-30 11:17:57 +05:30`
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
- Confirmed mobile was asking Supabase to redirect to `com.innerwave.mobile://login-callback/`.
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
com.innerwave.mobile://login-callback/
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
- Mobile resend continues using `com.innerwave.mobile://login-callback/`.
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

This verifies that the updated installed APK now owns `com.innerwave.mobile://login-callback/` and Android can return Chrome OAuth to InnerWave.

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
com.innerwave.mobile://login-callback/
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
