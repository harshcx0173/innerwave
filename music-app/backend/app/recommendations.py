from __future__ import annotations

import re
import unicodedata
from collections import Counter
from dataclasses import dataclass
from typing import Iterable


_GENERIC_WORDS = {
    "a", "an", "and", "audio", "by", "feat", "featuring", "film", "for",
    "from", "full", "music", "official", "of", "song", "the", "video",
}
_VARIANT_WORDS = {
    "acoustic", "cover", "karaoke", "live", "lyrics", "lyric", "reprise",
    "remix", "remastered", "slowed", "sped", "status", "version",
}
_PODCAST_WORDS = {
    "audiobook", "episode", "interview", "podcast", "pravachan", "speech",
}
_DEVOTIONAL_WORDS = {
    "aarti", "arti", "bhajan", "chalisa", "devotional", "katha", "mantra",
    "stotra", "stotram",
}
_LOW_QUALITY_PHRASES = {
    "best of", "full album", "greatest hits", "jukebox", "non stop", "nonstop",
    "shorts", "status video",
}


def normalise(value: str) -> str:
    value = unicodedata.normalize("NFKD", value).casefold()
    return " ".join(re.findall(r"[\w]+", value, flags=re.UNICODE))


def _words(value: str) -> set[str]:
    return {word for word in normalise(value).split() if len(word) > 1}


def _title_words(value: str) -> set[str]:
    # Bracketed text on Music results is normally release/variant metadata.
    value = re.sub(r"[\(\[\{].*?[\)\]\}]", " ", value)
    return {word for word in _words(value) if word not in _GENERIC_WORDS}


def _artist_words(item: dict) -> set[str]:
    artists = item.get("artists") or []
    if isinstance(artists, list):
        value = " ".join(str(artist) for artist in artists)
    else:
        value = str(artists)
    if not value:
        value = str(item.get("subtitle") or "").split(" · ")[0]
    return _words(value)


def _seconds(value: object) -> int | None:
    parts = str(value or "").strip().split(":")
    if not parts or not all(part.isdigit() for part in parts):
        return None
    total = 0
    for part in parts:
        total = total * 60 + int(part)
    return total


def _contains(words: set[str], vocabulary: set[str]) -> bool:
    return bool(words & vocabulary)


def _same_recording(seed_words: set[str], candidate_words: set[str]) -> bool:
    if not seed_words or not candidate_words:
        return False
    overlap = seed_words & candidate_words
    similarity = len(overlap) / len(seed_words | candidate_words)
    if seed_words == candidate_words or similarity >= 0.72:
        return True
    # Short titles such as "Vaaroon Forever" produce many lyric/reprise uploads.
    # Sharing the distinctive first word plus half of the seed is enough to treat
    # these as the same recording family.
    distinctive_overlap = any(len(word) >= 5 for word in overlap)
    return (
        len(seed_words) <= 3
        and distinctive_overlap
        and len(overlap) / len(seed_words) >= 0.5
    )


@dataclass(frozen=True)
class RankedItem:
    score: float
    original_index: int
    item: dict


def rank_queue(
    candidates: Iterable[dict],
    *,
    video_id: str = "",
    title: str = "",
    artist: str = "",
    limit: int = 50,
) -> list[dict]:
    """Return a music-only, diverse queue ordered around one seed track.

    This is a deterministic content-based ranker. It deliberately favours the
    upstream YouTube Music order while removing content-category mismatches,
    duplicate recordings and low-quality title variants.
    """
    seed_title_words = _title_words(title)
    seed_artist_words = _words(artist)
    seed_all_words = _words(f"{title} {artist}")
    seed_is_podcast = _contains(seed_all_words, _PODCAST_WORDS)
    seed_is_devotional = _contains(seed_all_words, _DEVOTIONAL_WORDS)
    ranked: list[RankedItem] = []
    seen_ids: set[str] = {video_id} if video_id else set()
    seen_recordings: set[tuple[str, str]] = set()
    seen_title_artists: list[tuple[set[str], set[str]]] = []

    for index, item in enumerate(candidates):
        item_id = str(item.get("videoId") or item.get("id") or "")
        if not item.get("videoId") or not item_id or item_id in seen_ids:
            continue
        seen_ids.add(item_id)

        item_type = normalise(str(item.get("type") or ""))
        title_value = str(item.get("title") or "")
        subtitle = str(item.get("subtitle") or "")
        all_words = _words(f"{title_value} {subtitle}")
        title_words = _title_words(title_value)
        artist_words = _artist_words(item)
        normalised_title = normalise(title_value)

        if item_type not in {"song", "video", "unknown", ""}:
            continue
        if not seed_is_podcast and _contains(all_words, _PODCAST_WORDS):
            continue
        if not seed_is_devotional and _contains(all_words, _DEVOTIONAL_WORDS):
            continue
        if title_value.lstrip().startswith("#") or re.search(r"\btop\s+\d+\s+songs\b", normalised_title) or any(
            phrase in normalised_title for phrase in _LOW_QUALITY_PHRASES
        ):
            continue
        duration = _seconds(item.get("duration"))
        if not seed_is_podcast and duration is not None and duration > 15 * 60:
            continue
        if _same_recording(seed_title_words, title_words):
            continue

        artist_key = " ".join(sorted(artist_words))
        title_key = " ".join(sorted(title_words))
        recording_key = (title_key, artist_key)
        if title_key and recording_key in seen_recordings:
            continue
        if any(
            (title_words <= previous_title or previous_title <= title_words)
            and (
                (
                    min(len(title_words), len(previous_title)) >= 2
                    and bool(artist_words & previous_artists)
                )
                or (
                    min(len(title_words), len(previous_title)) == 1
                    and any(len(word) >= 5 for word in title_words & previous_title)
                )
            )
            for previous_title, previous_artists in seen_title_artists
        ):
            continue
        seen_recordings.add(recording_key)
        seen_title_artists.append((title_words, artist_words))

        artist_overlap = len(seed_artist_words & artist_words)
        title_overlap = len(seed_title_words & title_words)
        score = max(0.0, 60.0 - index * 0.55)
        score += min(artist_overlap, 3) * 11.0
        score += min(title_overlap, 2) * 2.0
        if normalise(subtitle).startswith("song "):
            score += 4.0
        if duration is not None and 90 <= duration <= 480:
            score += 3.0
        variant_count = len(all_words & _VARIANT_WORDS)
        score -= variant_count * 12.0
        ranked.append(RankedItem(score, index, item))

    ranked.sort(key=lambda value: (-value.score, value.original_index))

    # Avoid a queue monopolised by one artist while retaining a few strong
    # same-artist choices. This produces the mix of familiarity and discovery
    # users expect from a song radio.
    artist_counts: Counter[str] = Counter()
    seed_artist_count = 0
    selected: list[dict] = []
    deferred: list[RankedItem] = []
    for candidate in ranked:
        candidate_artists = _artist_words(candidate.item)
        artist_key = " ".join(sorted(candidate_artists)) or "unknown"
        cap = 3 if artist_key != "unknown" else 8
        repeats_seed_artist = bool(seed_artist_words & candidate_artists)
        if artist_counts[artist_key] >= cap or (repeats_seed_artist and seed_artist_count >= 5):
            deferred.append(candidate)
            continue
        selected.append(candidate.item)
        artist_counts[artist_key] += 1
        seed_artist_count += int(repeats_seed_artist)
        if len(selected) >= limit:
            return selected

    # If the upstream supplied little variety, prefer a slightly repetitive
    # music queue over returning an unexpectedly short queue.
    for candidate in deferred:
        selected.append(candidate.item)
        if len(selected) >= limit:
            break
    return selected


def recommendation_queries(title: str, artist: str) -> list[str]:
    clean_artist = artist.split(",", 1)[0].strip()
    context_match = re.search(
        r'(?:from|film|movie)\s*["“”\']?([^\)\]\}]+)',
        title,
        re.IGNORECASE,
    )
    context = context_match.group(1).strip(" '\"“”") if context_match else ""
    values = [
        f"{clean_artist} radio songs" if clean_artist else "",
        f"{clean_artist} popular songs" if clean_artist else "",
        f"{context} songs" if context else "",
    ]
    return list(dict.fromkeys(value for value in values if value.strip()))
