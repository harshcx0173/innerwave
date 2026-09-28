# InnerWave

InnerWave is a YouTube Music-inspired project with three main parts:

- `music-app/frontend`: Next.js web application
- `music-app/backend`: FastAPI service backed by the local InnerTube Python library
- `music-app/mobile`: Flutter application for Android and iOS
- `innertube-main`: local InnerTube library source used by the backend

See [`music-app/README.md`](music-app/README.md) for local setup and [`music-app/PROJECT_STATUS.md`](music-app/PROJECT_STATUS.md) for the architecture, API map, completed features and roadmap. The home/mobile development log is in [`music-app/AntigravityWork.md`](music-app/AntigravityWork.md).

## Local web development

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& .\music-app\start-dev.ps1
```

- Web: `http://localhost:3000`
- API docs: `http://localhost:8000/docs`

## Flutter development

```powershell
cd .\music-app\mobile
flutter pub get
flutter run
```

The mobile backend URL is configured in `music-app/mobile/lib/core/api/music_api.dart`. Use a current HTTPS deployment URL for physical-device testing.
