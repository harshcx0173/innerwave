"use client";

/* eslint-disable react-hooks/set-state-in-effect */

import { useEffect, useMemo, useRef, useState, type UIEvent } from "react";
import { ArrowDown, ArrowUp, GripVertical, LoaderCircle, Play, X } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { musicApi } from "@/lib/api";
import type { Feed } from "@/lib/types";
import { MediaArt } from "./media-art";

type Tab = "up-next" | "lyrics" | "related";
type TimedLyric = { time: number; text: string };

function durationSeconds(value: string | null | undefined) {
  if (!value) return 0;
  const parts = value.split(":").map(Number);
  if (parts.some((part) => !Number.isFinite(part))) return 0;
  return parts.reduce((total, part) => total * 60 + part, 0);
}

export function QueuePanel() {
  const player = usePlayer();
  const [activeTab, setActiveTab] = useState<Tab>("up-next");
  const [visibleCount, setVisibleCount] = useState(18);
  const [lyrics, setLyrics] = useState<{ text: string; source?: string | null; lines: TimedLyric[]; synced: boolean; syncSource?: string | null } | null>(null);
  const [related, setRelated] = useState<Feed | null>(null);
  const [loading, setLoading] = useState(false);
  const [tabError, setTabError] = useState<string | null>(null);
  const lyricsPanelRef = useRef<HTMLDivElement>(null);
  const [lyricsOffset, setLyricsOffset] = useState(0);
  const current = player.current;
  const videoId = player.current?.videoId;
  const lyricDuration = durationSeconds(current?.duration) || player.duration;

  useEffect(() => {
    setActiveTab("up-next");
    setVisibleCount(Math.max(18, player.queueIndex + 10));
    setLyrics(null);
    setRelated(null);
    setTabError(null);
    setLyricsOffset(0);
  }, [videoId, player.queueIndex]);

  useEffect(() => {
    if (!videoId || activeTab === "up-next") return;
    if ((activeTab === "lyrics" && lyrics) || (activeTab === "related" && related)) return;
    const controller = new AbortController();
    setLoading(true);
    setTabError(null);
    const request = activeTab === "lyrics"
      ? musicApi.lyrics(current!, lyricDuration, controller.signal).then((result) => setLyrics({ text: result.lyrics, source: result.source, lines: result.lines || [], synced: result.synced, syncSource: result.syncSource }))
      : musicApi.related(current!, controller.signal).then(setRelated);
    request.catch((reason) => {
      if (!controller.signal.aborted) setTabError(reason instanceof Error ? reason.message : "This tab could not be loaded");
    }).finally(() => {
      if (!controller.signal.aborted) setLoading(false);
    });
    return () => controller.abort();
  }, [activeTab, current, lyricDuration, lyrics, related, videoId]);

  const relatedItems = useMemo(() => {
    const items = related?.shelves.flatMap((shelf) => shelf.items).filter((item) => item.videoId) || [];
    return items.filter((item, index) => items.findIndex((other) => other.id === item.id) === index);
  }, [related]);

  const activeLyricIndex = useMemo(() => {
    if (!lyrics?.lines.length) return -1;
    const playbackTime = player.currentTime + lyricsOffset;
    let active = -1;
    for (let index = 0; index < lyrics.lines.length; index++) {
      if (lyrics.lines[index].time > playbackTime) break;
      active = index;
    }
    return active;
  }, [lyrics, lyricsOffset, player.currentTime]);

  useEffect(() => {
    if (activeTab !== "lyrics" || activeLyricIndex < 0) return;
    const panel = lyricsPanelRef.current;
    const line = panel?.querySelector<HTMLElement>(`[data-lyric-index="${activeLyricIndex}"]`);
    if (!panel || !line) return;
    const top = panel.scrollTop + line.getBoundingClientRect().top - panel.getBoundingClientRect().top
      - panel.clientHeight / 2 + line.clientHeight / 2;
    panel.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
  }, [activeLyricIndex, activeTab]);

  if (!player.queueOpen && !player.fullscreenOpen) return null;

  const revealMore = (event: UIEvent<HTMLDivElement>) => {
    const element = event.currentTarget;
    if (element.scrollHeight - element.scrollTop - element.clientHeight < 220) {
      const nextCount = Math.min(player.queue.length, visibleCount + 14);
      setVisibleCount(nextCount);
      if (nextCount >= player.queue.length - 2) player.loadMoreQueue();
    }
  };

  return (
    <aside className={`queue-panel ${player.fullscreenOpen ? "fullscreen-queue" : ""}`}>
      <header>
        <div><p className="eyebrow">AUTOPLAY RADIO</p><h2>{activeTab === "up-next" ? "Up next" : activeTab === "lyrics" ? "Lyrics" : "Related"}</h2></div>
        <button onClick={() => player.fullscreenOpen ? player.toggleFullscreen() : player.setQueueOpen(false)} aria-label={player.fullscreenOpen ? "Exit fullscreen" : "Close queue"}><X /></button>
      </header>
      <div className="queue-tabs">
        <button className={activeTab === "up-next" ? "active" : ""} onClick={() => setActiveTab("up-next")}>UP NEXT</button>
        <button className={activeTab === "lyrics" ? "active" : ""} onClick={() => setActiveTab("lyrics")}>LYRICS</button>
        <button className={activeTab === "related" ? "active" : ""} onClick={() => setActiveTab("related")}>RELATED</button>
      </div>

      {loading ? <div className="queue-tab-state"><LoaderCircle className="spin" /><span>Loading…</span></div> : tabError ? <div className="queue-tab-state"><span>{tabError}</span></div> : null}

      {!loading && !tabError && activeTab === "up-next" && (
        <div className="queue-list" onScroll={revealMore}>
          {player.queue.slice(0, visibleCount).map((item, index) => (
            <div className={`queue-item ${index === player.queueIndex ? "current" : ""}`} key={`${item.id}-${index}`}>
              <GripVertical size={15} className="drag" />
              <button className="queue-track" onClick={() => player.play(item, player.queue)}><MediaArt item={item} className="size-11 shrink-0 rounded-lg!" /><span><strong>{item.title}</strong><small>{item.subtitle}</small></span></button>
              <div className="queue-move"><button onClick={() => player.moveQueueItem(index, index - 1)} aria-label="Move up"><ArrowUp size={13} /></button><button onClick={() => player.moveQueueItem(index, index + 1)} aria-label="Move down"><ArrowDown size={13} /></button></div>
            </div>
          ))}
          {visibleCount < player.queue.length && <div className="queue-loading-more"><LoaderCircle className="spin" size={16} /> Scroll for more</div>}
        </div>
      )}

      {!loading && !tabError && activeTab === "lyrics" && lyrics && (
        <div className={`lyrics-panel ${lyrics.synced ? "synced" : ""}`} ref={lyricsPanelRef}>
          {lyrics.synced && <div className="lyrics-sync-tools"><span>SYNCED · {lyrics.syncSource}</span><div><button onClick={() => setLyricsOffset((value) => value - 0.5)}>−0.5s</button><button onClick={() => setLyricsOffset(0)}>{lyricsOffset > 0 ? "+" : ""}{lyricsOffset.toFixed(1)}s</button><button onClick={() => setLyricsOffset((value) => value + 0.5)}>+0.5s</button></div></div>}
          {lyrics.synced ? lyrics.lines.map((line, index) => (
            <button
              key={`${line.time}-${index}`}
              data-lyric-index={index}
              className={`lyric-line ${index === activeLyricIndex ? "active" : ""} ${index < activeLyricIndex ? "past" : ""}`}
              onClick={() => player.seek(Math.max(0, line.time - lyricsOffset))}
            >{line.text}</button>
          )) : <p>{lyrics.text}</p>}
          {(lyrics.source || lyrics.syncSource) && <small>{lyrics.source || `Timing: ${lyrics.syncSource}`}</small>}
        </div>
      )}

      {!loading && !tabError && activeTab === "related" && (
        <div className="related-list">
          {relatedItems.map((item) => (
            <button key={item.id} className="queue-track related-track" onClick={() => player.play(item, [])}>
              <MediaArt item={item} className="size-12 shrink-0 rounded-lg!" />
              <span><strong>{item.title}</strong><small>{item.subtitle}</small></span><Play size={15} />
            </button>
          ))}
          {!relatedItems.length && <div className="queue-tab-state">No related tracks were returned.</div>}
        </div>
      )}
    </aside>
  );
}
