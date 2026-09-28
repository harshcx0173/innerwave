"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { API_URL, musicApi } from "@/lib/api";
import type { MediaItem } from "@/lib/types";

type PlayerContextValue = {
  current: MediaItem | null;
  queue: MediaItem[];
  queueIndex: number;
  isPlaying: boolean;
  queueOpen: boolean;
  fullscreenOpen: boolean;
  currentTime: number;
  duration: number;
  buffered: number;
  volume: number;
  error: string | null;
  play: (item: MediaItem, context?: MediaItem[]) => void;
  toggle: () => void;
  next: () => void;
  previous: () => void;
  seek: (time: number) => void;
  setVolume: (volume: number) => void;
  setQueueOpen: (open: boolean) => void;
  toggleFullscreen: () => void;
  moveQueueItem: (from: number, to: number) => void;
  loadMoreQueue: () => void;
};

type PersistedPlayer = {
  current: MediaItem | null;
  queue: MediaItem[];
  queueIndex: number;
  currentTime: number;
  volume: number;
  isPlaying: boolean;
  queueContinuation: string | null;
  seenIds: string[];
};

const STORAGE_KEY = "innertube-player-session-v2";
const PlayerContext = createContext<PlayerContextValue | null>(null);

function remember(item: MediaItem) {
  const history = JSON.parse(localStorage.getItem("innerwave-history") || "[]") as MediaItem[];
  const next = [item, ...history.filter((entry) => entry.id !== item.id)].slice(0, 50);
  localStorage.setItem("innerwave-history", JSON.stringify(next));
  window.dispatchEvent(new Event("innerwave-history"));
}

export function PlayerProvider({ children }: { children: ReactNode }) {
  const audio = useRef<HTMLAudioElement>(null);
  const continuationLoading = useRef(false);
  const restored = useRef(false);
  const resumeTime = useRef(0);
  const queueRef = useRef<MediaItem[]>([]);
  const seenIdsRef = useRef<Set<string>>(new Set());
  const [current, setCurrent] = useState<MediaItem | null>(null);
  const [queue, setQueue] = useState<MediaItem[]>([]);
  const [queueIndex, setQueueIndex] = useState(0);
  const [queueContinuation, setQueueContinuation] = useState<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [queueOpen, setQueueOpen] = useState(false);
  const [fullscreenOpen, setFullscreenOpen] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [volume, setVolumeState] = useState(0.8);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    queueRef.current = queue;
  }, [queue]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      try {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "null") as PersistedPlayer | null;
        if (saved?.current?.videoId) {
          resumeTime.current = Math.max(0, Number(saved.currentTime) || 0);
          setCurrent(saved.current);
          setQueue(Array.isArray(saved.queue) && saved.queue.length ? saved.queue : [saved.current]);
          setQueueIndex(Math.max(0, Number(saved.queueIndex) || 0));
          setCurrentTime(resumeTime.current);
          setVolumeState(Math.max(0, Math.min(1, Number(saved.volume) || 0.8)));
          setQueueContinuation(saved.queueContinuation || null);
          seenIdsRef.current = new Set([
            ...(Array.isArray(saved.seenIds) ? saved.seenIds : []),
            ...(Array.isArray(saved.queue) ? saved.queue.map((item) => item.id) : []),
            saved.current.id,
          ]);
          // Keep restored tracks ready but paused on page load to respect browser autoplay policy
          setIsPlaying(false);
        }
      } catch {
        localStorage.removeItem(STORAGE_KEY);
      } finally {
        restored.current = true;
      }
    }, 0);
    return () => window.clearTimeout(timer);
  }, []);

  useEffect(() => {
    if (!restored.current) return;
    const timer = window.setTimeout(() => {
      const snapshot: PersistedPlayer = {
        current,
        queue,
        queueIndex,
        currentTime,
        volume,
        isPlaying,
        queueContinuation,
        seenIds: [...seenIdsRef.current].slice(-1000),
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot));
    }, 180);
    return () => window.clearTimeout(timer);
  }, [current, currentTime, isPlaying, queue, queueContinuation, queueIndex, volume]);

  const play = useCallback((item: MediaItem, context: MediaItem[] = []) => {
    if (!item.videoId) return;
    if (audio.current) {
      audio.current.pause();
      audio.current.currentTime = 0;
    }
    const playable = context.filter((entry) => entry.videoId);
    const index = playable.findIndex((entry) => entry.id === item.id);
    const nextQueue = index >= 0 ? playable : [item];
    nextQueue.forEach((entry) => seenIdsRef.current.add(entry.id));
    resumeTime.current = 0;
    setCurrentTime(0);
    setBuffered(0);
    setQueue(nextQueue);
    setQueueIndex(index >= 0 ? index : 0);
    setQueueContinuation(null);
    setCurrent(item);
    setIsPlaying(true);
    setError(null);
    remember(item);
  }, []);

  const next = useCallback(() => {
    setQueueIndex((index) => {
      const nextIndex = index + 1;
      if (nextIndex < queue.length) {
        const item = queue[nextIndex];
        seenIdsRef.current.add(item.id);
        if (audio.current) {
          audio.current.pause();
          audio.current.currentTime = 0;
        }
        resumeTime.current = 0;
        setCurrentTime(0);
        setBuffered(0);
        setCurrent(item);
        setIsPlaying(true);
        remember(item);
        return nextIndex;
      }
      setIsPlaying(false);
      return index;
    });
  }, [queue]);

  const previous = useCallback(() => {
    if (audio.current && audio.current.currentTime > 4) {
      audio.current.currentTime = 0;
      setCurrentTime(0);
      return;
    }
    setQueueIndex((index) => {
      const previousIndex = Math.max(0, index - 1);
      const item = queue[previousIndex];
      if (item) {
        seenIdsRef.current.add(item.id);
        if (audio.current) {
          audio.current.pause();
          audio.current.currentTime = 0;
        }
        resumeTime.current = 0;
        setCurrentTime(0);
        setBuffered(0);
        setCurrent(item);
        setIsPlaying(true);
        remember(item);
      }
      return previousIndex;
    });
  }, [queue]);

  useEffect(() => {
    if (!current?.videoId) return;
    if (queueRef.current.length > 1 && queueRef.current.some((item) => item.id === current.id)) return;
    let cancelled = false;
    musicApi.next(current).then(({ items, continuation }) => {
      if (cancelled || !items.length) return;
      const fresh = items.filter((item) => item.id !== current.id && !seenIdsRef.current.has(item.id));
      const unique = [current, ...fresh];
      fresh.forEach((item) => seenIdsRef.current.add(item.id));
      setQueue(unique.filter((item, index) => unique.findIndex((other) => other.id === item.id) === index));
      setQueueIndex(0);
      setQueueContinuation(continuation || null);
    }).catch(() => undefined);
    return () => { cancelled = true; };
  }, [current]);

  const loadMoreQueue = useCallback(() => {
    if (!current || !queueContinuation || continuationLoading.current) return;
    const token = queueContinuation;
    continuationLoading.current = true;
    musicApi.next(current, token).then(({ items, continuation }) => {
      setQueue((existing) => {
        const existingIds = new Set(existing.map((item) => item.id));
        const fresh = items.filter((item) => !existingIds.has(item.id) && !seenIdsRef.current.has(item.id));
        fresh.forEach((item) => seenIdsRef.current.add(item.id));
        return [...existing, ...fresh];
      });
      setQueueContinuation(continuation || null);
    }).catch(() => setQueueContinuation(null))
      .finally(() => { continuationLoading.current = false; });
  }, [current, queueContinuation]);

  useEffect(() => {
    if (queue.length - queueIndex <= 8) loadMoreQueue();
  }, [loadMoreQueue, queue.length, queueIndex]);

  useEffect(() => {
    if (!audio.current) return;
    audio.current.volume = volume;
    if (isPlaying && current) {
      audio.current.play().catch(() => {
        setIsPlaying(false);
      });
    } else {
      audio.current.pause();
    }
  }, [current, isPlaying, volume]);

  useEffect(() => {
    const syncFullscreen = () => {
      if (!document.fullscreenElement) setFullscreenOpen(false);
    };
    document.addEventListener("fullscreenchange", syncFullscreen);
    return () => document.removeEventListener("fullscreenchange", syncFullscreen);
  }, []);

  const toggleFullscreen = useCallback(() => {
    setFullscreenOpen((open) => {
      const nextOpen = !open;
      if (nextOpen && !document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(() => undefined);
      } else if (!nextOpen && document.fullscreenElement) {
        document.exitFullscreen().catch(() => undefined);
      }
      return nextOpen;
    });
  }, []);

  const value = useMemo<PlayerContextValue>(() => ({
    current,
    queue,
    queueIndex,
    isPlaying,
    queueOpen,
    fullscreenOpen,
    currentTime,
    duration,
    buffered,
    volume,
    error,
    play,
    toggle: () => {
      setError(null);
      setIsPlaying((playing) => !playing);
    },
    next,
    previous,
    seek: (time) => {
      setError(null);
      const safeTime = Math.max(0, Math.min(duration || time, time));
      resumeTime.current = safeTime;
      if (audio.current) audio.current.currentTime = safeTime;
      setCurrentTime(safeTime);
    },
    setVolume: (nextVolume) => setVolumeState(Math.max(0, Math.min(1, nextVolume))),
    setQueueOpen,
    toggleFullscreen,
    loadMoreQueue,
    moveQueueItem: (from, to) => setQueue((items) => {
      if (from === queueIndex || to < 0 || to >= items.length) return items;
      const copy = [...items];
      const [moved] = copy.splice(from, 1);
      copy.splice(to, 0, moved);
      return copy;
    }),
  }), [buffered, current, currentTime, duration, error, fullscreenOpen, isPlaying, loadMoreQueue, next, play, previous, queue, queueIndex, queueOpen, toggleFullscreen, volume]);

  return (
    <PlayerContext.Provider value={value}>
      {children}
      <audio
        ref={audio}
        src={current?.videoId ? `${API_URL}/api/stream/${current.videoId}` : undefined}
        onLoadedMetadata={(event) => {
          const media = event.currentTarget;
          const restoredTime = Math.min(resumeTime.current, Number.isFinite(media.duration) ? Math.max(0, media.duration - 0.25) : resumeTime.current);
          if (restoredTime > 0) media.currentTime = restoredTime;
          setDuration(Number.isFinite(media.duration) ? media.duration : 0);
        }}
        onTimeUpdate={(event) => setCurrentTime(event.currentTarget.currentTime)}
        onDurationChange={(event) => setDuration(Number.isFinite(event.currentTarget.duration) ? event.currentTarget.duration : 0)}
        onProgress={(event) => {
          const media = event.currentTarget;
          if (media.buffered.length && Number.isFinite(media.duration) && media.duration > 0) {
            setBuffered(media.buffered.end(media.buffered.length - 1));
          }
        }}
        onEnded={next}
        onError={() => {
          if (current) setError("This track could not be played. Try another result.");
          setIsPlaying(false);
        }}
        preload="auto"
      />
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const context = useContext(PlayerContext);
  if (!context) throw new Error("usePlayer must be used inside PlayerProvider");
  return context;
}
