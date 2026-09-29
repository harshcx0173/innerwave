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
import { musicApi } from "@/lib/api";
import type { MediaItem } from "@/lib/types";
import { YoutubeTransport, type YoutubeTransportHandle } from "@/components/youtube-transport";

export type PlayerSnapshot = {
  current: MediaItem | null;
  queue: MediaItem[];
  queueIndex: number;
  currentTime: number;
  duration: number;
  volume: number;
  isPlaying: boolean;
  queueContinuation: string | null;
  capturedAt: number;
};

export type PlayerCommand =
  | { action: "play"; item: MediaItem; context?: MediaItem[] }
  | { action: "toggle" }
  | { action: "next" }
  | { action: "previous" }
  | { action: "seek"; time: number }
  | { action: "volume"; volume: number }
  | { action: "moveQueueItem"; from: number; to: number };

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
  snapshot: PlayerSnapshot;
  setCommandInterceptor: (interceptor: ((command: PlayerCommand) => boolean) | null) => void;
  applyRemoteCommand: (command: PlayerCommand) => void;
  applyRemoteSnapshot: (snapshot: PlayerSnapshot, playLocally: boolean) => void;
  setLocalPlaybackEnabled: (enabled: boolean) => void;
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
  const transport = useRef<YoutubeTransportHandle>(null);
  const continuationLoading = useRef(false);
  const restored = useRef(false);
  const resumeTime = useRef(0);
  const autoplayOnLoad = useRef(false);
  const queueRef = useRef<MediaItem[]>([]);
  const seenIdsRef = useRef<Set<string>>(new Set());
  const commandInterceptorRef = useRef<((command: PlayerCommand) => boolean) | null>(null);
  const localPlaybackEnabledRef = useRef(true);
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

  const playLocal = useCallback((item: MediaItem, context: MediaItem[] = []) => {
    if (!item.videoId) return;
    transport.current?.stop();
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
    autoplayOnLoad.current = true;
    setCurrent(item);
    setIsPlaying(true);
    setError(null);
    remember(item);
  }, []);

  const nextLocal = useCallback(() => {
    setQueueIndex((index) => {
      const nextIndex = index + 1;
      if (nextIndex < queue.length) {
        const item = queue[nextIndex];
        seenIdsRef.current.add(item.id);
        transport.current?.stop();
        resumeTime.current = 0;
        setCurrentTime(0);
        setBuffered(0);
        autoplayOnLoad.current = true;
        setCurrent(item);
        setIsPlaying(true);
        remember(item);
        return nextIndex;
      }
      setIsPlaying(false);
      return index;
    });
  }, [queue]);

  const previousLocal = useCallback(() => {
    if (currentTime > 4) {
      transport.current?.seek(0);
      setCurrentTime(0);
      return;
    }
    setQueueIndex((index) => {
      const previousIndex = Math.max(0, index - 1);
      const item = queue[previousIndex];
      if (item) {
        seenIdsRef.current.add(item.id);
        transport.current?.stop();
        resumeTime.current = 0;
        setCurrentTime(0);
        setBuffered(0);
        autoplayOnLoad.current = true;
        setCurrent(item);
        setIsPlaying(true);
        remember(item);
      }
      return previousIndex;
    });
  }, [currentTime, queue]);

  const seekLocal = useCallback((time: number) => {
    setError(null);
    const safeTime = Math.max(0, Math.min(duration || time, time));
    resumeTime.current = safeTime;
    if (localPlaybackEnabledRef.current) transport.current?.seek(safeTime);
    setCurrentTime(safeTime);
  }, [duration]);

  const volumeLocal = useCallback((nextVolume: number) => {
    setVolumeState(Math.max(0, Math.min(1, nextVolume)));
  }, []);

  const moveQueueItemLocal = useCallback((from: number, to: number) => {
    setQueue((items) => {
      if (from === queueIndex || to < 0 || to >= items.length) return items;
      const copy = [...items];
      const [moved] = copy.splice(from, 1);
      copy.splice(to, 0, moved);
      return copy;
    });
  }, [queueIndex]);

  const runCommand = useCallback((command: PlayerCommand) => {
    if (command.action === "play") playLocal(command.item, command.context);
    else if (command.action === "toggle") { setError(null); setIsPlaying((playing) => !playing); }
    else if (command.action === "next") nextLocal();
    else if (command.action === "previous") previousLocal();
    else if (command.action === "seek") seekLocal(command.time);
    else if (command.action === "volume") volumeLocal(command.volume);
    else if (command.action === "moveQueueItem") moveQueueItemLocal(command.from, command.to);
  }, [moveQueueItemLocal, nextLocal, playLocal, previousLocal, seekLocal, volumeLocal]);

  const dispatchCommand = useCallback((command: PlayerCommand) => {
    if (commandInterceptorRef.current?.(command)) return;
    runCommand(command);
  }, [runCommand]);

  useEffect(() => {
    if (!current?.videoId) return;
    if (!localPlaybackEnabledRef.current) return;
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
    if (!localPlaybackEnabledRef.current) return;
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
    transport.current?.setVolume(volume);
    if (!localPlaybackEnabledRef.current) {
      transport.current?.pause();
    } else if (isPlaying && current) {
      transport.current?.play();
    } else {
      transport.current?.pause();
    }
  }, [current, isPlaying, volume]);

  useEffect(() => {
    if (!current?.videoId || !localPlaybackEnabledRef.current) return;
    transport.current?.load(current.videoId, resumeTime.current, autoplayOnLoad.current);
    autoplayOnLoad.current = false;
  }, [current?.videoId]);

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

  const snapshot = useMemo<PlayerSnapshot>(() => ({
    current,
    queue,
    queueIndex,
    currentTime,
    duration,
    volume,
    isPlaying,
    queueContinuation,
    capturedAt: 0,
  }), [current, currentTime, duration, isPlaying, queue, queueContinuation, queueIndex, volume]);

  const applyRemoteSnapshot = useCallback((next: PlayerSnapshot, playLocally: boolean) => {
    localPlaybackEnabledRef.current = playLocally;
    const elapsed = next.isPlaying ? Math.max(0, (Date.now() - Number(next.capturedAt || Date.now())) / 1000) : 0;
    const nextTime = Math.max(0, Number(next.currentTime || 0) + elapsed);
    if (!playLocally) transport.current?.pause();
    if (playLocally && next.current?.videoId !== current?.videoId) transport.current?.stop();
    resumeTime.current = nextTime;
    autoplayOnLoad.current = playLocally && next.isPlaying;
    setCurrent(next.current);
    setQueue(Array.isArray(next.queue) ? next.queue : []);
    setQueueIndex(Math.max(0, Number(next.queueIndex) || 0));
    setCurrentTime(nextTime);
    setDuration(Math.max(0, Number(next.duration) || 0));
    setVolumeState(Math.max(0, Math.min(1, Number(next.volume) || 0)));
    setIsPlaying(Boolean(next.isPlaying));
    setQueueContinuation(next.queueContinuation || null);
    seenIdsRef.current = new Set((next.queue || []).map((item) => item.id));
    if (playLocally && next.current?.videoId === current?.videoId) {
      transport.current?.seek(nextTime);
      transport.current?.setVolume(Math.max(0, Math.min(1, Number(next.volume) || 0)));
      if (next.isPlaying) transport.current?.play();
      else transport.current?.pause();
    }
  }, [current?.videoId]);

  const setLocalPlaybackEnabled = useCallback((enabled: boolean) => {
    localPlaybackEnabledRef.current = enabled;
    if (!enabled) transport.current?.pause();
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
    play: (item, context) => dispatchCommand({ action: "play", item, context }),
    toggle: () => dispatchCommand({ action: "toggle" }),
    next: () => dispatchCommand({ action: "next" }),
    previous: () => dispatchCommand({ action: "previous" }),
    seek: (time) => dispatchCommand({ action: "seek", time }),
    setVolume: (nextVolume) => dispatchCommand({ action: "volume", volume: nextVolume }),
    setQueueOpen,
    toggleFullscreen,
    loadMoreQueue,
    moveQueueItem: (from, to) => dispatchCommand({ action: "moveQueueItem", from, to }),
    snapshot,
    setCommandInterceptor: (interceptor) => { commandInterceptorRef.current = interceptor; },
    applyRemoteCommand: runCommand,
    applyRemoteSnapshot,
    setLocalPlaybackEnabled,
  }), [applyRemoteSnapshot, buffered, current, currentTime, dispatchCommand, duration, error, fullscreenOpen, isPlaying, loadMoreQueue, queue, queueIndex, queueOpen, runCommand, setLocalPlaybackEnabled, snapshot, toggleFullscreen, volume]);

  return (
    <PlayerContext.Provider value={value}>
      {children}
      <YoutubeTransport
        ref={transport}
        onTime={(time, nextDuration, nextBuffered) => {
          setCurrentTime(time);
          setDuration(nextDuration);
          setBuffered(nextBuffered);
        }}
        onPlayingChange={(playing) => { if (localPlaybackEnabledRef.current) setIsPlaying(playing); }}
        onEnded={() => runCommand({ action: "next" })}
        onError={(message) => {
          setError(message);
          setIsPlaying(false);
        }}
      />
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const context = useContext(PlayerContext);
  if (!context) throw new Error("usePlayer must be used inside PlayerProvider");
  return context;
}
