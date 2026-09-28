from __future__ import annotations

import re
import unicodedata
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse

from .parser import parse_chips, parse_feed, parse_lyrics, parse_suggestions, parse_watch_tabs
from .service import service


app = FastAPI(title="InnerWave API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def upstream_error(exc: Exception) -> HTTPException:
    return HTTPException(status_code=502, detail=f"InnerTube upstream error: {exc}")


def _recommendation_seed(video_id: str, title: str, artist: str) -> tuple[str, str]:
    if title.strip():
        return title.strip(), artist.strip()
    parsed = parse_feed(service.search(video_id))
    candidates = [
        item
        for shelf in parsed["shelves"]
        for item in shelf["items"]
        if item.get("videoId")
    ]
    if not candidates:
        return video_id, artist.strip()
    seed = next((item for item in candidates if item.get("videoId") == video_id), candidates[0])
    artists = seed.get("artists") or []
    resolved_artist = ", ".join(str(value) for value in artists if value) if isinstance(artists, list) else ""
    if not resolved_artist:
        resolved_artist = str(seed.get("subtitle") or "").split(" · ")[0]
    return str(seed.get("title") or video_id), artist.strip() or resolved_artist


def _search_recommendations(video_id: str, title: str, artist: str, *, limit: int = 50) -> list[dict]:
    """Build a stable song radio from Music search when watch-next is blocked.

    YouTube Music's watch-next call is regularly throttled on cloud-host IPs
    (including Render), while its search endpoint remains available.  Supplying
    the current track metadata lets hosted clients avoid the failing call and
    still receive a queue seeded by the song rather than by the visible shelf.
    """
    title, artist = _recommendation_seed(video_id, title, artist)
    queries = [
        " ".join(part for part in (title, artist, "songs radio") if part),
        " ".join(part for part in (artist, "popular songs") if part),
        f"songs like {title}",
    ]
    items: list[dict] = []
    seen: set[str] = {video_id}
    for query in dict.fromkeys(queries):
        parsed = parse_feed(service.search(query))
        for shelf in parsed["shelves"]:
            for item in shelf["items"]:
                item_id = str(item.get("videoId") or item.get("id") or "")
                if not item.get("videoId") or not item_id or item_id in seen:
                    continue
                seen.add(item_id)
                items.append(item)
                if len(items) >= limit:
                    return items
    return items


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok", "client": "WEB_REMIX"}


@app.get("/api/home")
def home() -> dict:
    try:
        result = parse_feed(service.home())
        quick_picks = [shelf for shelf in result["shelves"] if "quick" in shelf["title"].lower()]
        if not quick_picks:
            fallback = parse_feed(service.search("popular songs India"))
            songs: list[dict] = []
            seen_song_ids: set[str] = set()
            for shelf in fallback["shelves"]:
                for item in shelf["items"]:
                    if item.get("videoId") and item["id"] not in seen_song_ids:
                        songs.append(item)
                        seen_song_ids.add(item["id"])
            if songs:
                quick_picks = [{"id": "quick-picks", "title": "Quick picks", "layout": "songs", "items": songs[:20]}]
        result["shelves"] = quick_picks or result["shelves"][:1]
        result["source"] = "innertube"
        result["chips"] = parse_chips(service.home())
        result["hasMore"] = True
        result["nextPage"] = 1
        return result
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/search")
def search(q: str = Query(min_length=1, max_length=120)) -> dict:
    try:
        result = parse_feed(service.search(q.strip()))
        result["query"] = q.strip()
        return result
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/search/suggestions")
def suggestions(q: str = Query(min_length=1, max_length=120)) -> dict[str, list[str]]:
    try:
        return {"suggestions": parse_suggestions(service.suggestions(q.strip()))}
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/browse")
def browse(
    id: str = Query(min_length=2, max_length=180),
    params: str | None = Query(default=None, max_length=500),
) -> dict:
    try:
        result = parse_feed(service.browse(id, params))
        result["browseId"] = id
        return result
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/next")
def next_tracks(
    videoId: str | None = Query(default=None, min_length=5, max_length=32),
    playlistId: str | None = Query(default=None, max_length=100),
    params: str | None = Query(default=None, max_length=500),
    index: int | None = Query(default=None, ge=0, le=10000),
    continuation: str | None = Query(default=None, max_length=2000),
    title: str = Query(default="", max_length=200),
    artist: str = Query(default="", max_length=300),
) -> dict:
    if not videoId and not continuation:
        raise HTTPException(status_code=422, detail="videoId or continuation is required")
    try:
        if videoId and not continuation:
            queue = _search_recommendations(videoId, title, artist)
            return {
                "items": queue,
                "shelves": [{"id": "song-radio", "title": "Up next", "layout": "songs", "items": queue}],
                "continuation": None,
                "source": "search-radio",
            }
        result = parse_feed(service.next(videoId, playlistId, params=params, index=index, continuation=continuation))
        queue = next((shelf["items"] for shelf in result["shelves"] if shelf["items"]), [])
        return {"items": queue, "shelves": result["shelves"], "continuation": result["continuation"]}
    except Exception as exc:
        raise upstream_error(exc) from exc


def _watch_tab(video_id: str, name: str) -> str:
    tabs = parse_watch_tabs(service.watch_tabs(video_id))
    browse_id = tabs.get(name.lower())
    if not browse_id:
        raise HTTPException(status_code=404, detail=f"{name} is not available for this track")
    return browse_id


def _normalise(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).casefold()
    return " ".join(re.findall(r"[\w]+", value, flags=re.UNICODE))


def _parse_lrc(value: str) -> list[dict[str, float | str]]:
    lines: list[dict[str, float | str]] = []
    offset = 0.0
    offset_match = re.search(r"\[offset:([+-]?\d+)\]", value, flags=re.IGNORECASE)
    if offset_match:
        offset = int(offset_match.group(1)) / 1000
    for raw_line in value.splitlines():
        timestamps = re.findall(r"\[(\d{1,3}):(\d{2}(?:\.\d{1,3})?)\]", raw_line)
        lyric = re.sub(r"\[[^\]]+\]", "", raw_line).strip()
        if not timestamps or not lyric:
            continue
        for minutes, seconds in timestamps:
            lines.append({"time": max(0.0, int(minutes) * 60 + float(seconds) + offset), "text": lyric})
    return sorted(lines, key=lambda line: float(line["time"]))


def _best_synced_lyrics(title: str, artist: str, duration: float | None, preferred_text: str = "") -> dict | None:
    candidates = service.lyric_candidates(title, artist)
    title_key = _normalise(title)
    artist_tokens = set(_normalise(artist).split())
    ranked: list[tuple[float, dict]] = []
    for candidate in candidates:
        synced = candidate.get("syncedLyrics")
        if not isinstance(synced, str) or not synced.strip():
            continue
        candidate_title = _normalise(str(candidate.get("trackName") or candidate.get("name") or ""))
        score = 100.0 if candidate_title == title_key else (50.0 if title_key in candidate_title or candidate_title in title_key else 0.0)
        candidate_artists = set(_normalise(str(candidate.get("artistName") or "")).split())
        if artist_tokens and candidate_artists:
            score += 30.0 * len(artist_tokens & candidate_artists) / len(artist_tokens)
        candidate_duration = float(candidate.get("duration") or 0)
        if duration and candidate_duration:
            difference = abs(candidate_duration - duration)
            if difference > max(25.0, duration * 0.12):
                continue
            score += max(0.0, 45.0 - difference * 2.5)
        if preferred_text:
            preferred_devanagari = bool(re.search(r"[\u0900-\u097f]", preferred_text))
            candidate_devanagari = bool(re.search(r"[\u0900-\u097f]", synced))
            score += 15.0 if preferred_devanagari == candidate_devanagari else -15.0
        ranked.append((score, candidate))
    return max(ranked, key=lambda item: item[0])[1] if ranked else None


@app.get("/api/lyrics")
def lyrics(
    videoId: str = Query(min_length=5, max_length=32),
    title: str = Query(default="", max_length=200),
    artist: str = Query(default="", max_length=300),
    duration: float | None = Query(default=None, gt=0, le=7200),
) -> dict:
    result: dict = {"lyrics": "", "source": None}
    try:
        try:
            result = parse_lyrics(service.browse(_watch_tab(videoId, "lyrics")))
        except Exception:
            pass
        synced_match = None
        if title.strip():
            try:
                synced_match = _best_synced_lyrics(title.strip(), artist.strip(), duration, str(result.get("lyrics") or ""))
            except Exception:
                synced_match = None
        synced_value = str(synced_match.get("syncedLyrics") or "") if synced_match else ""
        timed_lines = _parse_lrc(synced_value)
        if synced_match and not result.get("lyrics"):
            result["lyrics"] = str(synced_match.get("plainLyrics") or "")
        if not result.get("lyrics") and not timed_lines:
            raise HTTPException(status_code=404, detail="Lyrics are not available for this track")
        return {
            **result,
            "lines": timed_lines,
            "synced": bool(timed_lines),
            "syncSource": "LRCLIB" if timed_lines else None,
            "matchedTrack": synced_match.get("trackName") if synced_match else None,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/related")
def related(
    videoId: str = Query(min_length=5, max_length=32),
    title: str = Query(default="", max_length=200),
    artist: str = Query(default="", max_length=300),
) -> dict:
    try:
        items = _search_recommendations(videoId, title, artist, limit=30)
        return {
            "shelves": [{"id": "related-songs", "title": "Related", "layout": "songs", "items": items}],
            "source": "search-radio",
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise upstream_error(exc) from exc


DISCOVERY_PAGES = [
    ("New releases", "new music releases India", "carousel", {"album", "song"}),
    ("Albums for you", "popular Hindi albums", "carousel", {"album"}),
    ("From the community", "Bollywood community playlists", "carousel", {"playlist"}),
    ("Featured playlists for you", "featured music playlists India", "carousel", {"playlist"}),
    ("Hindi Hits", "Hindi hits playlists", "carousel", {"playlist", "album"}),
    ("Trending community playlists", "trending community playlists India", "carousel", {"playlist"}),
    ("Covers and remixes", "popular covers and remixes", "songs", {"song"}),
    ("Trending songs for you", "trending songs India", "songs", {"song"}),
    ("Bollywood & Indian", "Bollywood Indian music", "carousel", {"playlist", "album", "song"}),
    ("Music videos for you", "popular Hindi music videos", "carousel", {"song"}),
    ("Long listens", "long music mixes India", "list", {"song"}),
    ("Live performances", "live music performances India", "carousel", {"song"}),
]


@app.get("/api/home/more")
def home_more(
    page: int = Query(default=1, ge=1, le=12),
    seed: str = Query(default="", max_length=80),
    continuation: str | None = Query(default=None, max_length=2000),
) -> dict:
    try:
        if continuation:
            result = parse_feed(service.music.browse(continuation=continuation))
        else:
            title, default_query, layout, preferred_types = DISCOVERY_PAGES[page - 1]
            query = f"{seed} music" if seed else default_query
            parsed = parse_feed(service.search(query))
            all_items: list[dict] = []
            seen_ids: set[str] = set()
            for shelf in parsed["shelves"]:
                for item in shelf["items"]:
                    if item["id"] not in seen_ids:
                        all_items.append(item)
                        seen_ids.add(item["id"])
            preferred = [item for item in all_items if item["type"] in preferred_types]
            remaining = [item for item in all_items if item["id"] not in {preferred_item["id"] for preferred_item in preferred}]
            items = [*preferred, *remaining][:24 if layout in {"songs", "list"} else 12]
            result = {
                "shelves": [{"id": f"discover-{page}", "title": title, "layout": layout, "items": items}] if items else [],
                "continuation": parsed.get("continuation"),
            }
        result["hasMore"] = bool(result.get("continuation")) or page < len(DISCOVERY_PAGES)
        result["nextPage"] = page + 1 if result["hasMore"] else None
        return result
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/recommendations")
def recommendations(artists: str = Query(default="", max_length=300)) -> dict:
    names = [name.strip() for name in artists.split(",") if name.strip()][:3]
    shelves: list[dict] = []
    try:
        for artist_index, name in enumerate(names):
            feed = parse_feed(service.search(f"{name} songs"))
            songs: list[dict] = []
            seen_song_ids: set[str] = set()
            for shelf in feed["shelves"]:
                for item in shelf["items"]:
                    if item.get("videoId") and item["id"] not in seen_song_ids:
                        songs.append(item)
                        seen_song_ids.add(item["id"])
            if songs:
                shelves.append({
                    "id": f"personal-{artist_index}-{name.lower().replace(' ', '-')}",
                    "title": f"Because you listened to {name}",
                    "layout": "songs",
                    "items": songs[:20],
                })
        return {"shelves": shelves}
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/player/{video_id}")
def player(video_id: str) -> dict:
    try:
        audio = service.cached(f"audio:{video_id}", 240, lambda: service.audio(video_id))
        return {
            "videoId": video_id,
            "title": audio.get("title"),
            "author": audio.get("author"),
            "lengthSeconds": audio.get("lengthSeconds"),
            "mimeType": audio.get("mimeType"),
            "bitrate": audio.get("bitrate"),
            "source": audio.get("source"),
            "streamUrl": f"/api/stream/{video_id}",
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise upstream_error(exc) from exc


@app.get("/api/stream/{video_id}")
def stream(video_id: str) -> RedirectResponse:
    try:
        audio = service.cached(f"audio:{video_id}", 240, lambda: service.audio(video_id))
        url = str(audio["url"])
        host = (urlparse(url).hostname or "").lower()
        if not (host.endswith("googlevideo.com") or host.endswith("youtube.com")):
            raise HTTPException(status_code=502, detail="Unexpected media host")
        return RedirectResponse(url=url, status_code=307, headers={"Cache-Control": "no-store"})
    except HTTPException:
        raise
    except Exception as exc:
        raise upstream_error(exc) from exc
