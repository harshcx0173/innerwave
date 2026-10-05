"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Copy, LogOut, MessageCircleMore, Music2, Reply, Send, SmilePlus, Users, X } from "lucide-react";
import { useListeningRoom, type RoomMessage } from "@/context/listening-room-context";
import { usePlayer } from "@/context/player-context";
import { useAuth } from "@/context/auth-context";
import { formatChatTime } from "@/lib/chat-time";

const emojis = ["❤️", "🔥", "😂", "👏", "🎵", "😍"];

export function ListeningRoomPanel() {
  const { user } = useAuth(); const player = usePlayer();
  const roomState = useListeningRoom();
  const [open, setOpen] = useState(false); const [mode, setMode] = useState<"create" | "join">("join");
  const [code, setCode] = useState(""); const [name, setName] = useState("My listening room"); const [draft, setDraft] = useState("");
  const [reply, setReply] = useState<RoomMessage | null>(null); const [emojiOpen, setEmojiOpen] = useState(false);
  const [toast, setToast] = useState<{ title: string; body: string } | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const mentionQuery = draft.match(/(?:^|\s)@([\w.-]*)$/)?.[1]?.toLowerCase();
  const mentionMatches = useMemo(() => mentionQuery === undefined ? [] : roomState.members.filter((member) => member.userId !== user?.id && member.name.toLowerCase().includes(mentionQuery)).slice(0, 5), [mentionQuery, roomState.members, user?.id]);
  const messageMap = useMemo(() => new Map(roomState.messages.map((message) => [message.id, message])), [roomState.messages]);
  useEffect(() => { let timer = 0; const show = (event: Event) => { const detail = (event as CustomEvent<{ title: string; body: string }>).detail; setToast(detail); window.clearTimeout(timer); timer = window.setTimeout(() => setToast(null), 4500); }; window.addEventListener("innerwave-room-notification", show); return () => { window.removeEventListener("innerwave-room-notification", show); window.clearTimeout(timer); }; }, []);

  function addMention(memberName: string) {
    setDraft((value) => value.replace(/@([\w.-]*)$/, `@${memberName.replace(/\s+/g, "_")} `)); inputRef.current?.focus();
  }
  async function submit() { if (await roomState.sendMessage(draft, reply?.id)) { setDraft(""); setReply(null); setEmojiOpen(false); } }
  async function suggestSong() { if (player.current) await roomState.sendMessage("Suggested this song", reply?.id, player.current); }

  return <>
    {toast && <button className="room-toast" onClick={() => { setOpen(true); setToast(null); }}><MessageCircleMore /><span><b>{toast.title}</b><small>{toast.body}</small></span><X onClick={(event) => { event.stopPropagation(); setToast(null); }} /></button>}
    <button className={`room-launcher ${roomState.room ? "active" : ""}`} onClick={() => setOpen(true)} aria-label="Listening room"><MessageCircleMore /><span>{roomState.room ? roomState.members.length : ""}</span></button>
    {open && <div className="room-overlay" onMouseDown={(event) => { if (event.target === event.currentTarget) setOpen(false); }}>
      <aside className="room-panel">
        <header><div><span>INNERWAVE TOGETHER</span><h2>{roomState.room?.name || "Listen together"}</h2></div><button onClick={() => setOpen(false)}><X /></button></header>
        {!roomState.room ? <div className="room-entry">
          <div className="room-mode"><button className={mode === "join" ? "active" : ""} onClick={() => setMode("join")}>Join room</button><button className={mode === "create" ? "active" : ""} onClick={() => setMode("create")}>Create room</button></div>
          <div className="room-entry-art"><Users /><h3>Music feels better together.</h3><p>Share one synchronized queue and chat while you listen.</p></div>
          {mode === "join" ? <input value={code} onChange={(event) => setCode(event.target.value.toUpperCase())} maxLength={6} placeholder="6-character room code" /> : <input value={name} onChange={(event) => setName(event.target.value)} maxLength={60} placeholder="Room name" />}
          <button className="room-primary" disabled={roomState.busy || (mode === "join" ? code.length < 6 : !name.trim())} onClick={() => void (mode === "join" ? roomState.joinRoom(code) : roomState.createRoom(name))}>{roomState.busy ? "Please wait…" : mode === "join" ? "Join listening room" : "Create listening room"}</button>
          {roomState.error && <p className="room-error">{roomState.error}</p>}
        </div> : <>
          <div className="room-meta"><button onClick={() => void navigator.clipboard.writeText(roomState.room!.code)} title="Copy room code"><b>{roomState.room.code}</b><Copy /></button><span className={roomState.connected ? "online" : ""}>{roomState.connected ? "Live" : "Connecting"}</span><button className="room-leave" onClick={() => void roomState.leaveRoom()}><LogOut />Leave</button></div>
          <div className="room-members">{roomState.members.map((member) => <span key={member.userId} title={`${member.name} • ${member.role}`} className={member.online ? "online" : ""}>{member.name.slice(0, 1).toUpperCase()}</span>)}</div>
          <div className="room-messages">
            {roomState.messages.map((message) => { const parent = message.reply_to ? messageMap.get(message.reply_to) : null; const grouped = [...new Set(message.reactions.map((reaction) => reaction.emoji))]; return <article key={message.id} className={message.sender_id === user?.id ? "mine" : ""}>
              <div className="room-message-head"><b>{message.senderName}</b><time>{formatChatTime(message.created_at)}</time></div>
              {parent && <blockquote><b>{parent.senderName}</b> {parent.body || "Shared a song"}</blockquote>}
              {message.body && <p>{message.body.split(/(@[\w_]+)/g).map((part, index) => part.startsWith("@") ? <mark key={index}>{part}</mark> : part)}</p>}
              {message.song && <button className="room-song" onClick={() => player.play(message.song!, [])}>{message.song.thumbnail ? <img src={message.song.thumbnail} alt="" /> : <Music2 />}<span><b>{message.song.title}</b><small>{message.song.artists.join(", ") || message.song.subtitle}</small></span><i>▶</i></button>}
              {!!grouped.length && <div className="room-reactions">{grouped.map((emoji) => <button key={emoji} onClick={() => void roomState.toggleReaction(message.id, emoji)}>{emoji} {message.reactions.filter((item) => item.emoji === emoji).length}</button>)}</div>}
              <div className="room-message-actions"><button onClick={() => { setReply(message); inputRef.current?.focus(); }}><Reply />Reply</button>{emojis.slice(0, 4).map((emoji) => <button key={emoji} onClick={() => void roomState.toggleReaction(message.id, emoji)}>{emoji}</button>)}</div>
            </article>; })}
            {!roomState.messages.length && <div className="room-empty"><MessageCircleMore /><p>Say hello. Everyone in the room will see it instantly.</p></div>}
          </div>
          <footer className="room-composer">
            {reply && <div className="room-replying"><span>Replying to <b>{reply.senderName}</b></span><button onClick={() => setReply(null)}><X /></button></div>}
            {!!mentionMatches.length && <div className="mention-menu">{mentionMatches.map((member) => <button key={member.userId} onClick={() => addMention(member.name)}>@{member.name.replace(/\s+/g, "_")}</button>)}</div>}
            {emojiOpen && <div className="emoji-menu">{emojis.map((emoji) => <button key={emoji} onClick={() => setDraft((value) => value + emoji)}>{emoji}</button>)}</div>}
            <div><button title="Emoji" onClick={() => setEmojiOpen((value) => !value)}><SmilePlus /></button><button title="Suggest current song" disabled={!player.current} onClick={() => void suggestSong()}><Music2 /></button><input ref={inputRef} value={draft} onChange={(event) => setDraft(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); void submit(); } }} placeholder="Message the room…" maxLength={2000} /><button className="send" disabled={!draft.trim()} onClick={() => void submit()}><Send /></button></div>
          </footer>
        </>}
      </aside>
    </div>}
  </>;
}
