"use client";

import { useState, useId, type FormEvent } from "react";
import { ArrowRight, Headphones, RefreshCw, Sparkles, UserCheck } from "lucide-react";

const SUGGESTION_POOL = [
  "Wave Rider",
  "Sonic Nomad",
  "Aura Groove",
  "Neon Rhythm",
  "Echo Chaser",
  "Velvet Beats",
  "Melody Seeker",
  "Cosmic Flow",
  "Midnight Chords",
  "Solar Harmony",
  "Bass Voyager",
  "Indie Pulse",
  "Rhythm Nomad",
  "Audio Explorer",
  "Luna Grooves",
  "Electric Soul",
];

function getRandomSuggestions(count = 6, currentList: string[] = []): string[] {
  const filtered = SUGGESTION_POOL.filter((item) => !currentList.includes(item));
  const pool = filtered.length >= count ? filtered : SUGGESTION_POOL;
  return [...pool].sort(() => Math.random() - 0.5).slice(0, count);
}

type Props = {
  isOpen: boolean;
  onComplete: (name: string) => void;
  initialName?: string;
  isClosable?: boolean;
  onClose?: () => void;
};

export function UserModal({ isOpen, onComplete, initialName = "", isClosable = false, onClose }: Props) {
  const [name, setName] = useState(initialName);
  const [suggestions, setSuggestions] = useState<string[]>(() => getRandomSuggestions(6));
  const [error, setError] = useState<string | null>(null);
  const inputId = useId();

  if (!isOpen) return null;

  const handleRefreshSuggestions = () => {
    setSuggestions((prev) => getRandomSuggestions(6, prev));
  };

  const handleSelectSuggestion = (suggested: string) => {
    setName(suggested);
    setError(null);
  };

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError("Please enter your name or pick a suggestion.");
      return;
    }
    if (trimmed.length < 2) {
      setError("Name must be at least 2 characters.");
      return;
    }
    if (trimmed.length > 30) {
      setError("Name cannot exceed 30 characters.");
      return;
    }
    setError(null);
    onComplete(trimmed);
  };

  return (
    <div
      className="fixed inset-0 z-100 flex items-center justify-center p-4 bg-black/85 backdrop-blur-2xl animate-fade-in"
      role="dialog"
      aria-modal="true"
      aria-labelledby="onboarding-title"
    >
      {/* Ambient background glow behind modal */}
      <div className="absolute w-96 h-96 rounded-full bg-[#d5ff63]/10 blur-3xl pointer-events-none -top-10 -left-10" />
      <div className="absolute w-96 h-96 rounded-full bg-[#2b665c]/20 blur-3xl pointer-events-none -bottom-10 -right-10" />

      <div className="relative w-full max-w-md overflow-hidden rounded-3xl border border-white/10 bg-[#0d1012]/95 p-7 shadow-2xl shadow-black/80 backdrop-blur-3xl">
        {/* Glow accent header bar */}
        <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-[#d5ff63] via-[#7ae697] to-[#2b665c]" />

        <div className="mb-6 flex items-center gap-3">
          <div className="grid size-12 place-items-center rounded-2xl bg-[#d5ff63] text-black shadow-lg shadow-[#d5ff63]/20">
            <Headphones size={24} className="stroke-[2.5]" />
          </div>
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-extrabold tracking-widest text-[#d5ff63] uppercase">
              <Sparkles size={12} />
              <span>Welcome to InnerWave</span>
            </div>
            <h2 id="onboarding-title" className="text-xl font-bold tracking-tight text-white">
              What should we call you?
            </h2>
          </div>
        </div>

        <p className="mb-5 text-xs text-neutral-400 leading-relaxed">
          Set your listener name to personalize your private YouTube Music experience, custom shelves, and playlists.
        </p>

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label htmlFor={inputId} className="mb-1.5 block text-[11px] font-semibold text-neutral-300">
              Your Name or Moniker
            </label>
            <div className="relative flex items-center">
              <input
                id={inputId}
                type="text"
                value={name}
                onChange={(e) => {
                  setName(e.target.value);
                  if (error) setError(null);
                }}
                placeholder="e.g. Alex, Neon Groove, MelodySeeker"
                autoFocus
                maxLength={30}
                className="w-full rounded-xl border border-white/15 bg-white/5 px-3.5 py-2.5 text-sm text-white placeholder:text-neutral-500 transition focus:border-[#d5ff63] focus:bg-white/10 focus:outline-none focus:ring-1 focus:ring-[#d5ff63]"
              />
              {name.trim().length >= 2 && (
                <span className="absolute right-3 text-[#d5ff63]">
                  <UserCheck size={18} />
                </span>
              )}
            </div>
            {error && <p className="mt-1.5 text-[11px] text-red-400">{error}</p>}
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[10px] font-bold tracking-wider text-neutral-400 uppercase">
                Or pick a suggestion:
              </span>
              <button
                type="button"
                onClick={handleRefreshSuggestions}
                className="flex items-center gap-1 text-[10px] text-neutral-400 transition hover:text-[#d5ff63]"
                title="Shuffle suggestions"
              >
                <RefreshCw size={11} />
                <span>Shuffle</span>
              </button>
            </div>

            <div className="flex flex-wrap gap-1.5">
              {suggestions.map((suggestion) => {
                const isSelected = name === suggestion;
                return (
                  <button
                    key={suggestion}
                    type="button"
                    onClick={() => handleSelectSuggestion(suggestion)}
                    className={`rounded-lg px-2.5 py-1 text-xs font-medium transition ${
                      isSelected
                        ? "border border-[#d5ff63] bg-[#d5ff63]/20 text-[#d5ff63]"
                        : "border border-white/10 bg-white/5 text-neutral-300 hover:border-white/20 hover:bg-white/10 hover:text-white"
                    }`}
                  >
                    {suggestion}
                  </button>
                );
              })}
            </div>
          </div>

          <div className="pt-2">
            <button
              type="submit"
              disabled={name.trim().length < 2}
              className="group flex w-full items-center justify-center gap-2 rounded-xl bg-[#d5ff63] py-2.5 text-xs font-bold text-black shadow-lg shadow-[#d5ff63]/20 transition duration-200 hover:bg-[#e4ff88] hover:shadow-[#d5ff63]/40 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <span>Continue to Music</span>
              <ArrowRight size={15} className="transition group-hover:translate-x-0.5" />
            </button>
          </div>

          {isClosable && onClose && (
            <div className="text-center pt-1">
              <button
                type="button"
                onClick={onClose}
                className="text-[11px] text-neutral-400 hover:text-white transition"
              >
                Cancel
              </button>
            </div>
          )}
        </form>
      </div>
    </div>
  );
}
