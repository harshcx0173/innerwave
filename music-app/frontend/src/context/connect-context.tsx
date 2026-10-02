"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/context/auth-context";
import { usePlayer, type PlayerCommand, type PlayerSnapshot } from "@/context/player-context";

export type PlaybackDevice = { id: string; name: string; platform: string; onlineAt: string };

type ConnectContextValue = {
  connected: boolean;
  devices: PlaybackDevice[];
  deviceId: string;
  activeDeviceId: string | null;
  isActiveDevice: boolean;
  activateDevice: (deviceId: string) => Promise<void>;
};

type StatePayload = { origin: string; activeDeviceId: string; snapshot: PlayerSnapshot; revision: number };
type CommandPayload = { id: string; origin: string; target: string; command: PlayerCommand };

const DEVICE_KEY = "innerwave-device-id";
const ConnectContext = createContext<ConnectContextValue | null>(null);

function createId() {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function getDeviceName() {
  const platform = navigator.userAgent.includes("Windows") ? "Windows" : navigator.userAgent.includes("Mac") ? "macOS" : "Web";
  return { name: `Web • ${platform}`, platform };
}

export function ConnectProvider({ children }: { children: ReactNode }) {
  const { session, user } = useAuth();
  const player = usePlayer();
  const playerRef = useRef(player);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const activeRef = useRef<string | null>(null);
  const revisionRef = useRef(0);
  const presenceReclaimTimerRef = useRef<number | null>(null);
  const [connected, setConnected] = useState(false);
  const [devices, setDevices] = useState<PlaybackDevice[]>([]);
  const [activeDeviceId, setActiveDeviceId] = useState<string | null>(null);
  const [deviceId] = useState(() => {
    const saved = localStorage.getItem(DEVICE_KEY);
    const id = saved || createId();
    if (!saved) localStorage.setItem(DEVICE_KEY, id);
    return id;
  });

  useEffect(() => { playerRef.current = player; }, [player]);

  const sendState = useCallback(async (persist: boolean) => {
    if (!user || activeRef.current !== deviceId) return;
    const snapshot = { ...playerRef.current.snapshot, capturedAt: Date.now() };
    const revision = ++revisionRef.current;
    await channelRef.current?.send({ type: "broadcast", event: "state", payload: { origin: deviceId, activeDeviceId: deviceId, snapshot, revision } satisfies StatePayload });
    if (persist) {
      await supabase.from("playback_sessions").upsert({ user_id: user.id, active_device_id: deviceId, state: snapshot, revision, updated_at: new Date().toISOString() });
    }
  }, [deviceId, user]);

  const activateDevice = useCallback(async (targetId: string) => {
    if (!user || !targetId) return;
    const snapshot = { ...playerRef.current.snapshot, capturedAt: Date.now() };
    const revision = ++revisionRef.current;
    activeRef.current = targetId;
    setActiveDeviceId(targetId);
    if (targetId === deviceId) playerRef.current.applyRemoteSnapshot(snapshot, true);
    else playerRef.current.setLocalPlaybackEnabled(false);
    await supabase.from("playback_sessions").upsert({ user_id: user.id, active_device_id: targetId, state: snapshot, revision, updated_at: new Date().toISOString() });
    await channelRef.current?.send({ type: "broadcast", event: "active_device", payload: { origin: deviceId, activeDeviceId: targetId, snapshot, revision } satisfies StatePayload });
  }, [deviceId, user]);

  useEffect(() => {
    if (!user || !session) return;
    let cancelled = false;
    const topic = `innerwave:${user.id}:playback`;
    const device = { id: deviceId, ...getDeviceName(), onlineAt: new Date().toISOString() };
    const channel = supabase.channel(topic, { config: { private: true, presence: { key: deviceId } } });
    channelRef.current = channel;

    channel
      .on("presence", { event: "sync" }, () => {
        const state = channel.presenceState<PlaybackDevice>();
        const unique = new Map<string, PlaybackDevice>();
        Object.values(state).flat().forEach((entry) => {
          const value = entry as unknown as PlaybackDevice;
          if (value.id) unique.set(value.id, value);
        });
        setDevices([...unique.values()]);
        const active = activeRef.current;
        if (presenceReclaimTimerRef.current) window.clearTimeout(presenceReclaimTimerRef.current);
        if (unique.has(deviceId) && (!active || !unique.has(active))) {
          presenceReclaimTimerRef.current = window.setTimeout(() => {
            const latest = channel.presenceState<PlaybackDevice>();
            const onlineIds = new Set(
              Object.values(latest).flat().map((entry) => (entry as unknown as PlaybackDevice).id).filter(Boolean),
            );
            const elected = [...onlineIds].sort()[0];
            const latestActive = activeRef.current;
            if (elected === deviceId && (!latestActive || !onlineIds.has(latestActive))) {
              void activateDevice(deviceId);
            }
          }, 800);
        }
      })
      .on("broadcast", { event: "command" }, ({ payload }: { payload: CommandPayload }) => {
        if (payload.origin === deviceId || payload.target !== deviceId || activeRef.current !== deviceId) return;
        playerRef.current.applyRemoteCommand(payload.command);
        window.setTimeout(() => void sendState(true), 250);
      })
      .on("broadcast", { event: "state" }, ({ payload }: { payload: StatePayload }) => {
        if (payload.origin === deviceId || payload.origin !== payload.activeDeviceId) return;
        if (activeRef.current && payload.activeDeviceId !== activeRef.current) return;
        if (payload.revision <= revisionRef.current) return;
        revisionRef.current = payload.revision;
        if (!activeRef.current) activeRef.current = payload.activeDeviceId;
        setActiveDeviceId(payload.activeDeviceId);
        playerRef.current.applyRemoteSnapshot(payload.snapshot, false);
      })
      .on("broadcast", { event: "active_device" }, ({ payload }: { payload: StatePayload }) => {
        if (payload.revision <= revisionRef.current) return;
        revisionRef.current = payload.revision;
        activeRef.current = payload.activeDeviceId;
        setActiveDeviceId(payload.activeDeviceId);
        playerRef.current.applyRemoteSnapshot(payload.snapshot, payload.activeDeviceId === deviceId);
      });

    void (async () => {
      await supabase.realtime.setAuth(session.access_token);
      const { data } = await supabase.from("playback_sessions").select("active_device_id,state,revision").eq("user_id", user.id).maybeSingle();
      if (cancelled) return;
      const active = data?.active_device_id as string | null;
      activeRef.current = active;
      revisionRef.current = Number(data?.revision || 0);
      setActiveDeviceId(active);
      if (data?.state && Object.keys(data.state).length) playerRef.current.applyRemoteSnapshot(data.state as PlayerSnapshot, !active || active === deviceId);
      else playerRef.current.setLocalPlaybackEnabled(!active || active === deviceId);
      channel.subscribe(async (status) => {
        const ready = status === "SUBSCRIBED";
        setConnected(ready);
        if (!ready) return;
        await channel.track(device);
      });
    })();

    playerRef.current.setCommandInterceptor((command) => {
      const target = activeRef.current;
      if (!target || target === deviceId) return false;
      void channel.send({ type: "broadcast", event: "command", payload: { id: createId(), origin: deviceId, target, command } satisfies CommandPayload });
      return true;
    });

    return () => {
      cancelled = true;
      if (presenceReclaimTimerRef.current) window.clearTimeout(presenceReclaimTimerRef.current);
      presenceReclaimTimerRef.current = null;
      playerRef.current.setCommandInterceptor(null);
      setConnected(false);
      channelRef.current = null;
      void supabase.removeChannel(channel);
    };
  }, [activateDevice, deviceId, sendState, session, user]);

  useEffect(() => {
    const broadcast = window.setInterval(() => void sendState(false), 1000);
    const persist = window.setInterval(() => void sendState(true), 5000);
    return () => { window.clearInterval(broadcast); window.clearInterval(persist); };
  }, [sendState]);

  const value = useMemo<ConnectContextValue>(() => ({ connected, devices, deviceId, activeDeviceId, isActiveDevice: activeDeviceId === deviceId, activateDevice }), [activateDevice, activeDeviceId, connected, deviceId, devices]);
  return <ConnectContext.Provider value={value}>{children}</ConnectContext.Provider>;
}

export function useConnect() {
  const context = useContext(ConnectContext);
  if (!context) throw new Error("useConnect must be used inside ConnectProvider");
  return context;
}
