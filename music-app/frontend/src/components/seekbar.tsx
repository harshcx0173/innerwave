"use client";

import { useState, type CSSProperties, type PointerEvent } from "react";

function formatTime(value: number) {
  if (!Number.isFinite(value) || value < 0) return "0:00";
  return `${Math.floor(value / 60)}:${String(Math.floor(value % 60)).padStart(2, "0")}`;
}

export function Seekbar({ currentTime, duration, buffered, onSeek, large = false }: {
  currentTime: number;
  duration: number;
  buffered: number;
  onSeek: (time: number) => void;
  large?: boolean;
}) {
  const [preview, setPreview] = useState<number | null>(null);
  const max = duration || 1;
  const playedPercent = Math.min(100, Math.max(0, (currentTime / max) * 100));
  const bufferedPercent = Math.min(100, Math.max(playedPercent, (buffered / max) * 100));
  const previewPercent = preview == null ? 0 : (preview / max) * 100;

  function updatePreview(event: PointerEvent<HTMLInputElement>) {
    const bounds = event.currentTarget.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (event.clientX - bounds.left) / bounds.width));
    setPreview(ratio * max);
  }

  return (
    <div className={`seekbar-shell ${large ? "large" : ""}`}>
      <span>{formatTime(currentTime)}</span>
      <div className="seekbar-track-wrap">
        {preview != null && <output className="seek-preview" style={{ left: `${previewPercent}%` }}>{formatTime(preview)}</output>}
        <input
          className="enhanced-seekbar"
          aria-label="Track position"
          type="range"
          min={0}
          max={max}
          step={0.1}
          value={Math.min(currentTime, max)}
          onChange={(event) => onSeek(Number(event.target.value))}
          onPointerMove={updatePreview}
          onPointerLeave={() => setPreview(null)}
          style={{ "--played": `${playedPercent}%`, "--buffered": `${bufferedPercent}%` } as CSSProperties}
        />
      </div>
      <span>{formatTime(duration)}</span>
    </div>
  );
}
