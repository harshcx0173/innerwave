# InnerWave

Detailed implementation status, API mapping, setup notes and the mobile roadmap are available in [PROJECT_STATUS.md](PROJECT_STATUS.md).

InnerWave is a local-first music web app with a Next.js interface and a FastAPI backend. Catalog, home shelves, search, browse data and autoplay queues come from the local `tombulled/innertube` source in `../innertube-main`.

## What is implemented

- Dynamic home shelves parsed from the live `FEmusic_home` response
- Songs, artists, albums and playlist search
- Album/playlist/artist browsing
- Context-aware playlist queues plus 50-track radio/autoplay fallback and queue reordering
- Persistent bottom player with seeking, volume and next/previous controls
- Refresh-safe current track, queue, volume and playback-position restoration
- Working browser fullscreen now-playing view and buffered/preview seekbar
- Dynamic artwork-based ambient color theme
- Last-50-play browser history and history-based recommendation shelves
- YouTube Music-style mood chips and finite lazy-loaded discovery shelves
- Album and playlist detail views with Play all, Shuffle and card-level play buttons
- Responsive desktop, tablet and mobile layouts
- InnerTube audio resolution with a maintained `yt-dlp` fallback when Google's old private client versions reject playback

## Project layout

```text
InnerTube/
├── innertube-main/       # existing local library source
└── music-app/
    ├── .venv/
    ├── backend/
    │   └── app/
    ├── frontend/
    └── start-dev.ps1
```

## Run

The environment and packages are already installed. From PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& 'D:\Learn\InnerTube\music-app\start-dev.ps1'
```

Then open `http://localhost:3000`. API documentation is at `http://localhost:8000/docs`.

For visible logs, run these in separate terminals instead:

```powershell
cd D:\Learn\InnerTube\music-app\backend
..\.venv\Scripts\python.exe -m uvicorn app.main:app --reload --port 8000
```

```powershell
cd D:\Learn\InnerTube\music-app\frontend
npm run dev
```

## Notes

InnerTube is a private, unsupported Google API. Response shapes and playback requirements can change without notice. This project is intended for personal development and learning; review YouTube's terms and content licensing requirements before distributing or monetizing it.
