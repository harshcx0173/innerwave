/* eslint-disable @next/next/no-img-element */
"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Copy, ListMusic, LogOut, MessageCircleMore, Music2, Plus, Reply, Search, Send, SmilePlus, ThumbsUp, Users, X } from "lucide-react";
import { useListeningRoom, type RoomMessage } from "@/context/listening-room-context";
import { usePlayer } from "@/context/player-context";
import { useAuth } from "@/context/auth-context";
import { formatChatTime } from "@/lib/chat-time";
import { musicApi } from "@/lib/api";
import type { MediaItem } from "@/lib/types";
import { RoomEmojiPicker } from "./room-emoji-picker";

const emojis = ["❤️", "🔥", "😂", "👏", "🎵", "😍"];

function RoomSongThumbnail({
  song,
  className = "",
  alt = "",
}: {
  song?: MediaItem | null;
  className?: string;
  alt?: string;
}) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);

  const primarySrc = song?.thumbnail;
  const fallbackHq = song?.videoId ? `https://i.ytimg.com/vi/${song.videoId}/hqdefault.jpg` : null;
  const fallbackMq = song?.videoId ? `https://i.ytimg.com/vi/${song.videoId}/mqdefault.jpg` : null;

  let currentSrc: string | null = null;
  if (primarySrc && failedUrl !== primarySrc) {
    currentSrc = primarySrc;
  } else if (fallbackHq && failedUrl !== fallbackHq) {
    currentSrc = fallbackHq;
  } else if (fallbackMq && failedUrl !== fallbackMq) {
    currentSrc = fallbackMq;
  }

  const handleError = () => {
    if (currentSrc) {
      setFailedUrl(currentSrc);
    }
  };

  if (!currentSrc) {
    return <Music2 className={className} />;
  }

  return (
    <img
      src={currentSrc}
      alt={alt || song?.title || ""}
      loading="lazy"
      decoding="async"
      referrerPolicy="no-referrer"
      onError={handleError}
      className={className}
    />
  );
}

export function ListeningRoomPanel() {
  const { user } = useAuth(); const player = usePlayer();
  const roomState = useListeningRoom();
  const [open, setOpen] = useState(false); const [mode, setMode] = useState<"create" | "join">("join");
  const [roomTab, setRoomTab] = useState<"chat" | "queue">("chat");
  const [queueSearch, setQueueSearch] = useState("");
  const [queueResults, setQueueResults] = useState<MediaItem[]>([]);
  const [visibleCount, setVisibleCount] = useState(10);
  const [queueContinuation, setQueueContinuation] = useState<string | null>(null);
  const [queueSearching, setQueueSearching] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [code, setCode] = useState(""); const [name, setName] = useState("My listening room"); const [draft, setDraft] = useState("");
  const [reply, setReply] = useState<RoomMessage | null>(null); const [emojiOpen, setEmojiOpen] = useState(false);
  const [toast, setToast] = useState<{ title: string; body: string } | null>(null);
  const [unreadCount, setUnreadCount] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const openRef = useRef(open);
  const isSubmittingRef = useRef(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesContainerRef = useRef<HTMLDivElement>(null);
  const emojiTriggerRef = useRef<HTMLButtonElement>(null);

  const scrollToBottom = useCallback((behavior: ScrollBehavior = "auto") => {
    if (messagesContainerRef.current) {
      messagesContainerRef.current.scrollTop = messagesContainerRef.current.scrollHeight;
    }
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior, block: "end" });
    }
  }, []);

  useEffect(() => {
    openRef.current = open;
  }, [open]);

  // Always jump to latest message when panel opens or when user switches to chat tab
  useEffect(() => {
    if (open && roomTab === "chat" && roomState.room) {
      scrollToBottom("auto");
      const timer = setTimeout(() => {
        scrollToBottom("auto");
      }, 70);
      return () => clearTimeout(timer);
    }
  }, [open, roomTab, roomState.room, scrollToBottom]);

  // Smooth scroll to latest when new messages arrive while chat is open
  useEffect(() => {
    if (open && roomTab === "chat" && roomState.messages.length > 0) {
      const timer = setTimeout(() => {
        scrollToBottom("smooth");
      }, 50);
      return () => clearTimeout(timer);
    }
  }, [open, roomTab, roomState.messages.length, scrollToBottom]);

  const effectiveUnread = open || !roomState.room ? 0 : unreadCount;

  // Debounced search for queue tab
  useEffect(() => {
    let cancelled = false;
    if (!queueSearch.trim() || queueSearch.trim().length < 2) {
      const timer = setTimeout(() => {
        if (!cancelled) {
          setQueueResults([]);
          setVisibleCount(10);
          setQueueContinuation(null);
          setQueueSearching(false);
        }
      }, 0);
      return () => {
        cancelled = true;
        clearTimeout(timer);
      };
    }
    const timer = setTimeout(() => {
      setQueueSearching(true);
      musicApi
        .search(queueSearch)
        .then((res) => {
          if (!cancelled) {
            const allItems = (res.shelves || []).flatMap((shelf) => shelf.items || []);
            const seen = new Set<string>();
            const playableSongs = allItems.filter((item) => {
              const id = item.videoId || item.id;
              if (!id || seen.has(id)) return false;
              seen.add(id);
              return Boolean(item.videoId);
            });
            setQueueResults(playableSongs);
            setVisibleCount(Math.min(10, playableSongs.length));
            setQueueContinuation(res.continuation || null);
            setQueueSearching(false);
          }
        })
        .catch(() => {
          if (!cancelled) setQueueSearching(false);
        });
    }, 350);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [queueSearch]);

  const handleQueueScroll = (e: React.UIEvent<HTMLDivElement>) => {
    const { scrollTop, scrollHeight, clientHeight } = e.currentTarget;
    if (scrollHeight - scrollTop - clientHeight < 60 && !loadingMore && !queueSearching) {
      if (visibleCount < queueResults.length) {
        setVisibleCount((prev) => Math.min(prev + 10, queueResults.length));
      } else if (queueContinuation && queueSearch.trim()) {
        setLoadingMore(true);
        musicApi
          .search(queueSearch, queueContinuation)
          .then((res) => {
            const nextItems = (res.shelves || []).flatMap((shelf) => shelf.items || []);
            const seen = new Set(queueResults.map((item) => item.videoId || item.id));
            const newSongs = nextItems.filter((item) => {
              const id = item.videoId || item.id;
              if (!id || seen.has(id)) return false;
              seen.add(id);
              return Boolean(item.videoId);
            });
            if (newSongs.length > 0) {
              setQueueResults((prev) => [...prev, ...newSongs]);
              setVisibleCount((prev) => prev + Math.min(10, newSongs.length));
            }
            setQueueContinuation(res.continuation || null);
            setLoadingMore(false);
          })
          .catch(() => {
            setLoadingMore(false);
          });
      }
    }
  };

  const mentionQuery = draft.match(/(?:^|\s)@([\w.-]*)$/)?.[1]?.toLowerCase();
  const mentionMatches = useMemo(() => mentionQuery === undefined ? [] : roomState.members.filter((member) => member.userId !== user?.id && member.name.toLowerCase().includes(mentionQuery)).slice(0, 5), [mentionQuery, roomState.members, user?.id]);
  const messageMap = useMemo(() => new Map(roomState.messages.map((message) => [message.id, message])), [roomState.messages]);
  useEffect(() => {
    let timer = 0;
    const show = (event: Event) => {
      const detail = (event as CustomEvent<{ title: string; body: string; count?: number }>).detail;
      setToast(detail);
      if (!openRef.current) {
        setUnreadCount((prev) => prev + (detail.count || 1));
      }
      window.clearTimeout(timer);
      timer = window.setTimeout(() => setToast(null), 4500);
    };
    window.addEventListener("innerwave-room-notification", show);
    return () => {
      window.removeEventListener("innerwave-room-notification", show);
      window.clearTimeout(timer);
    };
  }, []);

  function addMention(memberName: string) {
    setDraft((value) => value.replace(/@([\w.-]*)$/, `@${memberName.replace(/\s+/g, "_")} `)); inputRef.current?.focus();
  }

  async function submit() {
    const text = draft.trim();
    if (!text && !reply) return;
    if (isSubmittingRef.current) return;
    isSubmittingRef.current = true;
    const currentReplyId = reply?.id || null;
    // Clear immediately for 0 ms UI response
    setDraft("");
    setReply(null);
    setEmojiOpen(false);
    inputRef.current?.focus();
    setTimeout(() => scrollToBottom("smooth"), 0);
    try {
      const ok = await roomState.sendMessage(text, currentReplyId);
      if (!ok) {
        setDraft(text);
      }
    } finally {
      isSubmittingRef.current = false;
    }
  }

  async function suggestSong() {
    if (player.current && !isSubmittingRef.current) {
      isSubmittingRef.current = true;
      const currentReplyId = reply?.id || null;
      setReply(null);
      try {
        await roomState.sendMessage("Suggested this song", currentReplyId, player.current);
      } finally {
        isSubmittingRef.current = false;
      }
    }
  }

  return <>
    {toast && <button className="room-toast" onClick={() => { setOpen(true); setUnreadCount(0); setToast(null); }}><MessageCircleMore /><span><b>{toast.title}</b><small>{toast.body}</small></span><X onClick={(event) => { event.stopPropagation(); setToast(null); }} /></button>}
    <button className={`room-launcher ${roomState.room ? "active" : ""}`} onClick={() => { setOpen(true); setUnreadCount(0); }} aria-label="Listening room"><MessageCircleMore />{effectiveUnread > 0 && <span>{effectiveUnread > 99 ? "99+" : effectiveUnread}</span>}</button>
    {open && <div className="room-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpen(false); }}>
      <aside className="room-panel">
        <header><div><span>INNERWAVE TOGETHER</span><h2>{roomState.room?.name || "Listen together"}</h2></div><button onClick={() => setOpen(false)}><X /></button></header>
        {!roomState.room ? <div className="room-entry">
          <div className="room-mode"><button className={mode === "join" ? "active" : ""} onClick={() => setMode("join")}>Join room</button><button className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create room</button></div>
          <div className="room-entry-art"><Users /><h3>Music feels better together.</h3><p>Share one synchronized queue and chat while you listen.</p></div>
          {mode === "join" ? <input value={code} onChange={(event) => setCode(event.target.value.toUpperCase())} maxLength={6} placeholder="6-character room code" /> : <input value={name} onChange={(event) => setName(event.target.value)} maxLength={60} placeholder="Room name" />}
          <button className="room-primary" disabled={roomState.busy || (mode === "join" ? code.length < 6 : !name.trim())} onClick={() => void (mode === "join" ? roomState.joinRoom(code) : roomState.createRoom(name))}>{roomState.busy ? "Please wait…" : mode === "join" ? "Join listening room" : "Create listening room"}</button>
          {roomState.error && <p className="room-error">{roomState.error}</p>}
          {mode === "join" && roomState.joinedRoomsHistory.length > 0 && (
            <div className="room-history-section">
              <div className="room-history-title">
                <span>PREVIOUSLY JOINED ROOMS</span>
                <small>{roomState.joinedRoomsHistory.length}</small>
              </div>
              <div className="room-history-box">
                {roomState.joinedRoomsHistory.map((item) => (
                  <div
                    key={item.code}
                    className="room-history-item"
                    onClick={() => {
                      setCode(item.code);
                      void roomState.joinRoom(item.code);
                    }}
                    title={`Click to join ${item.name || item.code}`}
                  >
                    <div className="room-history-text">
                      <b>{item.name || "Listening Room"}</b>
                      <span>Code: <code>{item.code}</code></span>
                    </div>
                    <button
                      type="button"
                      className="room-history-btn"
                      disabled={roomState.busy}
                      onClick={(e) => {
                        e.stopPropagation();
                        setCode(item.code);
                        void roomState.joinRoom(item.code);
                      }}
                    >
                      Join
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
          {mode === "create" && roomState.createdRoomsHistory.length > 0 && (
            <div className="room-history-section">
              <div className="room-history-title">
                <span>YOUR CREATED ROOMS</span>
                <small>{roomState.createdRoomsHistory.length}</small>
              </div>
              <div className="room-history-box">
                {roomState.createdRoomsHistory.map((item) => (
                  <div
                    key={item.code}
                    className="room-history-item"
                    onClick={() => {
                      void roomState.joinRoom(item.code);
                    }}
                    title={`Click to enter ${item.name || item.code}`}
                  >
                    <div className="room-history-text">
                      <b>{item.name || "My Room"}</b>
                      <span>Code: <code>{item.code}</code></span>
                    </div>
                    <button
                      type="button"
                      className="room-history-btn"
                      disabled={roomState.busy}
                      onClick={(e) => {
                        e.stopPropagation();
                        void roomState.joinRoom(item.code);
                      }}
                    >
                      Reopen
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div> : <>
          <div className="room-meta"><button onClick={() => void navigator.clipboard.writeText(roomState.room!.code)} title="Copy room code"><b>{roomState.room.code}</b><Copy /></button><span className={roomState.connected ? "online" : ""}>{roomState.connected ? "Live" : "Connecting"}</span><button className="room-leave" onClick={() => void roomState.leaveRoom()}><LogOut />Leave</button></div>
          <div className="room-members">{roomState.members.map((member) => <span key={member.userId} title={`${member.name} • ${member.role}`} className={member.online ? "online" : ""}>{member.name.slice(0, 1).toUpperCase()}</span>)}</div>

          <div className="room-nav-tabs">
            <button
              className={`room-nav-btn ${roomTab === "chat" ? "active" : ""}`}
              onClick={() => setRoomTab("chat")}
            >
              <MessageCircleMore size={15} />
              <span>Chat</span>
            </button>
            <button
              className={`room-nav-btn ${roomTab === "queue" ? "active" : ""}`}
              onClick={() => setRoomTab("queue")}
            >
              <ListMusic size={15} />
              <span>Queue & Vote</span>
              {roomState.roomQueue.length > 0 && (
                <span className="room-tab-badge">{roomState.roomQueue.length}</span>
              )}
            </button>
          </div>

          {roomTab === "chat" ? (
            <>
              <div className="room-messages" ref={messagesContainerRef}>
                {roomState.messages.map((message) => {
                  const parent = message.reply_to ? messageMap.get(message.reply_to) : null;
                  const grouped = [...new Set(message.reactions.map((reaction) => reaction.emoji))];
                  return (
                    <article key={message.id} className={message.sender_id === user?.id ? "mine" : ""}>
                      <div className="room-message-head"><b>{message.senderName}</b><time>{formatChatTime(message.created_at)}</time></div>
                      {parent && <blockquote><b>{parent.senderName}</b> {parent.body || "Shared a song"}</blockquote>}
                      {message.body && <p>{message.body.split(/(@[\w_]+)/g).map((part, index) => part.startsWith("@") ? <mark key={index}>{part}</mark> : part)}</p>}
                      {message.song && (
                        <div className="room-song-wrapper">
                          <button className="room-song" onClick={() => player.play(message.song!, [])}>
                            <RoomSongThumbnail song={message.song} />
                            <span><b>{message.song.title}</b><small>{message.song.artists.join(", ") || message.song.subtitle}</small></span>
                            <i>▶</i>
                          </button>
                          <button
                            className="room-song-queue-btn"
                            title="Add to shared room queue"
                            onClick={(e) => {
                              e.stopPropagation();
                              roomState.addToRoomQueue(message.song!);
                            }}
                          >
                            <Plus size={13} />
                            <span>Queue</span>
                          </button>
                        </div>
                      )}
                      {!!grouped.length && <div className="room-reactions">{grouped.map((emoji) => <button key={emoji} onClick={() => void roomState.toggleReaction(message.id, emoji)}>{emoji} {message.reactions.filter((item) => item.emoji === emoji).length}</button>)}</div>}
                      <div className="room-message-actions"><div className="reply-btn"><button onClick={() => { setReply(message); inputRef.current?.focus(); }}><Reply />Reply</button></div>&nbsp;{emojis.slice(0, 4).map((emoji) => <button key={emoji} onClick={() => void roomState.toggleReaction(message.id, emoji)}>{emoji}</button>)}</div>
                    </article>
                  );
                })}
                {!roomState.messages.length && <div className="room-empty"><MessageCircleMore /><p>Say hello. Everyone in the room will see it instantly.</p></div>}
                <div ref={messagesEndRef} />
              </div>
              <footer className="room-composer">
                {reply && <div className="room-replying"><span>Replying to <b>{reply.senderName}</b></span><button onClick={() => setReply(null)}><X /></button></div>}
                {!!mentionMatches.length && <div className="mention-menu">{mentionMatches.map((member) => <button key={member.userId} onClick={() => addMention(member.name)}>@{member.name.replace(/\s+/g, "_")}</button>)}</div>}
                {emojiOpen && (
                  <RoomEmojiPicker
                    onSelect={(emoji) => {
                      setDraft((value) => value + emoji);
                      inputRef.current?.focus();
                    }}
                    onClose={() => setEmojiOpen(false)}
                    triggerRef={emojiTriggerRef}
                  />
                )}
                <div>
                  <button
                    ref={emojiTriggerRef}
                    title="Emoji"
                    type="button"
                    onClick={() => setEmojiOpen((value) => !value)}
                  >
                    <SmilePlus />
                  </button>
                  <button title="Suggest current song" disabled={!player.current} onClick={() => void suggestSong()}><Music2 /></button>
                  <input ref={inputRef} value={draft} onChange={(event) => setDraft(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); void submit(); } }} placeholder="Message the room…" maxLength={2000} />
                  <button className="send" disabled={!draft.trim()} onClick={() => void submit()}><Send /></button>
                </div>
              </footer>
            </>
          ) : (
            <div className="room-queue-tab">
              {player.current && (
                <div className="room-queue-now">
                  <div className="room-queue-now-head">
                    <span>NOW PLAYING IN ROOM</span>
                    <span className="live-pill">LIVE</span>
                  </div>
                  <div className="room-queue-now-card">
                    <RoomSongThumbnail song={player.current} />
                    <div className="room-queue-now-meta">
                      <b>{player.current.title}</b>
                      <small>{player.current.artists?.join(", ") || player.current.subtitle}</small>
                    </div>
                  </div>
                </div>
              )}

              <div className="room-queue-search">
                <div className="room-queue-search-input">
                  <Search size={14} />
                  <input
                    value={queueSearch}
                    onChange={(e) => setQueueSearch(e.target.value)}
                    placeholder="Search song to add to room queue…"
                  />
                  {queueSearch && (
                    <button onClick={() => setQueueSearch("")}>
                      <X size={13} />
                    </button>
                  )}
                </div>
                {queueSearching && <div className="room-queue-searching">Searching tracks…</div>}
                {queueResults.length > 0 && (
                  <div className="room-queue-search-results" onScroll={handleQueueScroll}>
                    {queueResults.slice(0, visibleCount).map((song) => (
                      <div key={song.id} className="room-queue-result-item">
                        <RoomSongThumbnail song={song} />
                        <div className="room-queue-result-meta">
                          <b>{song.title}</b>
                          <small>{song.artists?.join(", ") || song.subtitle}</small>
                        </div>
                        <button
                          className="room-queue-result-add"
                          onClick={() => {
                            roomState.addToRoomQueue(song);
                            setQueueSearch("");
                            setQueueResults([]);
                            setQueueContinuation(null);
                            setVisibleCount(10);
                          }}
                          title="Add to queue"
                        >
                          <Plus size={14} />
                          <span>Add</span>
                        </button>
                      </div>
                    ))}
                    {loadingMore && (
                      <div className="room-queue-loading-more">
                        <span>Loading more tracks…</span>
                      </div>
                    )}
                  </div>
                )}
              </div>

              <div className="room-queue-header">
                <span>UPCOMING QUEUE (SORTED BY VOTES)</span>
                <small>{roomState.roomQueue.length} {roomState.roomQueue.length === 1 ? "track" : "tracks"}</small>
              </div>

              <div className="room-queue-scroll">
                {roomState.roomQueue.length === 0 ? (
                  <div className="room-queue-empty">
                    <ListMusic size={34} />
                    <h4>Room queue is empty</h4>
                    <p>Search any song above or click &ldquo;+ Queue&rdquo; on songs in chat. The song with the most votes will play next automatically!</p>
                  </div>
                ) : (
                  roomState.roomQueue.map((item, index) => {
                    const hasVoted = Boolean(user && item.votes.includes(user.id));
                    const isTop = index === 0;
                    return (
                      <article key={item.id} className={`room-queue-card ${isTop ? "top" : ""}`}>
                        <span className={`room-queue-rank ${isTop ? "top" : ""}`}>
                          {isTop ? "★ TOP" : `#${index + 1}`}
                        </span>
                        <div className="room-queue-thumb">
                          <RoomSongThumbnail song={item.song} />
                        </div>
                        <div className="room-queue-info">
                          <b>{item.song.title}</b>
                          <small>{item.song.artists?.join(", ") || item.song.subtitle}</small>
                          <span className="room-queue-by">Added by {item.addedBy.name}</span>
                        </div>
                        <div className="room-queue-actions">
                          <button
                            className={`room-vote-btn ${hasVoted ? "voted" : ""}`}
                            onClick={() => roomState.voteSong(item.id)}
                            title={hasVoted ? "Remove your vote" : "Vote for this song"}
                          >
                            <ThumbsUp size={13} />
                            <span>{item.votes.length}</span>
                          </button>
                          <button
                            className="room-queue-play"
                            onClick={() => roomState.playQueuedSong(item.id)}
                            title="Play now for the room"
                          >
                            ▶
                          </button>
                          {(roomState.isHost || item.addedBy.id === user?.id) && (
                            <button
                              className="room-queue-delete"
                              onClick={() => roomState.removeFromRoomQueue(item.id)}
                              title="Remove from queue"
                            >
                              <X size={12} />
                            </button>
                          )}
                        </div>
                      </article>
                    );
                  })
                )}
              </div>
            </div>
          )}
        </>}
      </aside>
    </div>}
  </>;
}
