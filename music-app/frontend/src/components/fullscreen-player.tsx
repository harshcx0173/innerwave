"use client";

import { useState } from "react";
import { Activity, ChevronDown, ListMusic, Pause, Play, Plus, Repeat2, Share2, Shuffle, SkipBack, SkipForward } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { useListeningRoom } from "@/context/listening-room-context";
import { usePlaylist } from "@/context/playlist-context";
import { MediaArt } from "./media-art";
import { Seekbar } from "./seekbar";
import { AudioVisualizer } from "./audio-visualizer";

export function FullscreenPlayer() {
  const player = usePlayer();
  const room = useListeningRoom();
  const { openAddToPlaylistModal } = usePlaylist();
  const [showVisualizer, setShowVisualizer] = useState(true);

  if (!player.fullscreenOpen || !player.current) return null;

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

  const artist = player.current.artists[0] || player.current.subtitle.split(" · ")[0];

  return (
    <section className="fullscreen-player with-queue">
      {player.current.thumbnail && <div className="fullscreen-backdrop" style={{ backgroundImage: `url(${player.current.thumbnail})` }} />}
      <header>
        <button onClick={player.toggleFullscreen} aria-label="Exit fullscreen"><ChevronDown /></button>
        <div>
          <small>{room.isInRoom ? (room.isHost ? "HOSTING ROOM" : room.isLive ? "LISTENING LIVE" : "PAUSED (DESYNCED)") : "PLAYING FROM"}</small>
          <strong>{room.isInRoom ? room.room?.name || "Listening Room" : player.current.playlistId ? "Your selected playlist" : "Song radio"}</strong>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setShowVisualizer((prev) => !prev)}
            className={`p-2 rounded-xl transition ${showVisualizer ? "bg-cyan-500/20 text-cyan-400" : "text-white/60 hover:text-white"}`}
            title={showVisualizer ? "Hide Visualizer" : "Show Visualizer"}
            aria-label="Toggle Visualizer"
          >
            <Activity size={20} />
          </button>
          <button
            onClick={() => player.openShareModal(player.current!)}
            className="p-2 rounded-xl text-white/60 hover:text-white hover:bg-white/10 transition"
            title="Share Song Card"
            aria-label="Share Song Card"
          >
            <Share2 size={20} />
          </button>
          <button
            onClick={() => openAddToPlaylistModal(player.current!)}
            className="p-2 rounded-xl text-white/60 hover:text-white hover:bg-white/10 transition"
            title="Add to Playlist"
            aria-label="Add to Playlist"
          >
            <Plus size={20} />
          </button>
          <button onClick={() => player.setQueueOpen(true)} aria-label="Open queue"><ListMusic /></button>
        </div>
      </header>
      <div className="fullscreen-content">
        <MediaArt item={player.current} className="fullscreen-art" />
        {showVisualizer && (
          <div className="w-full max-w-md my-2">
            <AudioVisualizer isPlaying={player.isPlaying} />
          </div>
        )}
        <div className="fullscreen-meta">
          <h1>{player.current.title}</h1>
          {artist ? (
            <p
              onClick={() => {
                player.toggleFullscreen();
                player.openArtistView(artist);
              }}
              className="cursor-pointer hover:underline hover:text-cyan-400 transition"
              title={`View ${artist}`}
            >
              {player.current.subtitle || artist}
            </p>
          ) : (
            <p>{player.current.subtitle}</p>
          )}
        </div>
        <Seekbar currentTime={player.currentTime} duration={player.duration} buffered={player.buffered} onSeek={player.seek} large />
        <div className="fullscreen-controls">
          <button aria-label="Shuffle"><Shuffle /></button>
          <button onClick={player.previous} aria-label="Previous"><SkipBack fill="currentColor" /></button>
          {showGoLive ? (
            <button className="fullscreen-play go-live" onClick={room.goLive} title="Sync with room and go live" aria-label="Go Live">
              <span className="live-dot" />
              <span className="live-label">GO LIVE</span>
            </button>
          ) : (
            <button className="fullscreen-play" onClick={handlePlayToggle} aria-label={player.isPlaying ? "Pause" : "Play"}>
              {player.isPlaying ? <Pause fill="currentColor" /> : <Play fill="currentColor" />}
            </button>
          )}
          <button onClick={player.next} aria-label="Next"><SkipForward fill="currentColor" /></button>
          <button aria-label="Repeat"><Repeat2 /></button>
        </div>
      </div>
    </section>
  );
}
