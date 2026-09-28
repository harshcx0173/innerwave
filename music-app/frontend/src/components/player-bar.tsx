"use client";

import { ListMusic, Maximize2, Pause, Play, Repeat2, Shuffle, SkipBack, SkipForward, Volume1, Volume2 } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { MediaArt } from "./media-art";
import { Seekbar } from "./seekbar";

export function PlayerBar() {
  const player = usePlayer();
  const { current } = player;
  return (
    <footer className={`player-bar ${current ? "visible" : ""}`}>
      <div className="track-identity">
        {current ? <MediaArt item={current} className="size-14 shrink-0 rounded-xl!" /> : <div className="size-14 rounded-xl bg-white/5" />}
        <span className="item-copy"><strong>{current?.title || "Choose something to play"}</strong><small>{current?.subtitle || "Your music will appear here"}</small></span>
      </div>
      <div className="transport">
        <div className="transport-buttons"><button aria-label="Shuffle"><Shuffle size={16} /></button><button onClick={player.previous} aria-label="Previous"><SkipBack size={18} fill="currentColor" /></button><button className="play-main" onClick={player.toggle} disabled={!current} aria-label={player.isPlaying ? "Pause" : "Play"}>{player.isPlaying ? <Pause fill="currentColor" /> : <Play fill="currentColor" className="ml-0.5" />}</button><button onClick={player.next} aria-label="Next"><SkipForward size={18} fill="currentColor" /></button><button aria-label="Repeat"><Repeat2 size={16} /></button></div>
        <Seekbar currentTime={player.currentTime} duration={player.duration} buffered={player.buffered} onSeek={player.seek} />
        {player.error && <div className="player-error">{player.error}</div>}
      </div>
      <div className="player-actions"><button aria-label="Queue" onClick={() => player.setQueueOpen(!player.queueOpen)} className={player.queueOpen ? "active" : ""}><ListMusic size={18} /></button>{player.volume === 0 ? <Volume1 size={18} /> : <Volume2 size={18} />}<input aria-label="Volume" type="range" min={0} max={1} step={0.01} value={player.volume} onChange={(event) => player.setVolume(Number(event.target.value))} /><button aria-label="Fullscreen" onClick={player.toggleFullscreen}><Maximize2 size={17} /></button></div>
    </footer>
  );
}
