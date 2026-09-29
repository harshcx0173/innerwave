# InnerWave Streaming and Queue Work Log

Last updated: 2026-09-29 (Asia/Calcutta)

## Agreed scope

- Fix mobile audio streaming without changing the working home, search, browse,
  lyrics, related-content, or frontend APIs.
- Keep mobile queue behavior aligned with the local web application.
- Keep disk usage minimal and stop work when either relevant Codex usage window
  reaches approximately 40% remaining.

## Architecture decision

Render remains the metadata backend for home, search, browse, lyrics, related
content, and `/api/next`. Audio stream extraction no longer uses Render and no
longer depends on a hidden YouTube iframe. The Flutter app resolves a fresh
YouTube audio URL on the listener's device, then plays it with `just_audio`.

This avoids the Render datacenter-IP bot challenge that affected `/api/stream`.

## Implemented changes

### Device-side streaming

- Added `just_audio` as the mobile audio transport.
- Replaced `youtube_player_iframe` in `PlayerProvider`.
- Vendored only the approximately 0.5 MB runtime portion of Musify's maintained
  `youtube_explode_dart` fork.
- Pinned source provenance in
  `mobile/packages/youtube_explode_dart/INNERWAVE_SOURCE.md`.
- Uses the tokenless `YoutubeApiClient.visionOs` manifest client.
- Selects audio-only streams by bitrate and attempts the remaining formats if
  the first CDN stream fails.
- Keeps stream request IDs so a slow previous song cannot replace a newer song.
- Preserves existing play/pause, seek, next, previous, repeat, shuffle, sleep
  timer, duration, and buffered-position interfaces used by the UI.

### Queue parity with local web

- Search-result songs now start a song-based radio queue instead of using the
  search results list as the queue.
- These home shelves now start a song-based queue, matching the local web app:
  Quick picks, Because you listened, Covers and remixes, Trending songs for
  you, Long listens, `personal-*`, and the mapped discovery shelf IDs.
- Albums, playlists, library lists, and ordinary collection shelves retain their
  explicit track context.
- A one-song context (for example the featured card) expands into radio results.
- Added a queue request ID and captured seed song, preventing an older `/api/next`
  response from overwriting the queue after the user switches songs.
- Existing deduplication remains active for current, queued, and previously seen
  song IDs.

## Files changed

- `mobile/pubspec.yaml`: replaced iframe dependency with `just_audio` and the
  local extractor package.
- `mobile/pubspec.lock`: regenerated dependency lock.
- `mobile/lib/main.dart`: removed the hidden mounted iframe widget.
- `mobile/lib/core/audio/player_provider.dart`: direct stream resolution,
  `just_audio` transport, stream-format fallback, and stale queue-response guard.
- `mobile/lib/core/audio/queue_policy.dart`: shared web-parity shelf policy.
- `mobile/lib/features/home/home_screen.dart`: applies the shelf queue policy.
- `mobile/lib/features/explore/explore_screen.dart`: search starts radio queue.
- `mobile/test/queue_policy_test.dart`: regression tests for radio versus
  collection shelves.
- Flutter-generated desktop plugin registrant files changed automatically after
  removing the iframe/WebView plugin.
- `mobile/packages/youtube_explode_dart/`: minimal vendored extractor runtime,
  original README, package manifest, and BSD-3-Clause license.

The pre-existing user modification in `mobile/.gitignore` was preserved.

## Verification completed

- `flutter pub get`: passed.
- `flutter test test/queue_policy_test.dart`: 2 tests passed.
- Changed app sources compile; analyzer reports only the pre-existing
  `withOpacity` deprecation in `explore_screen.dart` after the two local
  flow-control style infos were corrected.
- `flutter build apk --debug`: passed.
- Direct resolver probe for the previously selected song `1ujERBhuN48`:
  - 5 audio-only streams returned.
  - selected itag 251 at about 142.53 Kbit/s.
  - CDN Range request returned HTTP 206 and the requested bytes.
- Live `/api/next` probe for the same seed returned 36 unique items, excluded
  the seed song, and returned no continuation token for that response.

## Pending device verification

The connected Samsung phone disconnected from ADB immediately before APK
installation. The latest APK was preserved at
`InnerWave-streaming-queue-debug.apk`, but this exact build still needs to be
installed and tested on the phone for:

1. Audible playback and timeline progress.
2. Pause, resume, seek, next, and previous.
3. Quick Picks/search creating a radio queue.
4. Album/playlist playback retaining collection order.
5. Queue scrolling and duplicate prevention.
6. Switching tracks quickly while `/api/next` is still loading.

Do not mark mobile streaming fully verified until these device checks pass.

After preserving the APK, `flutter clean` removed approximately 2.3 GB of
generated build intermediates. Task-only screenshots, the sparse Musify clone,
and formatting backup were also permanently removed. Existing unrelated files
inside `D:\Learn\InnerTube\.codex-temp` were left untouched.

## Licensing

The vendored extractor package includes its original BSD-3-Clause license. It
was copied from `gokadzev/Musify` commit
`5b98d3a3cddd3fdb16ea6cc14d59d667e82cccd2`; the whole Musify application was
not copied.

## 2026-09-29 - Device playback confirmed; queue parity diagnosis

- The user confirmed that songs now load/play on the connected phone. This validates the device-side streaming change based on `youtube_explode_dart` + `just_audio`.
- Remaining issue: the mobile Up Next queue does not match the good local-web queue and contains weak/incorrect recommendations.
- Root cause found in `backend/app/main.py`: the first `/api/next` request (`videoId` present and no `continuation`) immediately calls `_search_recommendations(...)` and returns `source: "search-radio"` with `continuation: null`.
- That branch bypasses `MusicService.next(...)`, even though `backend/app/service.py` already builds the real YouTube Music radio playlist id (`RDAMVM<videoId>`) and supports continuation-based queue loading.
- Therefore the poor queue is primarily a backend queue-source problem, not an audio-player problem. Search results are being used as a radio substitute, so relatedness and ordering are weaker and infinite/scroll continuation cannot work properly.

### Exact next implementation

1. Change `/api/next` to try `service.next(...)` first for a new seed song.
2. Parse and return that real YouTube Music radio queue with its continuation token.
3. Use `_search_recommendations(...)` only as a fallback when the upstream radio request fails or returns no usable songs.
4. Preserve the existing mobile duplicate protection (`_seenIds`) and stale-request guard.
5. Test the same seed on local web and mobile, verify queue order/quality, scrolling, no repeats, then deploy the backend to Render.

### Stop condition

- No functional queue code was changed in this session after this diagnosis.
- Work stopped with the primary Codex window at 41% remaining, immediately before the user-requested 40% stop threshold, so the backend change is not left half-applied.

## 2026-09-29 - Radio-first queue fix implemented

- The user changed the stop threshold from 40% to 30% remaining.
- Updated `backend/app/main.py` so `/api/next` now calls `MusicService.next(...)` first and returns `source: "youtube-radio"` when YouTube Music supplies a usable queue.
- `_search_recommendations(...)` is retained only as `source: "search-radio-fallback"` for a new seed whose watch-next request fails or returns empty on a throttled cloud IP.
- A failed continuation request now returns 502 instead of replacing the existing queue with unrelated search results; the client retains its already loaded tracks.
- Updated `mobile/lib/core/api/music_api.dart` queue cache key to `queue_v2_...`, preventing an upgraded device from reusing an older search-generated queue for up to ten minutes.
- Added `backend/tests/test_next_queue.py` covering real-radio priority, search fallback, and continuation failure behavior.

### Verification

- Backend unit tests: 3/3 passed.
- Real local InnerTube request for seed `E8zOp4Kqcls`: `source=youtube-radio`, 50 tracks, and a continuation token.
- Continuation probe returned no new unique songs for this particular upstream response; the existing mobile duplicate filters correctly discard that repeated item. The initial 50-song radio queue remains intact.
- `git diff --check` found no whitespace errors.
- A Flutter test attempt stalled without output and was stopped; the two Dart processes created by that attempt were terminated. The previously completed queue-policy test and APK verification remain recorded above.
- The active/in-use Flutter build directory was not removed. No new APK was built in this pass because only the API cache-key string changed and the saved APK predates that change.
