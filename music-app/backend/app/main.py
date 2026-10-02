from __future__ import annotations

import re
import json
import os
import unicodedata
from datetime import datetime, timedelta, timezone
from urllib.error import HTTPError, URLError
from urllib.request import Request as UrlRequest, urlopen
from urllib.parse import urlparse

from fastapi import FastAPI, Header, HTTPException, Query, Request
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

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://gbqmtmcjqdqgfkzuwqot.supabase.co").rstrip("/")
SUPABASE_PUBLISHABLE_KEY = os.getenv("SUPABASE_PUBLISHABLE_KEY", "sb_publishable__Vqh6AU8KimNPSNGeX_tFA_4ieBRkqS")
ADMIN_EMAIL = os.getenv("INNERWAVE_ADMIN_EMAIL", "harsh.b.mevada@gmail.com").strip().lower()


def _bearer_token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Authentication required")
    return authorization.split(" ", 1)[1].strip()


def _supabase_json(path: str, token: str, *, method: str = "GET", payload: object | None = None, headers: dict[str, str] | None = None) -> object:
    body = json.dumps(payload).encode("utf-8") if payload is not None else None
    request = UrlRequest(
        f"{SUPABASE_URL}{path}",
        data=body,
        method=method,
        headers={
            "apikey": SUPABASE_PUBLISHABLE_KEY,
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            **(headers or {}),
        },
    )
    try:
        with urlopen(request, timeout=12) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(status_code=exc.code, detail=f"Supabase request failed: {detail[:300]}") from exc
    except (URLError, TimeoutError) as exc:
        raise HTTPException(status_code=503, detail="Account service is temporarily unavailable") from exc


def _authenticated_user(authorization: str | None) -> tuple[str, dict]:
    token = _bearer_token(authorization)
    user = _supabase_json("/auth/v1/user", token)
    if not isinstance(user, dict) or not user.get("id"):
        raise HTTPException(status_code=401, detail="Invalid session")
    return token, user


def _client_ip(request: Request) -> str | None:
    forwarded = request.headers.get("x-forwarded-for", "")
    candidate = forwarded.split(",", 1)[0].strip() if forwarded else (request.client.host if request.client else "")
    return candidate or None


@app.post("/api/presence")
async def update_presence(request: Request, authorization: str | None = Header(default=None)) -> dict[str, bool]:
    token, user = _authenticated_user(authorization)
    payload = await request.json()
    if not isinstance(payload, dict):
        raise HTTPException(status_code=422, detail="Invalid presence payload")
    metadata = user.get("user_metadata") if isinstance(user.get("user_metadata"), dict) else {}
    permission = str(payload.get("locationPermission") or "unavailable")[:24]
    latitude = payload.get("latitude") if permission == "granted" else None
    longitude = payload.get("longitude") if permission == "granted" else None
    accuracy = payload.get("accuracyMeters") if permission == "granted" else None
    current_track = payload.get("currentTrack")
    device_id = str(payload.get("deviceId") or "")[:120]
    if not device_id:
        raise HTTPException(status_code=422, detail="deviceId is required")
    row = {
        "user_id": user["id"],
        "email": user.get("email"),
        "display_name": str(metadata.get("display_name") or metadata.get("full_name") or metadata.get("name") or str(user.get("email") or "InnerWave Listener").split("@")[0])[:80],
        "platform": str(payload.get("platform") or "Unknown")[:40],
        "device_id": device_id,
        "is_listening": bool(payload.get("isListening")),
        "current_track": current_track if isinstance(current_track, dict) else None,
        "location_permission": permission,
        "latitude": latitude if isinstance(latitude, (int, float)) and -90 <= latitude <= 90 else None,
        "longitude": longitude if isinstance(longitude, (int, float)) and -180 <= longitude <= 180 else None,
        "accuracy_meters": accuracy if isinstance(accuracy, (int, float)) and accuracy >= 0 else None,
        "ip_address": _client_ip(request),
        "last_seen": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    _supabase_json(
        "/rest/v1/user_presence?on_conflict=user_id,device_id",
        token,
        method="POST",
        payload=row,
        headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
    )
    return {"ok": True}


@app.get("/api/admin/overview")
def admin_overview(authorization: str | None = Header(default=None)) -> dict:
    token, user = _authenticated_user(authorization)
    if str(user.get("email") or "").lower() != ADMIN_EMAIL:
        raise HTTPException(status_code=403, detail="Admin access required")
    profiles = _supabase_json("/rest/v1/profiles?select=id,display_name,avatar_url,created_at&order=created_at.desc", token)
    presence = _supabase_json("/rest/v1/user_presence?select=*&order=last_seen.desc", token)
    profiles = profiles if isinstance(profiles, list) else []
    presence = presence if isinstance(presence, list) else []
    cutoff = datetime.now(timezone.utc) - timedelta(seconds=90)
    presence_by_user: dict[str, list[dict]] = {}
    for row in presence:
        if isinstance(row, dict) and row.get("user_id"):
            presence_by_user.setdefault(str(row["user_id"]), []).append(row)
    users = []
    active_users = 0
    active_listeners = 0
    for profile in profiles:
        rows = presence_by_user.get(str(profile.get("id")), [])
        active_rows = []
        for candidate in rows:
            try:
                seen = datetime.fromisoformat(str(candidate.get("last_seen") or "").replace("Z", "+00:00"))
                if seen >= cutoff:
                    active_rows.append(candidate)
            except ValueError:
                continue
        active = bool(active_rows)
        listening_rows = [candidate for candidate in active_rows if candidate.get("is_listening") is True]
        row = (listening_rows or active_rows or rows or [{}])[0]
        gps_rows = [candidate for candidate in active_rows or rows if candidate.get("location_permission") == "granted" and candidate.get("latitude") is not None and candidate.get("longitude") is not None]
        if gps_rows:
            location_row = gps_rows[0]
            row = {**row, "location_permission": "granted", "latitude": location_row.get("latitude"), "longitude": location_row.get("longitude"), "accuracy_meters": location_row.get("accuracy_meters"), "ip_address": location_row.get("ip_address")}
        listening = bool(listening_rows)
        active_users += int(active)
        active_listeners += int(listening)
        has_gps = row.get("location_permission") == "granted" and row.get("latitude") is not None and row.get("longitude") is not None
        users.append({
            **profile,
            **row,
            "active": active,
            "is_listening": listening,
            "location_source": "gps" if has_gps else ("ip" if row.get("ip_address") else "unavailable"),
            "ip_address": None if has_gps else row.get("ip_address"),
        })
    return {"totalUsers": len(profiles), "activeUsers": active_users, "activeListeners": active_listeners, "users": users, "generatedAt": datetime.now(timezone.utc).isoformat()}


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
    last_error: Exception | None = None
    for query in dict.fromkeys(queries):
        try:
            parsed = parse_feed(service.search(query))
        except Exception as exc:
            last_error = exc
            continue
        for shelf in parsed["shelves"]:
            for item in shelf["items"]:
                item_id = str(item.get("videoId") or item.get("id") or "")
                if not item.get("videoId") or not item_id or item_id in seen:
                    continue
                seen.add(item_id)
                items.append(item)
                if len(items) >= limit:
                    return items
    if not items and last_error:
        raise last_error
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

    radio_error: Exception | None = None
    try:
        result = parse_feed(service.next(videoId, playlistId, params=params, index=index, continuation=continuation))
        queue = next((shelf["items"] for shelf in result["shelves"] if shelf["items"]), [])
        if queue:
            return {
                "items": queue,
                "shelves": result["shelves"],
                "continuation": result["continuation"],
                "source": "youtube-radio",
            }
        radio_error = RuntimeError("YouTube Music returned an empty radio queue")
    except Exception as exc:
        radio_error = exc

    # Continuations cannot be reconstructed with search. Let the client keep
    # the queue it already has instead of silently replacing it with a new one.
    if continuation or not videoId:
        assert radio_error is not None
        raise upstream_error(radio_error) from radio_error

    # Cloud-hosted IPs (notably Render) can occasionally have watch-next
    # throttled. Search radio remains a resilient fallback, but it must not
    # replace the higher-quality YouTube Music radio when that is available.
    try:
        queue = _search_recommendations(videoId, title, artist)
        if not queue and radio_error is not None:
            raise radio_error
        return {
            "items": queue,
            "shelves": [{"id": "song-radio", "title": "Up next", "layout": "songs", "items": queue}],
            "continuation": None,
            "source": "search-radio-fallback",
        }
    except Exception as fallback_error:
        detail = fallback_error if radio_error is None else RuntimeError(
            f"radio failed ({radio_error}); search fallback failed ({fallback_error})"
        )
        raise upstream_error(detail) from fallback_error


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
