"use client";

import { ChevronDown, ListMusic, Pause, Play, Repeat2, Shuffle, SkipBack, SkipForward } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { MediaArt } from "./media-art";
import { Seekbar } from "./seekbar";

export function FullscreenPlayer() {
  const player = usePlayer();
  if (!player.fullscreenOpen || !player.current) return null;
  return (
    <section className="fullscreen-player with-queue">
      {player.current.thumbnail && <div className="fullscreen-backdrop" style={{ backgroundImage: `url(${player.current.thumbnail})` }} />}
      <header><button onClick={player.toggleFullscreen} aria-label="Exit fullscreen"><ChevronDown /></button><div><small>PLAYING FROM</small><strong>{player.current.playlistId ? "Your selected playlist" : "Song radio"}</strong></div><button onClick={() => player.setQueueOpen(true)} aria-label="Open queue"><ListMusic /></button></header>
      <div className="fullscreen-content">
        <MediaArt item={player.current} className="fullscreen-art" />
        <div className="fullscreen-meta"><h1>{player.current.title}</h1><p>{player.current.subtitle}</p></div>
        <Seekbar currentTime={player.currentTime} duration={player.duration} buffered={player.buffered} onSeek={player.seek} large />
        <div className="fullscreen-controls"><button aria-label="Shuffle"><Shuffle /></button><button onClick={player.previous} aria-label="Previous"><SkipBack fill="currentColor" /></button><button className="fullscreen-play" onClick={player.toggle} aria-label={player.isPlaying ? "Pause" : "Play"}>{player.isPlaying ? <Pause fill="currentColor" /> : <Play fill="currentColor" />}</button><button onClick={player.next} aria-label="Next"><SkipForward fill="currentColor" /></button><button aria-label="Repeat"><Repeat2 /></button></div>
      </div>
    </section>
  );
}
