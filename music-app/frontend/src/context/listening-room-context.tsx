"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import type { MediaItem } from "@/lib/types";
import { useAuth } from "@/context/auth-context";
import { usePlayer, type PlayerSnapshot } from "@/context/player-context";

export type ListeningRoom = { id: string; code: string; name: string; host_id: string; playback_state?: PlayerSnapshot; revision: number };
export type RoomMember = { userId: string; name: string; avatarUrl: string | null; online: boolean; role: string };
export type RoomReaction = { message_id: string; user_id: string; emoji: string };
export type RoomMessage = {
  id: string; room_id: string; sender_id: string; body: string; reply_to: string | null;
  song: MediaItem | null; created_at: string; senderName?: string; reactions: RoomReaction[];
};

type ListeningRoomContextValue = {
  room: ListeningRoom | null; members: RoomMember[]; messages: RoomMessage[]; connected: boolean; busy: boolean; error: string | null;
  createRoom: (name?: string) => Promise<boolean>; joinRoom: (code: string) => Promise<boolean>; leaveRoom: () => Promise<void>;
  sendMessage: (body: string, replyTo?: string | null, song?: MediaItem | null) => Promise<boolean>;
  toggleReaction: (messageId: string, emoji: string) => Promise<void>;
};

const ListeningRoomContext = createContext<ListeningRoomContextValue | null>(null);
const createId = () => typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;

function significantChange(a: PlayerSnapshot | null, b: PlayerSnapshot) {
  if (!a) return true;
  return a.current?.id !== b.current?.id || a.queueIndex !== b.queueIndex || a.isPlaying !== b.isPlaying ||
    Math.abs(a.volume - b.volume) > .02 || Math.abs(a.currentTime - b.currentTime) > 2.25;
}

async function enableRoomNotifications() {
  if (typeof Notification !== "undefined" && Notification.permission === "default") {
    try { await Notification.requestPermission(); } catch { /* browser may block permission prompts */ }
  }
}

export function ListeningRoomProvider({ children }: { children: ReactNode }) {
  const { user, session, displayName } = useAuth();
  const player = usePlayer();
  const playerRef = useRef(player); const channelRef = useRef<RealtimeChannel | null>(null);
  const roomRef = useRef<ListeningRoom | null>(null); const controllerRef = useRef<string | null>(null);
  const suppressUntilRef = useRef(0); const lastSnapshotRef = useRef<PlayerSnapshot | null>(null); const revisionRef = useRef(0);
  const knownMessageIdsRef = useRef<Set<string>>(new Set()); const messagesReadyRef = useRef(false);
  const [clientId] = useState(createId); const [room, setRoom] = useState<ListeningRoom | null>(null);
  const [members, setMembers] = useState<RoomMember[]>([]); const [messages, setMessages] = useState<RoomMessage[]>([]);
  const [connected, setConnected] = useState(false); const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null);
  useEffect(() => { playerRef.current = player; }, [player]);
  useEffect(() => { roomRef.current = room; }, [room]);

  const refreshMembers = useCallback(async (roomId: string, onlineIds = new Set<string>()) => {
    const { data: rows } = await supabase.from("room_members").select("user_id,role").eq("room_id", roomId);
    const ids = (rows || []).map((row) => row.user_id as string);
    const { data: profiles } = ids.length ? await supabase.from("profiles").select("id,display_name,avatar_url").in("id", ids) : { data: [] };
    const profileMap = new Map((profiles || []).map((profile) => [profile.id as string, profile]));
    setMembers((rows || []).map((row) => { const profile = profileMap.get(row.user_id as string); return {
      userId: row.user_id as string, role: row.role as string, online: onlineIds.has(row.user_id as string),
      name: String(profile?.display_name || (row.user_id === user?.id ? displayName : "Listener")), avatarUrl: profile?.avatar_url as string | null,
    }; }));
  }, [displayName, user?.id]);

  const refreshMessages = useCallback(async (roomId: string) => {
    const { data: rows, error: fetchError } = await supabase.from("room_messages").select("id,room_id,sender_id,body,reply_to,song,created_at").eq("room_id", roomId).order("created_at", { ascending: true }).limit(200);
    if (fetchError) { setError(fetchError.message); return; }
    const ids = [...new Set((rows || []).map((row) => row.sender_id as string))];
    const messageIds = (rows || []).map((row) => row.id as string);
    const [{ data: profiles }, { data: reactions }] = await Promise.all([
      ids.length ? supabase.from("profiles").select("id,display_name").in("id", ids) : Promise.resolve({ data: [] }),
      messageIds.length ? supabase.from("message_reactions").select("message_id,user_id,emoji").in("message_id", messageIds) : Promise.resolve({ data: [] }),
    ]);
    const names = new Map((profiles || []).map((profile) => [profile.id as string, String(profile.display_name || "Listener")]));
    const nextMessages = (rows || []).map((row) => ({ ...row, song: row.song as MediaItem | null, senderName: names.get(row.sender_id as string) || (row.sender_id === user?.id ? displayName : "Listener"), reactions: (reactions || []).filter((reaction) => reaction.message_id === row.id) })) as RoomMessage[];
    const fresh = messagesReadyRef.current ? nextMessages.filter((message) => !knownMessageIdsRef.current.has(message.id) && message.sender_id !== user?.id) : [];
    knownMessageIdsRef.current = new Set(nextMessages.map((message) => message.id)); messagesReadyRef.current = true; setMessages(nextMessages);
    const newest = fresh.at(-1);
    if (newest) {
      const detail = { title: newest.senderName || "InnerWave room", body: newest.song ? `🎵 ${newest.song.title}` : newest.body, roomId };
      if (document.hidden && typeof Notification !== "undefined" && Notification.permission === "granted") new Notification(detail.title, { body: detail.body, icon: newest.song?.thumbnail || "/favicon.ico", tag: `room-${roomId}` });
      else window.dispatchEvent(new CustomEvent("innerwave-room-notification", { detail }));
    }
  }, [displayName, user?.id]);

  const detach = useCallback(async () => {
    const channel = channelRef.current; channelRef.current = null; setConnected(false); setMembers([]); setMessages([]);
    if (channel) await supabase.removeChannel(channel);
  }, []);

  const attach = useCallback(async (nextRoom: ListeningRoom) => {
    await detach(); knownMessageIdsRef.current.clear(); messagesReadyRef.current = false; setRoom(nextRoom); roomRef.current = nextRoom; revisionRef.current = Number(nextRoom.revision || 0);
    controllerRef.current = nextRoom.host_id === user?.id ? clientId : null;
    if (nextRoom.playback_state?.current) { suppressUntilRef.current = Date.now() + 1200; playerRef.current.applyRemoteSnapshot(nextRoom.playback_state, true); lastSnapshotRef.current = nextRoom.playback_state; }
    await Promise.all([refreshMessages(nextRoom.id), refreshMembers(nextRoom.id)]);
    if (!session || !user) return;
    await supabase.realtime.setAuth(session.access_token);
    const channel = supabase.channel(`room:${nextRoom.id}`, { config: { private: true, presence: { key: clientId } } }); channelRef.current = channel;
    const refreshAll = () => { void refreshMessages(nextRoom.id); };
    channel.on("presence", { event: "sync" }, () => {
      const online = new Set<string>(); Object.values(channel.presenceState<{ userId: string }>()).flat().forEach((entry) => { if (entry.userId) online.add(entry.userId); });
      void refreshMembers(nextRoom.id, online);
    }).on("broadcast", { event: "playback" }, ({ payload }: { payload: { origin: string; userId: string; revision: number; snapshot: PlayerSnapshot } }) => {
      if (payload.origin === clientId || payload.revision <= revisionRef.current) return;
      revisionRef.current = payload.revision; controllerRef.current = payload.origin; suppressUntilRef.current = Date.now() + 900;
      lastSnapshotRef.current = payload.snapshot; playerRef.current.applyRemoteSnapshot(payload.snapshot, true);
    }).on("postgres_changes", { event: "*", schema: "public", table: "room_messages", filter: `room_id=eq.${nextRoom.id}` }, refreshAll)
      .on("postgres_changes", { event: "*", schema: "public", table: "message_reactions" }, refreshAll)
      .on("postgres_changes", { event: "*", schema: "public", table: "room_members", filter: `room_id=eq.${nextRoom.id}` }, () => void refreshMembers(nextRoom.id));
    channel.subscribe(async (status) => { const ready = status === "SUBSCRIBED"; setConnected(ready); if (ready) await channel.track({ userId: user.id, name: displayName, clientId }); });
  }, [clientId, detach, displayName, refreshMembers, refreshMessages, session, user]);

  useEffect(() => () => { void detach(); }, [detach]);
  useEffect(() => {
    if (!room || !user) return;
    const timer = window.setInterval(() => {
      const current = { ...playerRef.current.snapshot, capturedAt: Date.now() };
      if (Date.now() >= suppressUntilRef.current && significantChange(lastSnapshotRef.current, current)) controllerRef.current = clientId;
      const controls = controllerRef.current === clientId;
      lastSnapshotRef.current = current;
      if (!controls || !channelRef.current) return;
      const revision = Math.max(++revisionRef.current, Date.now()); revisionRef.current = revision;
      void channelRef.current.send({ type: "broadcast", event: "playback", payload: { origin: clientId, userId: user.id, revision, snapshot: current } });
    }, 500);
    const persist = window.setInterval(() => { if (controllerRef.current === clientId && roomRef.current) void supabase.from("listening_rooms").update({ playback_state: playerRef.current.snapshot, revision: revisionRef.current, updated_at: new Date().toISOString() }).eq("id", roomRef.current.id); }, 5000);
    return () => { window.clearInterval(timer); window.clearInterval(persist); };
  }, [clientId, room, user]);

  const createRoom = useCallback(async (name = "Listening room") => { void enableRoomNotifications(); setBusy(true); setError(null); const { data, error: rpcError } = await supabase.rpc("create_listening_room", { p_name: name }); setBusy(false); if (rpcError || !data) { setError(rpcError?.message || "Could not create room"); return false; } await attach(data as ListeningRoom); return true; }, [attach]);
  const joinRoom = useCallback(async (code: string) => { void enableRoomNotifications(); setBusy(true); setError(null); const { data, error: rpcError } = await supabase.rpc("join_listening_room", { p_code: code.trim().toUpperCase() }); setBusy(false); if (rpcError || !data) { setError(rpcError?.message || "Could not join room"); return false; } await attach(data as ListeningRoom); return true; }, [attach]);
  const leaveRoom = useCallback(async () => { const active = roomRef.current; await detach(); if (active && user) await supabase.from("room_members").delete().eq("room_id", active.id).eq("user_id", user.id); setRoom(null); roomRef.current = null; }, [detach, user]);
  const sendMessage = useCallback(async (body: string, replyTo: string | null = null, song: MediaItem | null = null) => { if (!room || !user || (!body.trim() && !song)) return false; const { error: sendError } = await supabase.from("room_messages").insert({ room_id: room.id, sender_id: user.id, body: body.trim(), reply_to: replyTo, song }); if (sendError) { setError(sendError.message); return false; } await refreshMessages(room.id); return true; }, [refreshMessages, room, user]);
  const toggleReaction = useCallback(async (messageId: string, emoji: string) => { if (!user || !room) return; const exists = messages.some((message) => message.id === messageId && message.reactions.some((reaction) => reaction.user_id === user.id && reaction.emoji === emoji)); if (exists) await supabase.from("message_reactions").delete().eq("message_id", messageId).eq("user_id", user.id).eq("emoji", emoji); else await supabase.from("message_reactions").insert({ message_id: messageId, user_id: user.id, emoji }); await refreshMessages(room.id); }, [messages, refreshMessages, room, user]);
  const value = useMemo(() => ({ room, members, messages, connected, busy, error, createRoom, joinRoom, leaveRoom, sendMessage, toggleReaction }), [busy, connected, createRoom, error, joinRoom, leaveRoom, members, messages, room, sendMessage, toggleReaction]);
  return <ListeningRoomContext.Provider value={value}>{children}</ListeningRoomContext.Provider>;
}

export function useListeningRoom() { const value = useContext(ListeningRoomContext); if (!value) throw new Error("useListeningRoom must be used inside ListeningRoomProvider"); return value; }
