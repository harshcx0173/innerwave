"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase } from "@/lib/supabase";
import type { MediaItem } from "@/lib/types";
import { useAuth } from "@/context/auth-context";
import { usePlayer, type PlayerSnapshot, type PlayerCommand } from "@/context/player-context";

export type ListeningRoom = {
  id: string;
  code: string;
  name: string;
  host_id: string;
  playback_state?: PlayerSnapshot & { roomQueue?: QueuedRoomSong[] };
  revision: number;
};
export type RoomMember = { userId: string; name: string; avatarUrl: string | null; online: boolean; role: string };
export type RoomReaction = { message_id: string; user_id: string; emoji: string };
export type RoomMessage = {
  id: string; room_id: string; sender_id: string; body: string; reply_to: string | null;
  song: MediaItem | null; created_at: string; senderName?: string; reactions: RoomReaction[];
};
export type RoomHistoryItem = { id?: string; code: string; name: string; timestamp: string };
export type QueuedRoomSong = {
  id: string;
  song: MediaItem;
  addedBy: { id: string; name: string };
  votes: string[];
  addedAt: string;
};

type ListeningRoomContextValue = {
  room: ListeningRoom | null; members: RoomMember[]; messages: RoomMessage[]; connected: boolean; busy: boolean; error: string | null;
  isHost: boolean; isInRoom: boolean; isLive: boolean; goLive: () => void; pauseListener: () => void;
  createRoom: (name?: string) => Promise<boolean>; joinRoom: (code: string) => Promise<boolean>; leaveRoom: () => Promise<void>;
  sendMessage: (body: string, replyTo?: string | null, song?: MediaItem | null) => Promise<boolean>;
  toggleReaction: (messageId: string, emoji: string) => Promise<void>;
  joinedRoomsHistory: RoomHistoryItem[];
  createdRoomsHistory: RoomHistoryItem[];
  roomQueue: QueuedRoomSong[];
  addToRoomQueue: (song: MediaItem) => void;
  voteSong: (queueItemId: string) => void;
  playQueuedSong: (queueItemId: string) => void;
  removeFromRoomQueue: (queueItemId: string) => void;
  requestPlaySong: (song: MediaItem, context?: MediaItem[]) => void;
};

const ListeningRoomContext = createContext<ListeningRoomContextValue | null>(null);
const createId = () => typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;

function getStoredHistory(key: string): RoomHistoryItem[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

function saveHistoryItem(key: string, item: RoomHistoryItem): RoomHistoryItem[] {
  if (typeof window === "undefined") return [];
  try {
    const current = getStoredHistory(key);
    const filtered = current.filter((r) => r.code !== item.code);
    const updated = [item, ...filtered].slice(0, 30);
    localStorage.setItem(key, JSON.stringify(updated));
    return updated;
  } catch {
    return [];
  }
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
  const latestHostSnapshotRef = useRef<PlayerSnapshot | null>(null);
  const [clientId] = useState(createId); const [room, setRoom] = useState<ListeningRoom | null>(null);
  const [members, setMembers] = useState<RoomMember[]>([]); const [messages, setMessages] = useState<RoomMessage[]>([]);
  const [connected, setConnected] = useState(false); const [busy, setBusy] = useState(false); const [error, setError] = useState<string | null>(null);
  const [isLive, setIsLive] = useState(true);
  const [createdRoomsHistory, setCreatedRoomsHistory] = useState<RoomHistoryItem[]>([]);
  const [joinedRoomsHistory, setJoinedRoomsHistory] = useState<RoomHistoryItem[]>([]);
  const [roomQueue, setRoomQueue] = useState<QueuedRoomSong[]>([]);
  const roomQueueRef = useRef<QueuedRoomSong[]>([]);
  const isLiveRef = useRef(true);
  const hasRestoredRef = useRef(false);

  useEffect(() => { roomQueueRef.current = roomQueue; }, [roomQueue]);
  useEffect(() => { isLiveRef.current = isLive; }, [isLive]);
  useEffect(() => { playerRef.current = player; }, [player]);
  useEffect(() => { roomRef.current = room; }, [room]);

  const isHost = Boolean(room && user && room.host_id === user.id);
  const isInRoom = Boolean(room);

  // Sync / load rooms history for authenticated user
  useEffect(() => {
    let isMounted = true;
    if (!user) {
      queueMicrotask(() => {
        if (isMounted) {
          setCreatedRoomsHistory([]);
          setJoinedRoomsHistory([]);
        }
      });
      return () => { isMounted = false; };
    }
    const createdKey = `innerwave-created-rooms:${user.id}`;
    const joinedKey = `innerwave-joined-rooms:${user.id}`;
    queueMicrotask(() => {
      if (isMounted) {
        setCreatedRoomsHistory(getStoredHistory(createdKey));
        setJoinedRoomsHistory(getStoredHistory(joinedKey));
      }
    });

    void supabase
      .from("listening_rooms")
      .select("id, code, name, created_at")
      .eq("host_id", user.id)
      .order("created_at", { ascending: false })
      .limit(30)
      .then(({ data: dbRooms }) => {
        if (!isMounted || !dbRooms || dbRooms.length === 0) return;
        setCreatedRoomsHistory((current) => {
          const map = new Map<string, RoomHistoryItem>();
          current.forEach((item) => map.set(item.code, item));
          dbRooms.forEach((r) => {
            if (!map.has(r.code)) {
              map.set(r.code, {
                id: r.id,
                code: r.code,
                name: r.name,
                timestamp: r.created_at,
              });
            }
          });
          const merged = Array.from(map.values())
            .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
            .slice(0, 30);
          try {
            localStorage.setItem(createdKey, JSON.stringify(merged));
          } catch { /* ignore */ }
          return merged;
        });
      });
    return () => { isMounted = false; };
  }, [user]);

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
      const detail = { title: newest.senderName || "InnerWave room", body: newest.song ? `🎵 ${newest.song!.title}` : newest.body, roomId, count: fresh.length };
      if (document.hidden && typeof Notification !== "undefined" && Notification.permission === "granted") new Notification(detail.title, { body: detail.body, icon: newest.song?.thumbnail || "/favicon.ico", tag: `room-${roomId}` });
      else window.dispatchEvent(new CustomEvent("innerwave-room-notification", { detail }));
    }
  }, [displayName, user?.id]);

  const detach = useCallback(async () => {
    const channel = channelRef.current; channelRef.current = null; setConnected(false); setMembers([]); setMessages([]);
    setRoomQueue([]); roomQueueRef.current = [];
    latestHostSnapshotRef.current = null; setIsLive(true); isLiveRef.current = true;
    if (channel) await supabase.removeChannel(channel);
  }, []);

  const attach = useCallback(async (nextRoom: ListeningRoom) => {
    await detach(); knownMessageIdsRef.current.clear(); messagesReadyRef.current = false; setRoom(nextRoom); roomRef.current = nextRoom; revisionRef.current = Number(nextRoom.revision || 0);
    controllerRef.current = nextRoom.host_id === user?.id ? clientId : null;
    setIsLive(true); isLiveRef.current = true;
    latestHostSnapshotRef.current = nextRoom.playback_state || null;
    const initialQueue = Array.isArray(nextRoom.playback_state?.roomQueue) ? nextRoom.playback_state.roomQueue : [];
    setRoomQueue(initialQueue); roomQueueRef.current = initialQueue;
    if (nextRoom.playback_state?.current && nextRoom.host_id !== user?.id) {
      suppressUntilRef.current = Date.now() + 1200;
      playerRef.current.applyRemoteSnapshot(nextRoom.playback_state, true);
      lastSnapshotRef.current = nextRoom.playback_state;
    }
    await Promise.all([refreshMessages(nextRoom.id), refreshMembers(nextRoom.id)]);
    if (!session || !user) return;
    await supabase.realtime.setAuth(session.access_token);
    const channel = supabase.channel(`room:${nextRoom.id}`, { config: { private: true, presence: { key: clientId } } }); channelRef.current = channel;
    const refreshAll = () => { void refreshMessages(nextRoom.id); };
    channel.on("presence", { event: "sync" }, () => {
      const online = new Set<string>(); Object.values(channel.presenceState<{ userId: string }>()).flat().forEach((entry) => { if (entry.userId) online.add(entry.userId); });
      void refreshMembers(nextRoom.id, online);
      if (roomRef.current?.host_id === user.id && roomQueueRef.current.length > 0) {
        void channel.send({ type: "broadcast", event: "room_queue_sync", payload: { queue: roomQueueRef.current } });
      }
    }).on("broadcast", { event: "playback" }, ({ payload }: { payload: { origin: string; userId: string; revision: number; snapshot: PlayerSnapshot } }) => {
      const activeRoom = roomRef.current;
      // Host controls everything; host never applies remote playback broadcasts
      if (activeRoom && activeRoom.host_id === user?.id) return;
      if (payload.origin === clientId || payload.revision <= revisionRef.current) return;
      // Only accept playback broadcasts sent by the room host
      if (activeRoom && payload.userId !== activeRoom.host_id) return;
      latestHostSnapshotRef.current = payload.snapshot;
      // If listener is paused locally / desynced, do not force playback
      if (!isLiveRef.current) return;
      revisionRef.current = payload.revision;
      controllerRef.current = payload.origin;
      lastSnapshotRef.current = payload.snapshot;
      playerRef.current.applyRemoteSnapshot(payload.snapshot, true);
    }).on("broadcast", { event: "change_song" }, ({ payload }: { payload: { song: MediaItem; context?: MediaItem[]; requesterName: string; requesterId: string } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      if (!payload.song?.videoId) return;
      playerRef.current.play(payload.song, payload.context || [payload.song]);
      window.dispatchEvent(new CustomEvent("innerwave-room-notification", {
        detail: {
          title: "Song changed",
          body: `${payload.requesterName || "A listener"} started playing ${payload.song.title}`,
          roomId: activeRoom.id,
        },
      }));
    }).on("broadcast", { event: "skip_song" }, ({ payload }: { payload: { direction: "next" | "previous"; requesterName: string } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      if (payload.direction === "next") {
        if (roomQueueRef.current.length > 0) {
          const [top, ...remaining] = roomQueueRef.current;
          roomQueueRef.current = remaining;
          setRoomQueue(remaining);
          void channel.send({ type: "broadcast", event: "room_queue_sync", payload: { queue: remaining } });
          playerRef.current.play(top.song);
        } else {
          playerRef.current.next();
        }
      } else {
        playerRef.current.previous();
      }
    }).on("broadcast", { event: "add_to_queue" }, ({ payload }: { payload: { item: QueuedRoomSong } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      const existing = roomQueueRef.current;
      if (existing.some((q) => q.song.videoId === payload.item.song.videoId)) return;
      const nextQueue = [...existing, payload.item];
      roomQueueRef.current = nextQueue;
      setRoomQueue(nextQueue);
      void channel.send({
        type: "broadcast",
        event: "room_queue_sync",
        payload: { queue: nextQueue, actorName: payload.item.addedBy.name, action: "add", songTitle: payload.item.song.title },
      });
    }).on("broadcast", { event: "vote_queue" }, ({ payload }: { payload: { queueItemId: string; userId: string } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      const nextQueue = roomQueueRef.current.map((item) => {
        if (item.id !== payload.queueItemId) return item;
        const hasVoted = item.votes.includes(payload.userId);
        const nextVotes = hasVoted ? item.votes.filter((id) => id !== payload.userId) : [...item.votes, payload.userId];
        return { ...item, votes: nextVotes };
      });
      nextQueue.sort((a, b) => b.votes.length - a.votes.length || new Date(a.addedAt).getTime() - new Date(b.addedAt).getTime());
      roomQueueRef.current = nextQueue;
      setRoomQueue(nextQueue);
      void channel.send({ type: "broadcast", event: "room_queue_sync", payload: { queue: nextQueue } });
    }).on("broadcast", { event: "play_queued" }, ({ payload }: { payload: { queueItemId: string } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      const target = roomQueueRef.current.find((item) => item.id === payload.queueItemId);
      if (target) {
        const remaining = roomQueueRef.current.filter((item) => item.id !== payload.queueItemId);
        roomQueueRef.current = remaining;
        setRoomQueue(remaining);
        void channel.send({ type: "broadcast", event: "room_queue_sync", payload: { queue: remaining } });
        playerRef.current.play(target.song);
      }
    }).on("broadcast", { event: "remove_from_queue" }, ({ payload }: { payload: { queueItemId: string } }) => {
      const activeRoom = roomRef.current;
      if (!activeRoom || activeRoom.host_id !== user.id) return;
      const remaining = roomQueueRef.current.filter((item) => item.id !== payload.queueItemId);
      roomQueueRef.current = remaining;
      setRoomQueue(remaining);
      void channel.send({ type: "broadcast", event: "room_queue_sync", payload: { queue: remaining } });
    }).on("broadcast", { event: "room_queue_sync" }, ({ payload }: { payload: { queue: QueuedRoomSong[]; actorName?: string; action?: string; songTitle?: string } }) => {
      const activeRoom = roomRef.current;
      if (activeRoom && activeRoom.host_id !== user.id) {
        const nextQ = Array.isArray(payload.queue) ? payload.queue : [];
        setRoomQueue(nextQ);
        roomQueueRef.current = nextQ;
        if (payload.action === "add" && payload.actorName && payload.songTitle) {
          window.dispatchEvent(new CustomEvent("innerwave-room-notification", {
            detail: {
              title: "Added to room queue",
              body: `${payload.actorName} queued ${payload.songTitle}`,
              roomId: activeRoom.id,
            },
          }));
        }
      }
    }).on("postgres_changes", { event: "*", schema: "public", table: "room_messages", filter: `room_id=eq.${nextRoom.id}` }, refreshAll)
      .on("postgres_changes", { event: "*", schema: "public", table: "message_reactions" }, refreshAll)
      .on("postgres_changes", { event: "*", schema: "public", table: "room_members", filter: `room_id=eq.${nextRoom.id}` }, () => void refreshMembers(nextRoom.id));
    channel.subscribe(async (status) => { const ready = status === "SUBSCRIBED"; setConnected(ready); if (ready) await channel.track({ userId: user.id, name: displayName, clientId }); });
  }, [clientId, detach, displayName, refreshMembers, refreshMessages, session, user]);

  // Page reload persistence: automatically rejoin active room
  useEffect(() => {
    if (!user || hasRestoredRef.current || roomRef.current) return;
    const activeKey = `innerwave-active-room:${user.id}`;
    const savedActive = localStorage.getItem(activeKey);
    if (!savedActive) return;
    try {
      const parsed = JSON.parse(savedActive);
      if (parsed?.code) {
        hasRestoredRef.current = true;
        const restore = async () => {
          try {
            const { data, error: rpcError } = await supabase.rpc("join_listening_room", { p_code: parsed.code.trim().toUpperCase() });
            if (rpcError || !data) {
              localStorage.removeItem(activeKey);
            } else {
              await attach(data as ListeningRoom);
            }
          } catch {
            localStorage.removeItem(activeKey);
          }
        };
        void restore();
      }
    } catch {
      localStorage.removeItem(activeKey);
    }
  }, [attach, user]);

  const pauseListener = useCallback(() => {
    setIsLive(false);
    isLiveRef.current = false;
    playerRef.current.applyRemoteSnapshot({
      ...playerRef.current.snapshot,
      isPlaying: false,
    }, true);
  }, []);

  const goLive = useCallback(() => {
    setIsLive(true);
    isLiveRef.current = true;
    if (latestHostSnapshotRef.current) {
      playerRef.current.applyRemoteSnapshot(latestHostSnapshotRef.current, true);
    }
  }, []);

  useEffect(() => () => { void detach(); }, [detach]);

  // Host broadcast timer & persistence
  useEffect(() => {
    if (!room || !user) return;
    const isHostUser = room.host_id === user.id;
    if (!isHostUser) return;
    controllerRef.current = clientId;
    const timer = window.setInterval(() => {
      if (!channelRef.current) return;
      const current = { ...playerRef.current.snapshot, capturedAt: Date.now() };
      lastSnapshotRef.current = current;
      const revision = Math.max(++revisionRef.current, Date.now());
      revisionRef.current = revision;
      void channelRef.current.send({ type: "broadcast", event: "playback", payload: { origin: clientId, userId: user.id, revision, snapshot: current } });
    }, 500);
    const persist = window.setInterval(() => {
      if (roomRef.current && roomRef.current.host_id === user.id) {
        void supabase.from("listening_rooms").update({
          playback_state: {
            ...playerRef.current.snapshot,
            roomQueue: roomQueueRef.current,
          },
          revision: revisionRef.current,
          updated_at: new Date().toISOString(),
        }).eq("id", roomRef.current.id);
      }
    }, 5000);
    return () => { window.clearInterval(timer); window.clearInterval(persist); };
  }, [clientId, room, user]);

  // Command Interceptor: Collaborative playback & shared queue Next autoplay
  useEffect(() => {
    if (!room || !user) {
      player.setCommandInterceptor(null);
      return;
    }

    if (room.host_id === user.id) {
      const hostInterceptor = (command: PlayerCommand) => {
        if (command.action === "next" && roomQueueRef.current.length > 0) {
          const [top, ...remaining] = roomQueueRef.current;
          roomQueueRef.current = remaining;
          setRoomQueue(remaining);
          void channelRef.current?.send({
            type: "broadcast",
            event: "room_queue_sync",
            payload: { queue: remaining },
          });
          playerRef.current.play(top.song);
          return true;
        }
        return false;
      };
      player.setCommandInterceptor(hostInterceptor);
      return () => { player.setCommandInterceptor(null); };
    }

    // Listener collaborative playback
    const listenerInterceptor = (command: PlayerCommand) => {
      if (!isLiveRef.current) return false;

      if (command.action === "play") {
        if (!channelRef.current) return false;
        void channelRef.current.send({
          type: "broadcast",
          event: "change_song",
          payload: {
            song: command.item,
            context: command.context,
            requesterName: displayName,
            requesterId: user.id,
          },
        });
        window.dispatchEvent(
          new CustomEvent("innerwave-room-notification", {
            detail: {
              title: "Changing song for room…",
              body: command.item.title,
            },
          })
        );
        return true;
      }

      if (command.action === "next") {
        if (!channelRef.current) return false;
        void channelRef.current.send({
          type: "broadcast",
          event: "skip_song",
          payload: { direction: "next", requesterName: displayName },
        });
        return true;
      }

      if (command.action === "previous") {
        if (!channelRef.current) return false;
        void channelRef.current.send({
          type: "broadcast",
          event: "skip_song",
          payload: { direction: "previous", requesterName: displayName },
        });
        return true;
      }

      return false;
    };

    player.setCommandInterceptor(listenerInterceptor);
    return () => { player.setCommandInterceptor(null); };
  }, [displayName, player, room, user]);

  const requestPlaySong = useCallback((song: MediaItem, context?: MediaItem[]) => {
    if (!song?.videoId) return;
    const activeRoom = roomRef.current;
    if (!activeRoom || !user) {
      playerRef.current.play(song, context);
      return;
    }

    if (activeRoom.host_id === user.id) {
      playerRef.current.play(song, context);
      return;
    }

    if (channelRef.current) {
      void channelRef.current.send({
        type: "broadcast",
        event: "change_song",
        payload: {
          song,
          context,
          requesterName: displayName,
          requesterId: user.id,
        },
      });
      window.dispatchEvent(
        new CustomEvent("innerwave-room-notification", {
          detail: {
            title: "Changing song for room…",
            body: song.title,
          },
        })
      );
    }
  }, [displayName, user]);

  const addToRoomQueue = useCallback((song: MediaItem) => {
    if (!song?.videoId) return;
    const activeRoom = roomRef.current;
    if (!activeRoom || !user || !channelRef.current) return;

    const newItem: QueuedRoomSong = {
      id: createId(),
      song,
      addedBy: { id: user.id, name: displayName },
      votes: [user.id],
      addedAt: new Date().toISOString(),
    };

    if (activeRoom.host_id === user.id) {
      if (roomQueueRef.current.some((q) => q.song.videoId === song.videoId)) return;
      const nextQueue = [...roomQueueRef.current, newItem];
      roomQueueRef.current = nextQueue;
      setRoomQueue(nextQueue);
      void channelRef.current.send({
        type: "broadcast",
        event: "room_queue_sync",
        payload: {
          queue: nextQueue,
          actorName: displayName,
          action: "add",
          songTitle: song.title,
        },
      });
    } else {
      void channelRef.current.send({
        type: "broadcast",
        event: "add_to_queue",
        payload: { item: newItem },
      });
    }

    window.dispatchEvent(
      new CustomEvent("innerwave-room-notification", {
        detail: {
          title: "Added to room queue",
          body: `Queued: ${song.title}`,
          roomId: activeRoom.id,
        },
      })
    );
  }, [displayName, user]);

  const voteSong = useCallback((queueItemId: string) => {
    const activeRoom = roomRef.current;
    if (!activeRoom || !user || !channelRef.current) return;

    if (activeRoom.host_id === user.id) {
      const nextQueue = roomQueueRef.current.map((item) => {
        if (item.id !== queueItemId) return item;
        const hasVoted = item.votes.includes(user.id);
        const nextVotes = hasVoted ? item.votes.filter((id) => id !== user.id) : [...item.votes, user.id];
        return { ...item, votes: nextVotes };
      });
      nextQueue.sort((a, b) => b.votes.length - a.votes.length || new Date(a.addedAt).getTime() - new Date(b.addedAt).getTime());
      roomQueueRef.current = nextQueue;
      setRoomQueue(nextQueue);
      void channelRef.current.send({
        type: "broadcast",
        event: "room_queue_sync",
        payload: { queue: nextQueue },
      });
    } else {
      // Optimistic update for listener
      setRoomQueue((prev) =>
        prev.map((item) => {
          if (item.id !== queueItemId) return item;
          const hasVoted = item.votes.includes(user.id);
          const nextVotes = hasVoted ? item.votes.filter((id) => id !== user.id) : [...item.votes, user.id];
          return { ...item, votes: nextVotes };
        }).sort((a, b) => b.votes.length - a.votes.length || new Date(a.addedAt).getTime() - new Date(b.addedAt).getTime())
      );
      void channelRef.current.send({
        type: "broadcast",
        event: "vote_queue",
        payload: { queueItemId, userId: user.id },
      });
    }
  }, [user]);

  const playQueuedSong = useCallback((queueItemId: string) => {
    const activeRoom = roomRef.current;
    if (!activeRoom || !user || !channelRef.current) return;

    if (activeRoom.host_id === user.id) {
      const target = roomQueueRef.current.find((item) => item.id === queueItemId);
      if (target) {
        const remaining = roomQueueRef.current.filter((item) => item.id !== queueItemId);
        roomQueueRef.current = remaining;
        setRoomQueue(remaining);
        void channelRef.current.send({
          type: "broadcast",
          event: "room_queue_sync",
          payload: { queue: remaining },
        });
        playerRef.current.play(target.song);
      }
    } else {
      void channelRef.current.send({
        type: "broadcast",
        event: "play_queued",
        payload: { queueItemId },
      });
    }
  }, [user]);

  const removeFromRoomQueue = useCallback((queueItemId: string) => {
    const activeRoom = roomRef.current;
    if (!activeRoom || !user || !channelRef.current) return;

    if (activeRoom.host_id === user.id) {
      const remaining = roomQueueRef.current.filter((item) => item.id !== queueItemId);
      roomQueueRef.current = remaining;
      setRoomQueue(remaining);
      void channelRef.current.send({
        type: "broadcast",
        event: "room_queue_sync",
        payload: { queue: remaining },
      });
    } else {
      void channelRef.current.send({
        type: "broadcast",
        event: "remove_from_queue",
        payload: { queueItemId },
      });
    }
  }, [user]);

  const createRoom = useCallback(async (name = "Listening room") => {
    void enableRoomNotifications();
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc("create_listening_room", { p_name: name });
    setBusy(false);
    if (rpcError || !data) {
      setError(rpcError?.message || "Could not create room");
      return false;
    }
    const created = data as ListeningRoom;
    const historyItem: RoomHistoryItem = {
      id: created.id,
      code: created.code,
      name: created.name || name,
      timestamp: new Date().toISOString(),
    };
    const storageKey = `innerwave-created-rooms:${user?.id || "guest"}`;
    const updated = saveHistoryItem(storageKey, historyItem);
    setCreatedRoomsHistory(updated);
    if (user) {
      localStorage.setItem(`innerwave-active-room:${user.id}`, JSON.stringify({ id: created.id, code: created.code, name: created.name, host_id: created.host_id }));
    }
    await attach(created);
    return true;
  }, [attach, user]);

  const joinRoom = useCallback(async (code: string) => {
    void enableRoomNotifications();
    setBusy(true);
    setError(null);
    const { data, error: rpcError } = await supabase.rpc("join_listening_room", { p_code: code.trim().toUpperCase() });
    setBusy(false);
    if (rpcError || !data) {
      setError(rpcError?.message || "Could not join room");
      return false;
    }
    const joined = data as ListeningRoom;
    const historyItem: RoomHistoryItem = {
      id: joined.id,
      code: joined.code,
      name: joined.name || "Listening room",
      timestamp: new Date().toISOString(),
    };
    if (joined.host_id === user?.id) {
      const storageKey = `innerwave-created-rooms:${user?.id || "guest"}`;
      const updated = saveHistoryItem(storageKey, historyItem);
      setCreatedRoomsHistory(updated);
    } else {
      const storageKey = `innerwave-joined-rooms:${user?.id || "guest"}`;
      const updated = saveHistoryItem(storageKey, historyItem);
      setJoinedRoomsHistory(updated);
    }
    if (user) {
      localStorage.setItem(`innerwave-active-room:${user.id}`, JSON.stringify({ id: joined.id, code: joined.code, name: joined.name, host_id: joined.host_id }));
    }
    await attach(joined);
    return true;
  }, [attach, user]);

  const leaveRoom = useCallback(async () => {
    const active = roomRef.current;
    if (user) {
      localStorage.removeItem(`innerwave-active-room:${user.id}`);
    }
    await detach();
    if (active && user) {
      await supabase.from("room_members").delete().eq("room_id", active.id).eq("user_id", user.id);
    }
    setRoom(null);
    roomRef.current = null;
  }, [detach, user]);

  const sendMessage = useCallback(async (body: string, replyTo: string | null = null, song: MediaItem | null = null) => {
    if (!room || !user || (!body.trim() && !song)) return false;
    const { error: sendError } = await supabase.from("room_messages").insert({ room_id: room.id, sender_id: user.id, body: body.trim(), reply_to: replyTo, song });
    if (sendError) { setError(sendError.message); return false; }
    await refreshMessages(room.id);
    return true;
  }, [refreshMessages, room, user]);

  const toggleReaction = useCallback(async (messageId: string, emoji: string) => {
    if (!user || !room) return;
    const exists = messages.some((message) => message.id === messageId && message.reactions.some((reaction) => reaction.user_id === user.id && reaction.emoji === emoji));
    if (exists) await supabase.from("message_reactions").delete().eq("message_id", messageId).eq("user_id", user.id).eq("emoji", emoji);
    else await supabase.from("message_reactions").insert({ message_id: messageId, user_id: user.id, emoji });
    await refreshMessages(room.id);
  }, [messages, refreshMessages, room, user]);

  const value = useMemo(() => ({
    room, members, messages, connected, busy, error, isHost, isInRoom, isLive, goLive, pauseListener,
    createRoom, joinRoom, leaveRoom, sendMessage, toggleReaction,
    joinedRoomsHistory, createdRoomsHistory,
    roomQueue, addToRoomQueue, voteSong, playQueuedSong, removeFromRoomQueue, requestPlaySong,
  }), [
    addToRoomQueue, busy, connected, createRoom, createdRoomsHistory, error, goLive, isHost, isInRoom, isLive,
    joinRoom, joinedRoomsHistory, leaveRoom, members, messages, pauseListener, playQueuedSong,
    removeFromRoomQueue, requestPlaySong, room, roomQueue, sendMessage, toggleReaction, voteSong
  ]);
  return <ListeningRoomContext.Provider value={value}>{children}</ListeningRoomContext.Provider>;
}

export function useListeningRoom() { const value = useContext(ListeningRoomContext); if (!value) throw new Error("useListeningRoom must be used inside ListeningRoomProvider"); return value; }
