from __future__ import annotations

import hashlib
import re
from typing import Any, Iterable


def text(value: Any) -> str:
    if not isinstance(value, dict):
        return ""
    if isinstance(value.get("simpleText"), str):
        return value["simpleText"].strip()
    runs = value.get("runs")
    if isinstance(runs, list):
        return "".join(str(run.get("text", "")) for run in runs if isinstance(run, dict)).strip()
    return ""


def _walk(value: Any) -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield key, child
            yield from _walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from _walk(child)


def _best_thumbnail(value: Any) -> str | None:
    candidates: list[dict[str, Any]] = []
    if isinstance(value, dict):
        direct_containers = [
            value.get("thumbnail"),
            value.get("thumbnailRenderer"),
            value.get("musicThumbnailRenderer"),
            value.get("thumbnails"),
        ]
        for container in direct_containers:
            if isinstance(container, dict):
                for k, child in _walk(container):
                    if k == "thumbnails" and isinstance(child, list):
                        candidates.extend(item for item in child if isinstance(item, dict) and item.get("url"))
            elif isinstance(container, list):
                candidates.extend(item for item in container if isinstance(item, dict) and item.get("url"))

    if not candidates:
        for key, child in _walk(value):
            if key == "thumbnails" and isinstance(child, list):
                candidates.extend(item for item in child if isinstance(item, dict) and item.get("url"))

    if not candidates:
        return None

    def thumb_size(item: dict[str, Any]) -> int:
        try:
            return int(item.get("width", 0)) * int(item.get("height", 0))
        except (ValueError, TypeError):
            return 0

    best = max(candidates, key=thumb_size)
    if thumb_size(best) == 0:
        best = candidates[-1]

    url = str(best.get("url", "")).strip()
    if not url:
        return None

    if url.startswith("//"):
        url = f"https:{url}"

    # YouTube Music commonly advertises low-res renditions (e.g. =w120-h120)
    # Upgrade standard Google image service URLs to high quality.
    if "googleusercontent.com" in url or "ggpht.com" in url:
        url = re.sub(r"=w\d+-h\d+", "=w1200-h1200-l90-rj", url)
        url = re.sub(r"=s\d+(?=$|[-?])", "=s1200", url)
    return url


def _first_navigation(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        if "watchEndpoint" in value or "browseEndpoint" in value or "watchPlaylistEndpoint" in value:
            return value
        for key in ("navigationEndpoint", "onTap", "endpoint"):
            child = value.get(key)
            if isinstance(child, dict):
                found = _first_navigation(child)
                if found:
                    return found
        for child in value.values():
            found = _first_navigation(child)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = _first_navigation(child)
            if found:
                return found
    return {}


def _endpoint_data(endpoint: dict[str, Any]) -> dict[str, Any]:
    watch = endpoint.get("watchEndpoint", {})
    browse = endpoint.get("browseEndpoint", {})
    playlist = endpoint.get("watchPlaylistEndpoint", {})
    config = browse.get("browseEndpointContextSupportedConfigs", {}).get("browseEndpointContextMusicConfig", {})
    return {
        "videoId": watch.get("videoId"),
        "playlistId": watch.get("playlistId") or playlist.get("playlistId"),
        "browseId": browse.get("browseId"),
        "browseParams": browse.get("params"),
        "pageType": config.get("pageType"),
        "watchParams": watch.get("params"),
        "index": watch.get("index"),
    }


def _type_for(meta: dict[str, Any], renderer_name: str) -> str:
    page_type = str(meta.get("pageType") or "")
    if "ARTIST" in page_type or "USER_CHANNEL" in page_type:
        return "artist"
    if "ALBUM" in page_type:
        return "album"
    if "PLAYLIST" in page_type:
        return "playlist"
    if meta.get("videoId"):
        return "song"
    if renderer_name == "playlistRenderer":
        return "playlist"
    if renderer_name == "channelRenderer":
        return "artist"
    return "unknown"


def parse_item(wrapper: Any) -> dict[str, Any] | None:
    if not isinstance(wrapper, dict):
        return None
    renderer_name = ""
    renderer: dict[str, Any] = wrapper
    for key, child in wrapper.items():
        if key.endswith("Renderer") and isinstance(child, dict):
            renderer_name, renderer = key, child
            break

    title_value: Any = renderer.get("title") or renderer.get("headline")
    subtitle_values: list[str] = []
    duration = text(renderer.get("lengthText", {}))

    flex_columns = renderer.get("flexColumns", [])
    if isinstance(flex_columns, list):
        column_texts: list[str] = []
        for column in flex_columns:
            if not isinstance(column, dict):
                continue
            inner = column.get("musicResponsiveListItemFlexColumnRenderer", {})
            value = text(inner.get("text", {}))
            if value:
                column_texts.append(value)
            if title_value is None and inner.get("text"):
                title_value = inner["text"]
        if column_texts:
            subtitle_values.extend(column_texts[1:])

    fixed_columns = renderer.get("fixedColumns", [])
    if isinstance(fixed_columns, list) and not duration:
        for column in fixed_columns:
            if isinstance(column, dict):
                value = text(column.get("musicResponsiveListItemFixedColumnRenderer", {}).get("text", {}))
                if value:
                    duration = value

    subtitle = text(renderer.get("subtitle", {})) or text(renderer.get("longBylineText", {}))
    if not subtitle and subtitle_values:
        subtitle = " · ".join(subtitle_values)

    title_string = text(title_value or {})
    if not title_string:
        return None

    endpoint = _first_navigation(renderer)
    meta = _endpoint_data(endpoint)
    meta["videoId"] = renderer.get("videoId") or meta.get("videoId")
    meta["playlistId"] = renderer.get("playlistId") or meta.get("playlistId")
    item_type = _type_for(meta, renderer_name)
    identity = meta.get("videoId") or meta.get("browseId") or meta.get("playlistId")
    if not identity:
        identity = hashlib.sha1(f"{renderer_name}:{title_string}:{subtitle}".encode()).hexdigest()[:16]

    artists: list[str] = []
    if subtitle:
        parts = [part.strip() for part in re.split(r"\s+[·•]\s+", subtitle) if part.strip()]
        if parts and parts[0].lower() in {"song", "video", "album", "single", "ep", "playlist", "artist"}:
            parts = parts[1:]
        primary = parts[0] if parts else subtitle
        artists = [part.strip() for part in primary.split(",") if part.strip()]

    return {
        "id": identity,
        "videoId": meta.get("videoId"),
        "browseId": meta.get("browseId"),
        "browseParams": meta.get("browseParams"),
        "playlistId": meta.get("playlistId"),
        "title": title_string,
        "subtitle": subtitle,
        "artists": artists,
        "thumbnail": _best_thumbnail(renderer) or (f"https://i.ytimg.com/vi/{meta['videoId']}/hqdefault.jpg" if meta.get("videoId") else None),
        "type": item_type,
        "duration": duration or None,
        "watchParams": meta.get("watchParams"),
        "index": meta.get("index"),
    }


def _shelf_title(renderer: dict[str, Any]) -> str:
    header = renderer.get("header", {})
    for _, value in _walk(header):
        candidate = text(value)
        if candidate:
            return candidate
    return text(renderer.get("title", {})) or "More for you"


def _items(renderer: dict[str, Any]) -> list[dict[str, Any]]:
    values = renderer.get("contents") or renderer.get("items") or []
    if not isinstance(values, list):
        return []
    parsed: list[dict[str, Any]] = []
    seen: set[str] = set()
    for value in values:
        item = parse_item(value)
        if item and item["id"] not in seen:
            parsed.append(item)
            seen.add(item["id"])
    return parsed


def _layout(items: list[dict[str, Any]], renderer_name: str) -> str:
    if renderer_name in {"musicShelfRenderer", "playlistPanelRenderer"}:
        return "list"
    if items and sum(item["type"] == "song" for item in items) > len(items) / 2:
        return "songs"
    return "carousel"


SHELF_RENDERERS = {
    "musicCarouselShelfRenderer",
    "musicCardShelfRenderer",
    "musicShelfRenderer",
    "playlistPanelRenderer",
    "gridRenderer",
}


def parse_shelves(data: Any) -> list[dict[str, Any]]:
    shelves: list[dict[str, Any]] = []
    seen: set[str] = set()
    included_items: set[str] = set()

    def visit(value: Any) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in SHELF_RENDERERS and isinstance(child, dict):
                    items = _items(child)
                    if items:
                        title_value = "Up next" if key == "playlistPanelRenderer" else _shelf_title(child)
                        signature = title_value + ":" + ",".join(item["id"] for item in items[:4])
                        if signature not in seen:
                            shelves.append({
                                "id": hashlib.sha1(signature.encode()).hexdigest()[:12],
                                "title": title_value,
                                "layout": _layout(items, key),
                                "items": items,
                            })
                            included_items.update(item["id"] for item in items)
                            seen.add(signature)
                    continue
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(data)

    # Search responses often place individual result renderers directly inside
    # itemSectionRenderer blocks instead of wrapping them in a music shelf.
    loose_items: list[dict[str, Any]] = []
    loose_seen: set[str] = set()
    item_renderers = {
        "musicResponsiveListItemRenderer",
        "musicTwoRowItemRenderer",
        "playlistPanelVideoRenderer",
        "playlistRenderer",
        "videoRenderer",
        "channelRenderer",
    }
    for key, child in _walk(data):
        if key in item_renderers and isinstance(child, dict):
            item = parse_item({key: child})
            if item and item["id"] not in included_items and item["id"] not in loose_seen:
                loose_items.append(item)
                loose_seen.add(item["id"])
    if loose_items:
        signature = "Results:" + ",".join(item["id"] for item in loose_items[:4])
        shelves.append({
            "id": hashlib.sha1(signature.encode()).hexdigest()[:12],
            "title": "Results",
            "layout": "list" if len(loose_items) > 12 else _layout(loose_items, ""),
            "items": loose_items,
        })
    return shelves


def continuation_token(data: Any) -> str | None:
    for key, child in _walk(data):
        if key == "continuationCommand" and isinstance(child, dict) and child.get("token"):
            return str(child["token"])
        if key in {"nextRadioContinuationData", "nextContinuationData"} and isinstance(child, dict) and child.get("continuation"):
            return str(child["continuation"])
    return None


def parse_feed(data: dict[str, Any]) -> dict[str, Any]:
    return {"shelves": parse_shelves(data), "continuation": continuation_token(data)}


def parse_watch_tabs(data: Any) -> dict[str, str]:
    tabs: dict[str, str] = {}
    for key, child in _walk(data):
        if key != "tabRenderer" or not isinstance(child, dict):
            continue
        raw_title = child.get("title", {})
        title_value = (raw_title if isinstance(raw_title, str) else text(raw_title)).lower()
        browse_id = child.get("endpoint", {}).get("browseEndpoint", {}).get("browseId")
        if title_value and browse_id:
            tabs[title_value] = str(browse_id)
    return tabs


def parse_lyrics(data: Any) -> dict[str, str | None]:
    for key, child in _walk(data):
        if key == "musicDescriptionShelfRenderer" and isinstance(child, dict):
            lyrics = text(child.get("description", {}))
            if lyrics:
                return {"lyrics": lyrics, "source": text(child.get("footer", {})) or None}
    return {"lyrics": "", "source": None}


def parse_suggestions(data: dict[str, Any]) -> list[str]:
    suggestions: list[str] = []
    for key, child in _walk(data):
        if key == "searchSuggestionRenderer" and isinstance(child, dict):
            value = text(child.get("suggestion", {}))
            if value and value not in suggestions:
                suggestions.append(value)
    return suggestions[:10]


def parse_chips(data: Any) -> list[str]:
    chips: list[str] = []
    for key, child in _walk(data):
        if key == "chipCloudChipRenderer" and isinstance(child, dict):
            value = text(child.get("text", {}))
            if value and value not in chips:
                chips.append(value)
    return chips[:12]
