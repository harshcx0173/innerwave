from __future__ import annotations

import threading
import time
import json
from typing import Any, Callable
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from innertube import InnerTube
import yt_dlp


class MusicService:
    def __init__(self) -> None:
        self.music = InnerTube("WEB_REMIX")
        self.player_clients = [InnerTube("IOS"), InnerTube("ANDROID_MUSIC"), self.music]
        self._cache: dict[str, tuple[float, Any]] = {}
        self._cache_lock = threading.Lock()

    def cached(self, key: str, ttl: int, loader: Callable[[], Any]) -> Any:
        now = time.time()
        with self._cache_lock:
            cached = self._cache.get(key)
            if cached and cached[0] > now:
                return cached[1]
        value = loader()
        with self._cache_lock:
            self._cache[key] = (now + ttl, value)
        return value

    def home(self) -> dict[str, Any]:
        return self.cached("home", 300, lambda: self.music.browse("FEmusic_home"))

    def search(self, query: str) -> dict[str, Any]:
        return self.cached(f"search:{query.lower()}", 180, lambda: self.music.search(query))

    def browse(self, browse_id: str, params: str | None = None) -> dict[str, Any]:
        return self.cached(
            f"browse:{browse_id}:{params or ''}",
            300,
            lambda: self.music.browse(browse_id, params=params),
        )

    def next(
        self,
        video_id: str | None,
        playlist_id: str | None = None,
        *,
        params: str | None = None,
        index: int | None = None,
        continuation: str | None = None,
    ) -> dict[str, Any]:
        # A radio playlist id asks Music for the full 50-track autoplay queue.
        resolved_playlist = playlist_id or (f"RDAMVM{video_id}" if video_id and not continuation else None)
        return self.music.next(
            video_id=video_id,
            playlist_id=resolved_playlist,
            params=params,
            index=index,
            continuation=continuation,
        )

    def watch_tabs(self, video_id: str) -> dict[str, Any]:
        return self.cached(
            f"watch-tabs:{video_id}",
            300,
            lambda: self.next(video_id, f"RDAMVM{video_id}"),
        )

    def suggestions(self, query: str) -> dict[str, Any]:
        return self.cached(
            f"suggest:{query.lower()}",
            120,
            lambda: self.music.music_get_search_suggestions(query),
        )

    def lyric_candidates(self, title: str, artist: str = "") -> list[dict[str, Any]]:
        key = f"lrclib:{title.lower()}:{artist.lower()}"

        def load() -> list[dict[str, Any]]:
            query = {"track_name": title}
            if artist:
                query["artist_name"] = artist
            request = Request(
                f"https://lrclib.net/api/search?{urlencode(query)}",
                headers={"User-Agent": "InnerWave/0.1 (local music client)"},
            )
            with urlopen(request, timeout=10) as response:
                payload = json.loads(response.read().decode("utf-8"))
            return payload if isinstance(payload, list) else []

        return self.cached(key, 86400, load)

    def audio(self, video_id: str) -> dict[str, Any]:
        errors: list[str] = []
        for client in self.player_clients:
            try:
                data = client.player(video_id)
                formats = data.get("streamingData", {}).get("adaptiveFormats", [])
                audio = [
                    item for item in formats
                    if item.get("url") and str(item.get("mimeType", "")).startswith("audio/")
                ]
                if audio:
                    preferred = [item for item in audio if "audio/mp4" in str(item.get("mimeType", ""))]
                    selected = max(preferred or audio, key=lambda item: int(item.get("bitrate", 0)))
                    details = data.get("videoDetails", {})
                    return {
                        "url": selected["url"],
                        "mimeType": selected.get("mimeType"),
                        "bitrate": selected.get("bitrate"),
                        "title": details.get("title"),
                        "author": details.get("author"),
                        "lengthSeconds": details.get("lengthSeconds"),
                        "source": "innertube",
                    }
                errors.append(data.get("playabilityStatus", {}).get("reason", "No direct audio format"))
            except Exception as exc:  # third-party private API failures vary
                errors.append(str(exc))

        try:
            options = {
                "quiet": True,
                "no_warnings": True,
                "skip_download": True,
                "format": "bestaudio/best",
                "noplaylist": True,
            }
            with yt_dlp.YoutubeDL(options) as downloader:
                info = downloader.extract_info(
                    f"https://www.youtube.com/watch?v={video_id}", download=False
                )
            if info and info.get("url"):
                return {
                    "url": info["url"],
                    "mimeType": info.get("ext"),
                    "bitrate": info.get("abr") or info.get("tbr"),
                    "title": info.get("title"),
                    "author": info.get("artist") or info.get("uploader"),
                    "lengthSeconds": info.get("duration"),
                    "source": "yt-dlp-fallback",
                }
        except Exception as exc:
            errors.append(str(exc))
        raise RuntimeError("; ".join(errors) or "No playable audio stream was returned")


service = MusicService()
