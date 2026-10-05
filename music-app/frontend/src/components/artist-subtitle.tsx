"use client";

import React from "react";
import type { MediaItem } from "@/lib/types";
import { usePlayer } from "@/context/player-context";

export type ArtistSubtitleProps = {
  item?: MediaItem | null;
  subtitle?: string | null;
  artists?: string[] | null;
  className?: string;
  onArtistClick?: (artistName: string) => void;
  clickable?: boolean;
};

const TYPE_MARKERS = new Set([
  "song",
  "video",
  "album",
  "single",
  "ep",
  "playlist",
  "artist",
  "track",
]);

/**
 * Splits an artist string (e.g. "Ajay-Atul & Shreya Ghoshal" or "Arijit Singh, Pritam & Jasleen Royal")
 * into artist tokens and separator tokens.
 */
function tokenizeArtists(text: string): { text: string; isArtist: boolean }[] {
  if (!text) return [];
  // Split on commas, ampersands, and English conjunctions / feature tags while keeping delimiters
  const rawParts = text.split(/(\s*(?:,|&|\band\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b)\s*)/i);
  return rawParts
    .filter((part) => part.length > 0)
    .map((part, index) => ({
      text: part,
      isArtist: index % 2 === 0 && part.trim().length > 0,
    }));
}

export function ArtistSubtitle({
  item,
  subtitle,
  artists,
  className = "",
  onArtistClick,
  clickable = true,
}: ArtistSubtitleProps) {
  const player = usePlayer();

  const handleArtistClick = (artistName: string, e: React.MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
    if (onArtistClick) {
      onArtistClick(artistName);
    } else {
      player.openArtistView(artistName);
    }
  };

  const rawSubtitle = (item?.subtitle || subtitle || "").trim();
  const rawArtists = (item?.artists || artists || []).filter(Boolean);

  // If item is purely a playlist without videoId, display as regular text
  const isPlaylist = item?.type === "playlist" && !item?.videoId;
  if (isPlaylist || !clickable) {
    return (
      <small className={`truncate text-white/50 block ${className}`}>
        {rawSubtitle || item?.type || "Playlist"}
      </small>
    );
  }

  // If no subtitle at all, but artists array is present
  if (!rawSubtitle && rawArtists.length > 0) {
    return (
      <small className={`truncate text-white/50 block ${className}`}>
        {rawArtists.map((artist, idx) => (
          <React.Fragment key={`${artist}-${idx}`}>
            {idx > 0 && <span className="text-white/40"> & </span>}
            <span
              role="button"
              tabIndex={0}
              onClick={(e) => handleArtistClick(artist, e)}
              className="cursor-pointer hover:underline hover:text-cyan-400 text-white/70 transition"
              title={`View ${artist}`}
            >
              {artist}
            </span>
          </React.Fragment>
        ))}
      </small>
    );
  }

  if (!rawSubtitle) {
    return (
      <small className={`truncate text-white/50 block ${className}`}>
        {item?.type || ""}
      </small>
    );
  }

  // Parse subtitle segments separated by bullet (•) or middle dot (·)
  // Example: "Song • Ajay-Atul & Shreya Ghoshal · 635M plays"
  const segments = rawSubtitle
    .split(/\s+[·•]\s+/)
    .map((s) => s.trim())
    .filter(Boolean);

  let prefix: string | null = null;
  let artistSegment = "";
  let suffixSegments: string[] = [];

  if (segments.length === 0) {
    return <small className={`truncate text-white/50 block ${className}`}>{rawSubtitle}</small>;
  }

  // Check if first segment is a type marker (e.g. "Song", "Album")
  if (TYPE_MARKERS.has(segments[0].toLowerCase())) {
    prefix = segments[0];
    if (segments.length > 1) {
      artistSegment = segments[1];
      suffixSegments = segments.slice(2);
    }
  } else {
    // No type marker: first segment is the artist(s)
    artistSegment = segments[0];
    suffixSegments = segments.slice(1);
  }

  // If we couldn't isolate an artist segment, fallback to plain text
  if (!artistSegment && rawArtists.length > 0) {
    artistSegment = rawArtists.join(", ");
  }

  const artistTokens = tokenizeArtists(artistSegment);
  const suffixText = suffixSegments.length > 0 ? suffixSegments.join(" · ") : null;

  return (
    <small className={`truncate text-white/50 block ${className}`}>
      {prefix && (
        <span className="text-white/40">
          {prefix}
          {" • "}
        </span>
      )}

      {artistTokens.map((token, idx) => {
        if (!token.isArtist) {
          return (
            <span key={idx} className="text-white/40">
              {token.text}
            </span>
          );
        }

        const name = token.text.trim();
        return (
          <span
            key={idx}
            role="button"
            tabIndex={0}
            onClick={(e) => handleArtistClick(name, e)}
            className="cursor-pointer hover:underline hover:text-cyan-400 text-white/70 transition"
            title={`View ${name}`}
          >
            {name}
          </span>
        );
      })}

      {suffixText && (
        <span className="text-white/40">
          {" · "}
          {suffixText}
        </span>
      )}
    </small>
  );
}
