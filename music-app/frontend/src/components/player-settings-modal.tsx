"use client";

import { Moon, Sliders, Volume2, X } from "lucide-react";
import { usePlayer } from "@/context/player-context";

type Props = {
  isOpen: boolean;
  onClose: () => void;
};

export function PlayerSettingsModal({ isOpen, onClose }: Props) {
  const {
    sleepTimerRemaining,
    sleepTimerMode,
    setSleepTimer,
    cancelSleepTimer,
    crossfade,
    setCrossfade,
    audioQuality,
    setAudioQuality,
  } = usePlayer();

  if (!isOpen) return null;

  const formatRemaining = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  const timerOptions: { label: string; value: number | "end-of-track" }[] = [
    { label: "15 min", value: 15 },
    { label: "30 min", value: 30 },
    { label: "45 min", value: 45 },
    { label: "60 min", value: 60 },
    { label: "End of track", value: "end-of-track" },
  ];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md p-4 animate-in fade-in duration-200">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-[#12141A] p-6 shadow-2xl text-white">
        <div className="flex items-center justify-between pb-4 border-b border-white/10">
          <div className="flex items-center gap-2">
            <Sliders size={20} className="text-cyan-400" />
            <h2 className="text-base font-semibold">Playback & Audio Settings</h2>
          </div>
          <button
            onClick={onClose}
            className="rounded-full p-1.5 text-white/60 hover:bg-white/10 hover:text-white transition"
          >
            <X size={18} />
          </button>
        </div>

        {/* 1. Sleep Timer Section */}
        <div className="mt-5 space-y-3">
          <div className="flex items-center justify-between">
            <span className="flex items-center gap-2 text-sm font-medium text-white/90">
              <Moon size={16} className="text-purple-400" /> Sleep Timer
            </span>
            {sleepTimerMode !== null && (
              <span className="text-xs px-2.5 py-0.5 rounded-full bg-purple-500/20 text-purple-300 font-semibold animate-pulse">
                {sleepTimerMode === "end-of-track"
                  ? "At end of song"
                  : sleepTimerRemaining !== null
                  ? `${formatRemaining(sleepTimerRemaining)} left (fading)`
                  : "Active"}
              </span>
            )}
          </div>

          <div className="grid grid-cols-3 gap-2">
            {timerOptions.map((opt) => {
              const active = sleepTimerMode === opt.value;
              return (
                <button
                  key={String(opt.value)}
                  onClick={() => setSleepTimer(opt.value)}
                  className={`py-2 px-3 rounded-xl text-xs font-medium border transition ${
                    active
                      ? "border-purple-500 bg-purple-500/20 text-purple-200"
                      : "border-white/10 bg-white/5 hover:border-white/20 text-white/80"
                  }`}
                >
                  {opt.label}
                </button>
              );
            })}
            {sleepTimerMode !== null && (
              <button
                onClick={cancelSleepTimer}
                className="py-2 px-3 rounded-xl text-xs font-medium border border-rose-500/40 bg-rose-500/10 text-rose-300 hover:bg-rose-500/20 transition"
              >
                Turn off
              </button>
            )}
          </div>
          <p className="text-[11px] text-white/40">
            Music volume will automatically and gradually fade out before playback pauses.
          </p>
        </div>

        {/* 2. Audio Quality Section */}
        <div className="mt-6 space-y-3 pt-5 border-t border-white/10">
          <span className="flex items-center gap-2 text-sm font-medium text-white/90">
            <Volume2 size={16} className="text-cyan-400" /> Audio Stream Quality
          </span>

          <div className="grid grid-cols-3 gap-2">
            {[
              { id: "high" as const, label: "High", sub: "256 kbps" },
              { id: "normal" as const, label: "Normal", sub: "128 kbps" },
              { id: "low" as const, label: "Saver", sub: "64 kbps" },
            ].map((q) => (
              <button
                key={q.id}
                onClick={() => setAudioQuality(q.id)}
                className={`flex flex-col items-center py-2.5 px-3 rounded-xl border transition ${
                  audioQuality === q.id
                    ? "border-cyan-400 bg-cyan-400/20 text-cyan-200"
                    : "border-white/10 bg-white/5 hover:border-white/20 text-white/80"
                }`}
              >
                <span className="text-xs font-semibold">{q.label}</span>
                <span className="text-[10px] text-white/50">{q.sub}</span>
              </button>
            ))}
          </div>
        </div>

        {/* 3. Crossfade Section */}
        <div className="mt-6 space-y-3 pt-5 border-t border-white/10">
          <div className="flex items-center justify-between text-sm font-medium">
            <span className="text-white/90">Crossfade</span>
            <span className="text-cyan-400 font-bold">{crossfade > 0 ? `${crossfade}s` : "Off"}</span>
          </div>

          <input
            type="range"
            min={0}
            max={12}
            step={1}
            value={crossfade}
            onChange={(e) => setCrossfade(Number(e.target.value))}
            className="w-full accent-cyan-400 h-1.5 bg-white/10 rounded-lg cursor-pointer"
          />
          <div className="flex justify-between text-[10px] text-white/40">
            <span>Off</span>
            <span>3s</span>
            <span>6s</span>
            <span>9s</span>
            <span>12s</span>
          </div>
        </div>
      </div>
    </div>
  );
}
