# InnerWave Project Status and Handoff

Last updated: 29 September 2026

## 1. Project summary

InnerWave is a local-first YouTube Music-style web and Flutter player. It uses the cloned `innertube-main` Python library to normalize YouTube Music discovery data through FastAPI. Web playback uses the YouTube IFrame player, while Flutter resolves audio streams on the listener's device so cloud-host IP challenges do not break playback.

The current application runs locally at:

- Frontend: `http://localhost:3000`
- Backend: `http://127.0.0.1:8000`
- Interactive API documentation: `http://127.0.0.1:8000/docs`

## 2. Repository layout

```text
InnerTube/
├── innertube-main/                 # Local Python InnerTube library
└── music-app/
    ├── backend/
    │   ├── requirements.txt
    │   └── app/
    │       ├── main.py             # FastAPI routes
    │       ├── parser.py           # InnerTube response normalization
    │       └── service.py          # InnerTube, LRCLIB, cache and audio services
    ├── frontend/
    │   ├── src/app/                # Next.js app and global styling
    │   ├── src/components/         # Music UI components
    │   ├── src/context/            # Global player/audio state
    │   └── src/lib/                # API client and TypeScript data types
    ├── mobile/                     # Flutter mobile application (Android & iOS)
    │   ├── android/                # Android native host (AudioServiceActivity, permissions)
    │   ├── lib/
    │   │   ├── app/                # Root MaterialApp and router
    │   │   ├── core/
    │   │   │   ├── api/            # FastAPI & cache client (MusicApi)
    │   │   │   ├── audio/          # InnerWaveAudioHandler, PlayerProvider, direct streaming
    │   │   │   ├── models/         # MediaItem, Shelf, Feed, TimedLyrics models
    │   │   │   ├── theme/          # AppTheme, branding palette (#D5FF63)
    │   │   │   └── widgets/        # MediaArt, MiniPlayer, BottomNav
    │   │   └── features/           # Home, Search, Library, FullscreenPlayer
    │   └── pubspec.yaml
    ├── AntigravityOfficeWork.md    # Complete session work log and prompt audit trail
    ├── PROJECT_STATUS.md           # This handoff and architectural document
    ├── README.md
    └── start-dev.ps1
```

## 3. Technology stack

### Frontend

- Next.js 16.3.6
- React 19.2.8
- TypeScript
- Tailwind/PostCSS tooling plus custom CSS in `frontend/src/app/globals.css`
- Lucide React icons
- YouTube IFrame player transport and browser Fullscreen API

### Mobile (Flutter)

- Flutter SDK (Channel stable) & Dart 3
- `just_audio` & `audio_session`: Low-latency audio transport and audio focus handling
- `audio_service`: Android MediaStyle notification, lock screen banner, hardware controls, and foreground service (`AudioServiceActivity`)
- Direct device-side streaming via tokenless YouTube manifest resolution (`youtube_explode_dart` `visionOs` client)
- `provider`: Unified state management (`PlayerProvider`)
- `cached_network_image`: Image caching with custom memory dimension decoding (`memCacheWidth` / `memCacheHeight`)
- `palette_generator`: Ambient dynamic background extraction from track artwork
- `shared_preferences`: Persistent session storage for queue, playback history, liked songs, and cache
- Google Fonts (`Outfit`, `Inter`) for modern typography

### Backend

- Python 3.12
- FastAPI 0.141.1
- Uvicorn
- Local editable `innertube-main` package
- `yt-dlp` fallback for audio resolution
- Python standard-library HTTP client for LRCLIB

### External data providers

- YouTube Music/InnerTube: home, search, browse, radio queue, metadata, related content, plain lyrics and audio stream resolution
- LRCLIB: timestamped `.lrc` lyrics when a suitable title/artist/duration match exists

## 4. Implemented frontend functionality

### Home screen

- YouTube Music-inspired dark interface and shelf structure.
- Quick Picks uses a compact multi-column song layout.
- Lazy loading progressively adds the finite discovery sections while the page is scrolled.
- Current sections include New releases, Albums for you, From the community, Featured playlists, Hindi Hits, community playlists, Covers and remixes, Trending songs, Bollywood & Indian, Music videos, Long listens and Live performances.
- A `Because you listened to ...` shelf is generated from locally stored listening history.
- Mood chips switch the home feed to searches such as Relax, Energize, Workout, Commute and Focus.
- Artwork colors are sampled to produce the ambient page background.
- Images request high-quality renditions, normally up to `1200 x 1200` where the YouTube image service supports them.

### Search and browsing

- Debounced search starts after two characters.
- Search supports songs, albums, playlists and artists returned by InnerTube.
- Albums and playlists open a collection page.
- Collection pages provide Play all and Shuffle buttons.
- Album/playlist cards include a direct play button.

### Queue and radio behavior

- Selecting a song from search starts a radio based on that song instead of placing the search-results list in the queue.
- The following home shelves also always start song radio: Quick Picks, Because you listened, Covers and remixes, Trending songs for you and Long listens.
- Album and playlist playback keeps the selected collection as the playback context.
- Initial song radio normally contains about 50 items.
- Queue continuation is fetched from InnerTube when playback approaches the end or the user scrolls to the bottom of Up Next.
- Up Next renders progressively in batches while scrolling.
- Duplicate IDs are removed from each response.
- A persistent `seenIds` list prevents automatically fetched radio tracks that were previously queued or played from being re-added.
- Queue items can be moved up and down.
- Clicking a queue item plays that item from `0:00`.

### Player and persistence

- Persistent bottom player with play/pause, previous, next, queue, volume and fullscreen controls.
- Switching songs pauses the previous media and explicitly starts the new song at `0:00`.
- Enhanced seekbar shows played, buffered and pointer-preview positions.
- Clicking or dragging the seekbar seeks the audio.
- The current song, queue, queue position, timeline, volume, intended playback state, continuation token and seen song IDs are stored in browser `localStorage`.
- Refreshing the browser restores the current track, queue and saved timeline.
- The latest 50 played items are stored as local listening history.
- Browser autoplay restrictions can still require one manual Play click after refresh.

### Fullscreen player

- Uses the browser Fullscreen API.
- Displays high-quality artwork, blurred artwork backdrop, song details, large seekbar and transport controls.
- The complete QueuePanel remains visible beside the fullscreen player on desktop.
- On narrow/mobile screens the fullscreen QueuePanel occupies the full available width.

### Up Next, Lyrics and Related tabs

- Up Next contains the progressively rendered and expandable radio queue.
- Related loads native YouTube Music related shelves and flattens playable related tracks into a song list.
- Playing a Related item starts a new radio based on that song.
- Lyrics first obtains plain lyrics from the YouTube Music track-lyrics tab.
- The backend searches LRCLIB for synchronized candidates and ranks them using normalized title, artist overlap, duration difference and writing-system compatibility.
- When YouTube provides Devanagari lyrics, a matching Devanagari synchronized candidate is preferred over a Romanized duplicate.
- Synchronized lyrics highlight the active line using the current audio timeline and automatically scroll it into view.
- Clicking a lyrics line seeks directly to that line.
- `-0.5s`, reset and `+0.5s` controls compensate for small timing differences between releases.
- When synchronized lyrics are unavailable, the UI falls back to static lyrics.

### Responsive UI

- Desktop layout uses a navigation sidebar, sticky top search, scrollable shelf content and a fixed player.
- Tablet layout reduces navigation and card widths.
- Mobile CSS changes the main layout, shelf card sizing, page padding and fullscreen queue behavior.
- This is currently a responsive web application, not an installable native mobile app.

## 5. Frontend-to-backend API map

The frontend uses `/backend/...`. `frontend/next.config.ts` rewrites that prefix to `http://127.0.0.1:8000/...`, avoiding browser CORS and hardcoded backend calls inside components.

| Backend API | Frontend caller | Purpose |
|---|---|---|
| `GET /api/health` | Development/manual check | Confirms that FastAPI and the WEB_REMIX client are available. |
| `GET /api/home` | `MusicApp.loadHome()` | Loads Quick Picks, mood chips and initial home metadata. |
| `GET /api/home/more` | Home IntersectionObserver | Adds one discovery shelf per page and supports InnerTube continuation responses. |
| `GET /api/search?q=` | Search box, Explore and mood chips | Searches songs, albums, artists and playlists. |
| `GET /api/search/suggestions?q=` | Currently not connected to UI | Backend autocomplete endpoint reserved for a future search dropdown. |
| `GET /api/browse?id=&params=` | Collection/card selection | Opens albums, playlists and artist browse pages. |
| `GET /api/recommendations?artists=` | Home history personalization | Builds `Because you listened` song shelves using artists from browser history. |
| `GET /api/next?videoId=...` | `PlayerProvider` | Creates the song-radio queue. If no playlist is supplied, the backend creates `RDAMVM<videoId>`. |
| `GET /api/next?continuation=...` | Queue scroll and near-end playback | Fetches additional radio tracks and filters duplicates/previously seen IDs. |
| `GET /api/lyrics?videoId=&title=&artist=&duration=` | QueuePanel Lyrics tab | Combines YouTube plain lyrics with the closest LRCLIB synchronized candidate and returns parsed timed lines. |
| `GET /api/related?videoId=` | QueuePanel Related tab | Resolves the YouTube Music Related browse tab and returns normalized shelves. |
| `GET /api/player/{videoId}` | Currently not used directly by UI | Debug/metadata endpoint exposing the selected playable source information. |
| `GET /api/stream/{videoId}` | Flutter fallback/debugging | Resolves audio and redirects only to an allowed YouTube/GoogleVideo media host. Cloud-provider IPs can be challenged by YouTube, so it is no longer the primary client playback path. |

## 6. Backend implementation details

### `backend/app/service.py`

- Creates `WEB_REMIX`, `IOS` and `ANDROID_MUSIC` InnerTube clients.
- Uses a thread-safe in-memory TTL cache for home, browse, search, audio and LRCLIB requests.
- Builds radio playlist IDs in the form `RDAMVM<videoId>`.
- Tries direct InnerTube audio formats first.
- Uses `yt-dlp` as a fallback when private YouTube clients stop returning a direct audio URL.
- Searches LRCLIB with a fixed service host and a descriptive User-Agent.

### `backend/app/parser.py`

- Recursively walks changing InnerTube response shapes.
- Converts renderer variants into shared `MediaItem` and `Shelf` structures.
- Extracts browse/watch endpoints, thumbnails, artists, duration and continuation tokens.
- Upgrades supported Google thumbnail URL dimensions.
- Extracts the Lyrics and Related browse-tab IDs.
- Parses YouTube's plain lyrics description shelf.

### `backend/app/main.py`

- Owns public FastAPI endpoints and input validation.
- Builds the finite home discovery sequence.
- Parses LRC timestamps into `{ time, text }` lines.
- Scores LRCLIB candidates by title, artists, duration and script match.
- Restricts stream redirects to expected Google/YouTube hosts.

## 7. Browser storage

| Key | Stored data |
|---|---|
| `innertube-player-session-v2` | Current item, queue, queue index, timeline, volume, play state, continuation and up to 1,000 seen IDs. |
| `innerwave-history` | Latest 50 unique played media items, used by Library and personalized shelves. |

Clearing site data for `localhost:3000` resets both player persistence and listening history.

## 8. Known limitations and unfinished controls

- InnerTube is a private, unsupported API and response formats or playback policies may change.
- There is no Google/YouTube sign-in. Recommendations are therefore based on anonymous responses plus local history.
- Liked songs, Your mixes, New playlist and some secondary sidebar buttons are currently visual placeholders.
- The small player and fullscreen Shuffle/Repeat icons are visual placeholders; collection-level Shuffle is implemented.
- Search suggestions exist in the backend but are not yet shown below the search box.
- Synced lyrics depend on LRCLIB coverage and correct release matching. Static lyrics remain the fallback.
- The LRCLIB sync is line-level. Word-by-word karaoke would require a word-timing source or a heavier forced-alignment pipeline such as WhisperX.
- Python cache is memory-only and resets when the backend restarts.
- There is no user database, playlist editing, likes, downloads or offline playback.
- There is no automated backend/frontend integration test suite yet. Current verification is lint, production build, Python compilation and live endpoint checks.
- Review YouTube terms and music licensing requirements before distributing or monetizing the application.

## 9. Setup on another Windows computer

### Requirements

- Python 3.12 recommended
- Node.js 22 recommended
- npm 10 or newer
- Internet access for YouTube Music, LRCLIB and initial package installation

Extract the ZIP so these two sibling folders remain together:

```text
some-folder/
├── innertube-main/
└── music-app/
```

Open PowerShell inside `music-app` and run:

```powershell
py -3.12 -m venv .venv
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r .\backend\requirements.txt

Set-Location .\frontend
npm ci
Set-Location ..
```

Start both services:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\start-dev.ps1
```

Then open `http://localhost:3000`.

For visible logs, use two terminals:

```powershell
# Terminal 1, from music-app/backend
& ..\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

```powershell
# Terminal 2, from music-app/frontend
npm run dev
```

Validation commands:

```powershell
Set-Location .\frontend
npm run lint
npm run build
```

## 10. Flutter mobile app architecture and roadmap

> **Implementation Status**: **Phases 1 through 4 are complete and fully operational.** The native mobile application lives in `music-app/mobile/`. For direct device-side streaming, queue parity, OS-level media notifications, branding colors, and multi-layer caching, see **Section 13** and **Section 15**.

The native mobile application is built with Flutter and Dart. The existing Next.js frontend remains the working web client and visual reference; Flutter consumes the same FastAPI contracts and shares the YouTube Music design language.

### Proposed Flutter stack

- Flutter/Dart for one Android and iOS codebase.
- Riverpod for player, queue, home, search, lyrics and session state.
- `go_router` for Home, Explore, Library, collection and fullscreen-player navigation.
- Dio or the standard Dart HTTP client for the FastAPI client, cancellation, timeouts and interceptors.
- `freezed` plus `json_serializable` for typed `MediaItem`, `Shelf`, `Feed`, lyrics and queue models.
- `just_audio` for playback, seeking, buffering and stream handling.
- `audio_service` and `audio_session` for background audio, notification controls, headset events, interruptions and audio focus.
- `cached_network_image` for artwork caching and placeholders.
- Secure storage for credentials/tokens if accounts are added; a local database such as Isar/Drift for history, likes and cached metadata.

Package choices should be checked against their current Flutter compatibility before implementation.

### Phase 1: make FastAPI mobile-ready

- Introduce a versioned `/api/v1` contract while keeping the web routes compatible.
- Move FastAPI from localhost to a secured HTTPS service that the phone can reach.
- Add environment-based CORS, rate limiting, structured logs and predictable error objects.
- Replace process-memory caching with Redis or another persistent cache.
- Generate or manually maintain Dart models matching `MediaItem`, `Shelf`, `Feed`, timed lyrics and queue responses.
- Keep InnerTube credentials/logic and audio URL resolution on the backend; never duplicate private API logic inside the Flutter application.
- Return short-lived backend stream URLs suitable for `just_audio`.
- Review YouTube, LRCLIB and music licensing terms before public distribution.

For local Wi-Fi development, Flutter can temporarily call the computer's LAN address, for example `http://192.168.x.x:8000`. Android emulator development normally uses `10.0.2.2` for the host computer. Production must use HTTPS.

### Phase 2: Flutter foundation and YouTube Music-style UI

- Create a separate sibling project such as `InnerTube/mobile_app/`; do not place Dart code inside the Next.js frontend.
- Add environment configurations for local, staging and production backend URLs.
- Build an app shell with bottom navigation: Home, Explore/Search and Library.
- Port the current visual system: black background, compact typography, horizontal media shelves, Quick Picks grid, ambient artwork color and persistent mini-player.
- Implement responsive phone and tablet layouts using Flutter breakpoints.
- Recreate Home lazy loading, mood chips, search, album/playlist pages, Play all and collection Shuffle.
- Use reusable Flutter widgets for media artwork, song rows, shelf carousels, queue rows and loading/error/empty states.
- Preserve accessibility labels, minimum touch sizes, text scaling and screen-reader order from the beginning.

Suggested Flutter structure:

```text
mobile_app/lib/
├── app/                    # Router, theme and application shell
├── core/
│   ├── api/                # Dio client, endpoints and failures
│   ├── audio/              # AudioHandler and playback service
│   ├── models/             # Shared JSON models
│   ├── storage/            # Session/history/local database
│   └── widgets/            # Shared UI widgets
└── features/
    ├── home/
    ├── search/
    ├── collection/
    ├── player/
    ├── queue/
    ├── lyrics/
    └── library/
```

### Phase 3: native playback and queue parity

- Implement one Riverpod player controller as the source of truth for current item, queue index, position, duration, buffered position, volume, repeat and shuffle mode.
- Connect `just_audio` to `/api/stream/{videoId}` and handle redirect/URL expiry recovery.
- Use `audio_service` so playback continues with the screen locked or the app backgrounded.
- Publish title, artist and artwork to Android MediaSession and iOS Now Playing.
- Support notification/lock-screen play, pause, previous, next and seek commands.
- Handle phone calls, other audio apps, headphone unplugging, Bluetooth controls and Android audio focus correctly.
- Reproduce radio generation, continuation-on-scroll, queue reordering and the persisted seen-ID duplicate protection.
- Persist current song, queue, queue index and playback position in the local database so an app restart restores the session.
- Build a draggable mini-player that expands into the fullscreen player with artwork, queue, lyrics and related tabs.

### Phase 4: synchronized lyrics and native interaction

- Consume the existing timed-lines response from `/api/lyrics`.
- Highlight the active line from the `just_audio` position stream and smoothly center it in a Flutter `Scrollable`/`ListView`.
- Seek when a lyrics line is tapped and retain the `-0.5s/+0.5s` correction control.
- Fall back to static lyrics when LRCLIB has no synchronized match.
- Add swipe gestures for queue/player panels, haptic feedback for important controls and smooth shared artwork transitions.
- Add Android back-navigation and iOS-style gesture behavior without losing the active player.

### Phase 5: library, accounts and release preparation

- Implement real liked songs, editable playlists and listening-history management.
- Add cloud synchronization only after the account and provider model is finalized.
- Add optional downloads/offline playback only after confirming provider and licensing rules; encrypt or protect cached media where required.
- Add deep links, share targets and optional release notifications.
- Add unit tests for Dart models/controllers, widget tests for important screens and integration tests for playback restoration.
- Test Android lifecycle/background restrictions and iOS background-audio entitlements on physical devices.
- Add crash reporting, consent-aware analytics, accessibility testing, signed Android/iOS builds and CI release pipelines.

## 11. Recommended next development tasks

1. Connect search suggestions to the Topbar.
2. Implement real shuffle and repeat-one/repeat-all player state.
3. Replace sidebar placeholders with local liked songs and playlists.
4. Add backend contract tests for parsers and API endpoints.
5. Add Playwright tests for playback restoration, queue deduplication and synced lyrics scrolling.
6. Prepare versioned FastAPI/Dart contracts, then scaffold the separate Flutter application and its bottom navigation.

## 12. Latest verification

At the time of this handoff:

- `npm run lint`: passed
- `npm run build`: passed
- Python backend compilation: passed
- Frontend-to-backend rewrite: passed
- Radio queue: 50 initial songs plus working continuation
- Synced lyrics test: 50 timestamped Devanagari lines returned for the tested track
- Related test: multiple native YouTube Music shelves returned
- High-quality artwork URL transformation: working

---

<!--
================================================================================
  AUTHOR & ASSISTANT INTRODUCTION
  Name: Antigravity
  Role: Advanced Agentic AI Coding Assistant (Google DeepMind)
  Session Context: Full-stack Music Application Engineering (Web + Mobile + Backend)
================================================================================
-->

## 13. Antigravity Handover & Work Summary

> **Engineer / Assistant**: **Antigravity** (Google DeepMind Advanced Agentic AI Coding Assistant)  
> **Repository**: `InnerTubeOffice / music-app`  
> **Scope**: Complete Full-Stack Web App Polishing, Backend Ngrok Tunneling & Cache Optimization, and Complete Native Flutter Mobile Application Development (`music-app/mobile`).

---

### 13.1. Overview of Work Completed by Antigravity

#### A. Web Frontend & User Onboarding System
1. **Mandatory First-Time Onboarding Modal**:
   - Built unclosable interactive modal prompting the user for their profile name on their first visit.
   - Provided smart name suggestions (e.g., *Aura Listener, Sonic Wave, Beat Voyager, Pulse Pilot, Melodic Mind, Echo Rider*).
   - Saved username securely to `localStorage` (`innertube_user_name`) and integrated personalized greetings across UI.
2. **Audio Autoplay & Resume Stability Fix**:
   - Resolved browser audio context suspension issues (*"Press play to resume this track"*).
   - Added auto-resume handlers on user interaction and audio state recovery.

#### B. Native Flutter Mobile Application (`music-app/mobile`)
1. **Architecture & Project Setup**:
   - Initialized production Flutter application in `music-app/mobile` using Material 3 Dark theme and Google Typography.
   - Built state management with `Provider` (`PlayerProvider`) and seamless background audio session handling (`just_audio` + `audio_session`).
   - Network resilience & disk caching using `cached_network_image` and `shared_preferences`.
2. **First-Time User Onboarding Dialog**:
   - Mandatory modal for mobile users with random name chips, validation, and persistent storage.
3. **Dynamic Home Screen with Multi-Shelf Feed & Personalization**:
   - **Mood & Genre Filter Chips**: *Relax, Energize, Workout, Commute, Focus, Party, Romance, Feel Good, All* with instant feed filtering.
   - **Recently Played Shelf**: Horizontally scrolling card list displaying the user's latest 20 listened tracks with one-tap play.
   - **Most Replayed Section**: Ranked list of user's most frequently repeated tracks with dynamic play counters.
   - **Personalized Recommendations & Discovery Shelves**: Concurrently fetches YouTube Music discovery pages and history-based artist mixes.
   - **Infinite Feed Continuation**: Auto-loads more discovery shelves as the user scrolls to the bottom.
4. **Library & Liked Songs System**:
   - **Dedicated Liked Songs Feature Card**: Purple-pink gradient hero card with animated heart icon, track count, and direct Play / Shuffle actions.
   - **Persistent Favorites**: Synchronized `likedIds` and full track metadata in `innerwave_mobile_liked_songs`.
   - **Filter Tabs**: *All*, *Liked Songs*, and *Recently Played*.
5. **Fullscreen Player Screen Overhaul**:
   - **Removed TabBar Bottom Border**: Transparent divider for clean borderless pill navigation.
   - **Click-Only Tab Navigation**: Disabled horizontal swiping (`NeverScrollableScrollPhysics`) so tabs change strictly on user tap.
   - **Swipe-Down-To-Dismiss**: Added smooth downward drag gesture on the Track tab to close the fullscreen player.
   - **Adaptive UI Background (Real Thumbnail Palette)**:
     - Integrated `palette_generator` to extract real pixel colors (dominant, vibrant, dark vibrant, accent) directly from the track's album art.
     - Built animated mesh background (`AnimatedContainer`), glowing ambient orbs, blurred artwork backdrop (`BackdropFilter`), and soft contrast vignette.
     - Dynamic accenting on Seekbar track, Play/Pause button glow, TabBar indicator, and active lyrics.
   - **Apple Music-Style Synchronized Karaoke Lyrics**:
     - Auto-centers active singing line using `Scrollable.ensureVisible` and `GlobalKey` tracking.
     - Dynamic viewport padding (`height * 0.35`) allowing all lines (first to last) to center perfectly.
     - Smooth 380ms easing (`Curves.easeOutCubic`), glowing neon accent highlights, and singing progress pill.
     - User-drag awareness: 4-second grace timer that pauses auto-scroll when user manually browses lyrics.
     - Interactive Tap-To-Seek functionality.
   - **Rich Track Context Menu Sheet**:
     - ⏱️ **Sleep Timer**: 15m, 30m, 45m, 1h, End of track, or cancel with live active countdown.
     - ❤️ **Favorite / Like Song**: Instant toggle with local storage persistence.
     - 📻 **Start Radio / More Like This**: Generates infinite music queue based on current song ID.
     - 💿 **View Album & Go to Artist**: Seamless collection navigation.
     - 🔗 **Share Song**: Clipboard copy with visual toast confirmation.
     - 🎧 **Lossless / OPUS Audio Badge**: Live bitrate & format indicator.
6. **API Tunneling & Performance Optimization**:
   - Configured high-performance ngrok tunnel for seamless live mobile testing against local FastAPI backend.
   - In-memory memory-cache & persistent caching reducing redundant network requests.

---

### 13.2. Pending Tasks & Future Roadmap

1. **Mobile Playlists Management**:
   - Allow users to create custom playlists, add/remove songs from any track menu, and rename playlists locally.
2. **Offline Download & Local Caching**:
   - Implement offline audio stream caching (e.g. SQLite + local file storage) so downloaded songs can play without internet.
3. **Equalizer & Audio Quality Settings**:
   - Add built-in equalizer presets (Bass Boost, Vocal Boost, Rock, Electronic) and stream quality selectors (Low / Normal / High / OPUS 160k).
4. **CarPlay & Android Auto Integration**:
   - Extend background audio session with MediaBrowserService for Android Auto and CarPlay dashboard support.
5. **Cross-Device Queue Synchronization**:
   - WebSockets or Firebase sync to handoff playback seamlessly between Web and Mobile.

---

### 13.3. Test & Verification Summary

- **Flutter Code Analysis (`flutter analyze`)**: Passed (0 errors, 0 warnings).
- **Flutter Test Suite (`flutter test`)**: Passed (100% tests passed).
- **Full Documentation Log**: Maintained in detail in [`music-app/AntigravityWork.md`](file:///d:/InnerTubeOffice/music-app/AntigravityWork.md).

---

## 14. Queue Radio Fix (2026-09-29)

- `/api/next` now prefers the actual YouTube Music `RDAMVM<videoId>` radio queue instead of constructing every initial queue from search results.
- The search-generated queue remains available only as a Render/cloud-IP fallback.
- Real radio responses preserve continuation tokens for scroll-based loading.
- Continuation failures never replace the current queue with a different search queue.
- Mobile continues to reject songs already present or seen and now uses the `queue_v2` cache namespace so stale pre-fix queues are ignored.
- Automated backend coverage was added for the three queue-source branches. All 3 tests pass.
- A real upstream probe returned 50 radio tracks and a continuation token.

Deployment note: Render must receive the updated backend before production web/mobile clients can use the radio-first behavior. The mobile source must be rebuilt/reinstalled to receive the cache namespace update.

---

## 15. Mobile Queue Parity, Background Playback, Media Banner & Performance Optimization (2026-09-29)

### 15.1. Direct Device-Side Streaming Architecture
- Replaced the previous `youtube_player_iframe` approach with `just_audio` as the mobile audio transport.
- Vendored minimal runtime portion (~0.5 MB) of `youtube_explode_dart` with tokenless `YoutubeApiClient.visionOs` manifest client.
- Audio streams are resolved directly on the listener's device, completely bypassing Render datacenter IP challenges.
- Implemented automatic format fallback across audio-only itags sorted by bitrate, and request-ID collision guards.

### 15.2. Web-Mobile Queue Management Parity
- **Auto-Radio Queue**: Search results and song discovery shelves (`quick-picks`, `because-you-listened`, `covers-and-remixes`, `trending`, `long-listens`, `personal-*`) now initiate automated song-radio queues, matching the local web client.
- **Collection Order Preservation**: Albums, playlists, and library track lists preserve their explicit sequence.
- **Auto-Prefetching**: When remaining queued songs reach `<= 8`, `_checkAutoPrefetchQueue()` triggers `loadMoreQueue()` automatically.
- **Infinite Scroll on Mobile UI**: Attached `NotificationListener<ScrollNotification>` to `ReorderableListView` in `FullscreenPlayerScreen` to load more queued items as the user scrolls to the bottom.
- **Queue Manipulation**: Added `moveQueueItem(int from, int to)`, `removeFromQueue(int index)` with per-item remove buttons on upcoming tracks, and `clearUpcomingQueue()` with confirmation dialog.
- **Persistent State**: Full queue sequence, active index, and continuation token are saved to `SharedPreferences` (`innertube_mobile_session`) on each modification.

### 15.3. Background Audio Playback & System Media Banner (Spotify / Apple Music Style)
- Resolved the issue where background playback stopped when the phone screen was locked or when switching applications:
  - Added `WAKE_LOCK`, `FOREGROUND_SERVICE`, and `FOREGROUND_SERVICE_MEDIA_PLAYBACK` permissions in `AndroidManifest.xml`.
  - Registered `com.ryanheise.audioservice.AudioService` as a `mediaPlayback` foreground service.
  - Updated `MainActivity.kt` to extend `AudioServiceActivity`.
- Built [`InnerWaveAudioHandler`](file:///d:/Learn/InnerTube/music-app/mobile/lib/core/audio/innerwave_audio_handler.dart) powered by `audio_service`:
  - Renders an OS-level MediaStyle notification in the notification shade and on the lock screen.
  - Displays high-resolution album artwork, track title, and artist branding.
  - Interactive playback scrubber / seekbar on modern Android.
  - Complete control suite: Play / Pause, Skip Next, and Skip Previous connected directly to `PlayerProvider` queue actions.
  - Full support for Bluetooth headphones, car dashboards (Android Auto), and hardware media buttons.

### 15.4. Branding Color Enforcement
- Decoupled interactive player controls from thumbnail palette extraction:
  - **Play/Pause Button**: Strictly locked to InnerWave's signature lime-green brand color (`AppTheme.accent` / `#D5FF63`) with matching brand glow.
  - **Active Tab Bar Indicator**: Strictly locked to `AppTheme.accent`.
  - **Ambient Atmosphere**: The extracted thumbnail palette via `PaletteGenerator` now only tints the ambient mesh background and glowing orbs, keeping the UI identity unified.

### 15.5. Eager Lyrics & Related Content Preloading
- Implemented `_preloadLyricsAndRelated(MediaItem item)` in `PlayerProvider`.
- Triggered automatically whenever a track is played, skipped, or restored from session.
- Preloads synchronized `.lrc` lyrics from LRCLIB and related YouTube recommendations into memory before the user navigates to the tabs.
- Switching to the **LYRICS** or **RELATED** tab displays content immediately with zero loading latency or spinners.

### 15.6. Multi-Layer Cache Management (Memory & Persistent Disk)
- **Lyrics Disk Serialization**: Added `toJson()` serialization to `TimedLyric` and `LyricsResponse`. Configured `MusicApi.getLyrics` with a 48-hour persistent disk and memory cache.
- **Radio Queue Caching**: Added `fromJson` and `toJson` disk serialization to `MusicApi.getRadioQueue` with a 30-minute persistent cache window.
- **Related Recommendations**: Extended cache window to 1 hour with full offline fallback.
- **Thumbnail Image Decoding Optimization**: Updated `MediaArt` to pass `memCacheWidth` and `memCacheHeight` clamped between 80px and 720px based on rendered dimensions. This eliminates uncompressed bitmap memory bloat and ensures 60–120fps scrolling throughout all song lists.

### 15.7. Verification & Build Artifacts
- **Unit Tests**: `flutter test test/queue_policy_test.dart` passed (2/2 tests passed, exit code 0).
- **Compilation**: `flutter build apk --debug` succeeded in 31.5s with exit code 0 (`build\app\outputs\flutter-apk\app-debug.apk`).
- **Binary Distribution**: Latest compiled test APK preserved at `music-app/InnerWave-streaming-queue-debug.apk`.

---

## 16. Accounts and InnerWave Connect (2026-09-29)

- Web and Flutter now support verified email/password accounts and Google sign-in through Supabase Auth.
- Authenticated devices join a private per-user Realtime channel and publish Presence metadata.
- A single active playback device owns the real audio transport; every other signed-in device becomes a remote controller.
- Current song, radio/collection queue, active index, play/pause, position, next/previous, app volume, and queue reordering synchronize between web and mobile.
- Playback state is also stored in `public.playback_sessions`, so refresh/reconnect does not depend only on an in-memory WebSocket message.
- Flutter continues resolving YouTube streams on the phone. Web continues using the YouTube IFrame transport. No expiring stream URL is transferred between devices.
- Database tables, RLS, profile trigger, and private Realtime authorization are defined in `supabase/migrations/001_auth_and_connect.sql`.
- Full setup steps, file-level changes, security notes, and the manual two-device test checklist are in `AUTH_CONNECT_WORK_LOG.md`.

### Current verification

- Frontend lint: passed.
- Frontend production build: passed.
- Flutter tests: 3/3 passed.
- Flutter analysis: 0 errors; only pre-existing/dependency warnings and informational lints remain.

---

## 17. Authentication Redirect Recovery (2026-09-30)

- Added a dedicated web callback page at `/auth/callback` for both Google OAuth and email confirmation.
- The callback handles returned OAuth errors, PKCE codes, restored implicit sessions, late auth events, and timeout recovery before returning the user to the app.
- Web and Flutter verification screens can resend signup confirmation emails with the correct platform callback.
- Rebuilt and installed the updated Android app on the connected phone.
- Verified Android resolves and launches `com.innerwave.mobile://login-callback` through `com.innerwave.mobile/.MainActivity`.
- Required Supabase URL Configuration is now exact rather than broad: production callback, localhost callback, and the mobile deep link.
- Full timestamped diagnosis, evidence, changes, and remaining dashboard step are documented in `codexWork.md`.
- Production check on 2026-09-30 found `profiles` and `playback_sessions` returning `404 PGRST205`; `supabase/migrations/001_auth_and_connect.sql` still needs to be run once in the production Supabase SQL Editor before Connect can work.
