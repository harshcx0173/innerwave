"use client";

import { useState } from "react";
import { ListMusic, Maximize2, Moon, Pause, Play, Plus, Repeat2, Share2, Shuffle, SkipBack, SkipForward, Sliders, Volume1, Volume2 } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { useListeningRoom } from "@/context/listening-room-context";
import { usePlaylist } from "@/context/playlist-context";
import { MediaArt } from "./media-art";
import { Seekbar } from "./seekbar";
import { PlayerSettingsModal } from "./player-settings-modal";
import { ArtistSubtitle } from "./artist-subtitle";

export function PlayerBar() {
  const player = usePlayer();
  const room = useListeningRoom();
  const { openAddToPlaylistModal } = usePlaylist();
  const [settingsOpen, setSettingsOpen] = useState(false);
  const { current } = player;
  const isListener = room.isInRoom && !room.isHost;
  const showGoLive = isListener && (!room.isLive || !player.isPlaying);

  const handlePlayToggle = () => {
    if (isListener) {
      if (room.isLive && player.isPlaying) {
        room.pauseListener();
      } else {
        room.goLive();
      }
    } else {
      player.toggle();
    }
  };

  return (
    <>
      <footer className={`player-bar ${current ? "visible" : ""}`}>
        <div className="track-identity">
          {current ? (
            <MediaArt item={current} className="size-14 shrink-0 rounded-xl!" />
          ) : (
            <div className="size-14 rounded-xl bg-white/5" />
          )}
          <span className="item-copy min-w-0">
            <strong>{current?.title || "Choose something to play"}</strong>
            {current ? (
              <ArtistSubtitle item={current} />
            ) : (
              <small>Your music will appear here</small>
            )}
          </span>
          {current && (
            <div className="flex items-center gap-1 ml-1 text-white/50">
              <button
                onClick={() => openAddToPlaylistModal(current)}
                className="p-1.5 rounded-lg hover:bg-white/10 hover:text-white transition"
                title="Add to playlist"
                aria-label="Add to playlist"
              >
                <Plus size={16} />
              </button>
              <button
                onClick={() => player.openShareModal(current)}
                className="p-1.5 rounded-lg hover:bg-white/10 hover:text-white transition"
                title="Share song card"
                aria-label="Share song"
              >
                <Share2 size={16} />
              </button>
            </div>
          )}
        </div>
        <div className="transport">
          <div className="transport-buttons">
            <button aria-label="Shuffle"><Shuffle size={16} /></button>
            <button onClick={player.previous} aria-label="Previous"><SkipBack size={18} fill="currentColor" /></button>
            {showGoLive ? (
              <button className="play-main go-live" onClick={room.goLive} title="Sync with room and go live" aria-label="Go Live">
                <span className="live-dot" />
                <span className="live-text">LIVE</span>
              </button>
            ) : (
              <button className="play-main" onClick={handlePlayToggle} disabled={!current} aria-label={player.isPlaying ? "Pause" : "Play"}>
                {player.isPlaying ? <Pause fill="currentColor" /> : <Play fill="currentColor" className="ml-0.5" />}
              </button>
            )}
            <button onClick={player.next} aria-label="Next"><SkipForward size={18} fill="currentColor" /></button>
            <button aria-label="Repeat"><Repeat2 size={16} /></button>
          </div>
          <Seekbar currentTime={player.currentTime} duration={player.duration} buffered={player.buffered} onSeek={player.seek} />
          {player.error && <div className="player-error">{player.error}</div>}
        </div>
        <div className="player-actions">
          {room.isInRoom && (
            <button
              className={`room-sync-indicator ${room.isLive && player.isPlaying ? "live" : "desynced"}`}
              onClick={room.isLive && player.isPlaying ? room.pauseListener : room.goLive}
              title={room.isHost ? "You are hosting the room" : room.isLive ? "Listening live • Click to pause" : "Click to go live with host"}
            >
              <span className="pulse-dot" />
              <small>{room.isHost ? "HOSTING" : room.isLive ? "LIVE" : "GO LIVE"}</small>
            </button>
          )}

          {player.sleepTimerMode !== null && (
            <button
              onClick={() => setSettingsOpen(true)}
              className="flex items-center gap-1 px-2 py-1 rounded-full bg-purple-500/20 text-purple-300 text-xs font-semibold hover:bg-purple-500/30 transition animate-pulse"
              title="Sleep timer active"
            >
              <Moon size={13} />
              <span>
                {player.sleepTimerMode === "end-of-track"
                  ? "Track end"
                  : player.sleepTimerRemaining !== null
                  ? `${Math.ceil(player.sleepTimerRemaining / 60)}m`
                  : "Active"}
              </span>
            </button>
          )}

          <button
            aria-label="Audio settings"
            onClick={() => setSettingsOpen(true)}
            title="Audio & Sleep settings"
            className="hover:text-white transition"
          >
            <Sliders size={17} />
          </button>

          <button aria-label="Queue" onClick={() => player.setQueueOpen(!player.queueOpen)} className={player.queueOpen ? "active" : ""}><ListMusic size={18} /></button>
          {player.volume === 0 ? <Volume1 size={18} /> : <Volume2 size={18} />}
          <input aria-label="Volume" type="range" min={0} max={1} step={0.01} value={player.volume} onChange={(event) => player.setVolume(Number(event.target.value))} />
          <button aria-label="Fullscreen" onClick={player.toggleFullscreen}><Maximize2 size={17} /></button>
        </div>
      </footer>
      <PlayerSettingsModal isOpen={settingsOpen} onClose={() => setSettingsOpen(false)} />
    </>
  );
}
