"use client";

/* eslint-disable @next/next/no-img-element */
import { useRef, useState } from "react";
import { Check, Copy, Download, Radio, Share2, X } from "lucide-react";
import { usePlayer } from "@/context/player-context";
import { useListeningRoom } from "@/context/listening-room-context";

export function SongShareModal() {
  const { activeShareSong, closeShareModal } = usePlayer();
  const room = useListeningRoom();
  const [copiedLink, setCopiedLink] = useState(false);
  const [copiedCode, setCopiedCode] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const posterRef = useRef<HTMLDivElement>(null);

  if (!activeShareSong) return null;

  const song = activeShareSong;
  const artistName = song.artists.join(", ") || song.subtitle.split(" · ")[0] || "Unknown Artist";

  const handleCopyLink = async () => {
    try {
      const shareUrl = `${window.location.origin}/?v=${encodeURIComponent(song.videoId || song.id)}`;
      await navigator.clipboard.writeText(shareUrl);
      setCopiedLink(true);
      setTimeout(() => setCopiedLink(false), 2500);
    } catch {
      // fallback
    }
  };

  const handleCopyRoomCode = async () => {
    if (!room.room?.code) return;
    try {
      await navigator.clipboard.writeText(room.room.code);
      setCopiedCode(true);
      setTimeout(() => setCopiedCode(false), 2500);
    } catch {
      // fallback
    }
  };

  const handleDownloadPoster = async () => {
    setDownloading(true);
    try {
      // Render canvas representation of the share card
      const canvas = document.createElement("canvas");
      canvas.width = 1080;
      canvas.height = 1440;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;

      // Dark gradient background
      const grad = ctx.createLinearGradient(0, 0, 1080, 1440);
      grad.addColorStop(0, "#1F1B2C");
      grad.addColorStop(0.5, "#0F1117");
      grad.addColorStop(1, "#08090C");
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, 1080, 1440);

      // Top brand badge
      ctx.fillStyle = "rgba(255, 255, 255, 0.7)";
      ctx.font = "bold 34px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("INNERWAVE MUSIC", 540, 120);

      // Draw artwork
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.src = song.thumbnail || "";
      await new Promise((res) => {
        img.onload = res;
        img.onerror = res;
      });

      if (img.width > 0) {
        ctx.save();
        ctx.beginPath();
        ctx.roundRect(140, 200, 800, 800, [40]);
        ctx.clip();
        ctx.drawImage(img, 140, 200, 800, 800);
        ctx.restore();
      }

      // Title
      ctx.fillStyle = "#FFFFFF";
      ctx.font = "bold 58px sans-serif";
      ctx.textAlign = "left";
      const title = song.title.length > 28 ? song.title.substring(0, 28) + "…" : song.title;
      ctx.fillText(title, 140, 1090);

      // Artist
      ctx.fillStyle = "rgba(255, 255, 255, 0.65)";
      ctx.font = "38px sans-serif";
      const artist = artistName.length > 34 ? artistName.substring(0, 34) + "…" : artistName;
      ctx.fillText(artist, 140, 1155);

      // Waveform bars simulation
      ctx.fillStyle = "#00F0FF";
      const barCount = 36;
      const startX = 140;
      const barWidth = 14;
      const spacing = 22;
      for (let i = 0; i < barCount; i++) {
        const h = 25 + Math.sin(i * 0.4) * 35 + ((i % 5) * 8);
        ctx.beginPath();
        ctx.roundRect(startX + i * spacing, 1280 - h / 2, barWidth, h, [6]);
        ctx.fill();
      }

      // Trigger download
      const link = document.createElement("a");
      link.download = `${song.title.replace(/[^a-zA-Z0-9]/g, "_")}_innerwave_card.png`;
      link.href = canvas.toDataURL("image/png");
      link.click();
    } catch {
      // fallback
    } finally {
      setDownloading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md p-4 animate-in fade-in duration-200">
      <div className="relative w-full max-w-sm rounded-3xl border border-white/10 bg-[#12141A] p-5 shadow-2xl">
        <button
          onClick={closeShareModal}
          className="absolute top-4 right-4 z-10 rounded-full p-2 bg-black/40 text-white/70 hover:bg-black/70 hover:text-white transition"
          aria-label="Close"
        >
          <X size={18} />
        </button>

        {/* Visual Poster Card */}
        <div
          ref={posterRef}
          className="relative overflow-hidden rounded-2xl p-6 text-center shadow-inner"
          style={{
            background: "linear-gradient(145deg, #2D1B4E 0%, #161822 55%, #0B0D12 100%)",
          }}
        >
          <div className="flex items-center justify-center gap-1.5 mb-5 text-[11px] font-bold tracking-widest text-cyan-400 uppercase">
            <Radio size={14} className="animate-pulse" />
            InnerWave Music
          </div>

          <div className="relative mx-auto aspect-square w-52 overflow-hidden rounded-2xl shadow-2xl border border-white/10 mb-5">
            <img
              src={song.thumbnail || ""}
              alt={song.title}
              className="w-full h-full object-cover"
              referrerPolicy="no-referrer"
            />
          </div>

          <h3 className="text-lg font-bold text-white truncate px-2">{song.title}</h3>
          <p className="text-xs text-white/60 truncate mt-1 px-2">{artistName}</p>

          {/* Decorative soundwave */}
          <div className="flex items-center justify-center gap-1 my-5 h-8">
            {[40, 65, 30, 85, 55, 95, 45, 75, 60, 90, 50, 70, 35, 80].map((h, i) => (
              <span
                key={i}
                className="w-1 rounded-full bg-cyan-400/80"
                style={{ height: `${h}%` }}
              />
            ))}
          </div>

          <p className="text-[10px] text-white/40 uppercase tracking-wider">
            Listen on InnerWave
          </p>
        </div>

        {/* Action Buttons */}
        <div className="mt-4 space-y-2">
          <button
            onClick={handleCopyLink}
            className="w-full flex items-center justify-center gap-2 rounded-xl bg-cyan-500 py-3 text-sm font-semibold text-black hover:bg-cyan-400 transition"
          >
            {copiedLink ? <Check size={16} /> : <Copy size={16} />}
            {copiedLink ? "Link Copied to Clipboard!" : "Copy Track Link"}
          </button>

          {room.isInRoom && room.room?.code && (
            <button
              onClick={handleCopyRoomCode}
              className="w-full flex items-center justify-center gap-2 rounded-xl bg-purple-600/30 border border-purple-500/40 py-2.5 text-sm font-medium text-purple-200 hover:bg-purple-600/40 transition"
            >
              {copiedCode ? <Check size={16} /> : <Share2 size={16} />}
              {copiedCode ? "Room Code Copied!" : `Copy Room Code: ${room.room.code}`}
            </button>
          )}

          <button
            onClick={handleDownloadPoster}
            disabled={downloading}
            className="w-full flex items-center justify-center gap-2 rounded-xl bg-white/10 py-2.5 text-sm font-medium text-white hover:bg-white/15 transition disabled:opacity-50"
          >
            <Download size={16} />
            {downloading ? "Generating Poster..." : "Save Poster Image"}
          </button>
        </div>
      </div>
    </div>
  );
}
