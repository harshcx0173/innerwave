import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/social/listening_room_controller.dart';

String formatRoomTime(String value, {DateTime? now}) {
  try {
    final created = DateTime.parse(value).toUtc().add(const Duration(hours: 5, minutes: 30));
    final current = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
    final age = current.difference(created);
    if (age.inMinutes < 60) return '${age.inMinutes.clamp(1, 59)}m';
    final clock = DateFormat('h:mm a').format(created);
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(created.year, created.month, created.day);
    if (day == today) return clock;
    if (today.difference(day).inDays == 1) return 'Yesterday $clock';
    return '${DateFormat('dd/MM/yyyy').format(created)} $clock';
  } catch (_) {
    return '';
  }
}

class ListeningRoomSheet extends StatefulWidget {
  const ListeningRoomSheet({super.key});
  @override
  State<ListeningRoomSheet> createState() => _ListeningRoomSheetState();
}

class _ListeningRoomSheetState extends State<ListeningRoomSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: 'My listening room');
  final _message = TextEditingController();
  final _scroll = ScrollController();

  int _selectedTab = 0; // 0: Chat, 1: Shared Queue, 2: Members
  int _lastKnownMessageCount = 0;
  int _unreadMessages = 0;

  bool _creating = false;
  bool _showEmoji = false;
  int _historyTab = 0; // 0: Joined, 1: Created
  RoomChatMessage? _reply;

  static const _emojis = [
    '❤️', '🔥', '😂', '👏', '🎵', '😍', '✨', '🎉',
    '🙌', '💯', '🚀', '😎', '💃', '🕺', '🥳', '🤯',
  ];

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.position.hasContentDimensions) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<RoomMember> _mentions(List<RoomMember> members) {
    final match = RegExp(r'(?:^|\s)@([\w.-]*)$').firstMatch(_message.text);
    if (match == null) return const [];
    final query = (match.group(1) ?? '').toLowerCase();
    return members.where((m) => m.name.toLowerCase().contains(query)).take(5).toList();
  }

  void _mention(String name) {
    _message.text = _message.text.replaceFirst(RegExp(r'@([\w.-]*)$'), '@${name.replaceAll(' ', '_')} ');
    _message.selection = TextSelection.collapsed(offset: _message.text.length);
    setState(() {});
  }

  Future<void> _send(ListeningRoomController room, {bool song = false}) async {
    final current = context.read<PlayerProvider>().current;
    final sent = await room.sendMessage(
      song ? 'Suggested this song' : _message.text,
      replyTo: _reply?.id,
      song: song ? current : null,
    );
    if (sent && mounted) {
      _message.clear();
      setState(() {
        _reply = null;
        _showEmoji = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) => Consumer<ListeningRoomController>(
        builder: (context, room, child) {
          final active = room.room;
          if (active == null) return _entry(room);

          // Update unread count if not on Chat tab
          if (room.messages.length > _lastKnownMessageCount) {
            if (_selectedTab != 0) {
              _unreadMessages += (room.messages.length - _lastKnownMessageCount);
            }
            _lastKnownMessageCount = room.messages.length;
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .90,
              child: Column(
                children: [
                  _header(room, active),
                  _tabBar(room),
                  const Divider(height: 1, color: Colors.white12),
                  Expanded(
                    child: switch (_selectedTab) {
                      0 => _chatView(room),
                      1 => _queueView(room),
                      _ => _membersView(room),
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

  Widget _header(ListeningRoomController room, ListeningRoom active) => ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                active.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!room.isHost)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                  room.isLive ? Icons.radio_button_checked : Icons.pause_circle_outline,
                  size: 14,
                  color: room.isLive ? const Color(0xFFD5FF63) : Colors.amber,
                ),
                label: Text(
                  room.isLive ? 'LIVE' : 'CATCH UP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: room.isLive ? const Color(0xFFD5FF63) : Colors.amber,
                  ),
                ),
                onPressed: () {
                  if (room.isLive) {
                    room.pauseListener();
                  } else {
                    room.goLive();
                  }
                },
              ),
          ],
        ),
        subtitle: Text(
          'Code: ${active.code} • ${room.isHost ? "Host (Broadcasting)" : (room.connected ? "Listening Live" : "Connecting…")}',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFD5FF63),
          child: Icon(room.isHost ? Icons.record_voice_over : Icons.headphones, color: Colors.black, size: 20),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.logout, color: Colors.redAccent),
          tooltip: 'Leave room',
          onPressed: () => room.leaveRoom(),
        ),
      );

  Widget _tabBar(ListeningRoomController room) => Container(
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _tabButton(
                icon: Icons.chat_bubble_outline,
                label: 'Chat',
                badge: _unreadMessages > 0 ? _unreadMessages : null,
                selected: _selectedTab == 0,
                onTap: () {
                  setState(() {
                    _selectedTab = 0;
                    _unreadMessages = 0;
                  });
                  _scrollToBottom();
                },
              ),
            ),
            Expanded(
              child: _tabButton(
                icon: Icons.queue_music,
                label: 'Queue',
                badge: room.roomQueue.isNotEmpty ? room.roomQueue.length : null,
                selected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
            ),
            Expanded(
              child: _tabButton(
                icon: Icons.people_outline,
                label: 'Members',
                badge: room.members.length,
                selected: _selectedTab == 2,
                onTap: () => setState(() => _selectedTab = 2),
              ),
            ),
          ],
        ),
      );

  Widget _tabButton({
    required IconData icon,
    required String label,
    int? badge,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFD5FF63).withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? const Color(0xFFD5FF63) : Colors.white70),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? const Color(0xFFD5FF63) : Colors.white70,
                ),
              ),
              if (badge != null && badge > 0) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFD5FF63) : Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  // --- TAB 1: CHAT VIEW ---

  Widget _chatView(ListeningRoomController room) {
    final messageById = {for (final message in room.messages) message.id: message};
    return Column(
      children: [
        Expanded(
          child: room.messages.isEmpty
              ? const Center(
                  child: Text(
                    'Say hello — everyone sees it instantly.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                  itemCount: room.messages.length,
                  itemBuilder: (_, index) {
                    final message = room.messages[index];
                    final parent = message.replyTo == null ? null : messageById[message.replyTo];
                    final grouped = message.reactions.map((r) => r.emoji).toSet();
                    final isMe = message.senderId == room.currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => _reactionPicker(room, message),
                        child: Container(
                          width: MediaQuery.sizeOf(context).width * .82,
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFF29321E) : const Color(0xFF202320),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isMe ? const Color(0xFFD5FF63).withValues(alpha: 0.2) : Colors.white10,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      message.senderName,
                                      style: TextStyle(
                                        color: isMe ? const Color(0xFFD5FF63) : Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    formatRoomTime(message.createdAt),
                                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 15,
                                    onPressed: () => setState(() => _reply = message),
                                    icon: const Icon(Icons.reply, color: Colors.white54),
                                  ),
                                ],
                              ),
                              if (parent != null)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    border: Border(
                                      left: BorderSide(
                                        color: Theme.of(context).colorScheme.primary,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '${parent.senderName}: ${parent.body.isEmpty ? 'Shared a song' : parent.body}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                ),
                              if (message.body.isNotEmpty)
                                Text(message.body, style: const TextStyle(fontSize: 13)),
                              if (message.song != null)
                                InkWell(
                                  onTap: () => room.requestPlaySong(message.song!),
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black38,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(5),
                                          child: Image.network(
                                            message.song!.highResThumbnail,
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) =>
                                                const SizedBox(width: 44, height: 44, child: Icon(Icons.music_note)),
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                message.song!.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                              ),
                                              Text(
                                                message.song!.artists.join(', '),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.play_circle_fill, color: Color(0xFFD5FF63), size: 28),
                                      ],
                                    ),
                                  ),
                                ),
                              if (grouped.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Wrap(
                                    spacing: 4,
                                    children: grouped
                                        .map((emoji) => ActionChip(
                                              visualDensity: VisualDensity.compact,
                                              label: Text(
                                                '$emoji ${message.reactions.where((r) => r.emoji == emoji).length}',
                                                style: const TextStyle(fontSize: 10),
                                              ),
                                              onPressed: () => room.toggleReaction(message.id, emoji),
                                            ))
                                        .toList(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_reply != null)
          Container(
            color: Colors.white10,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Replying to ${_reply!.senderName}: ${_reply!.body}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFD5FF63), fontSize: 11),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _reply = null),
                  icon: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        if (_mentions(room.members).isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _mentions(room.members)
                  .map((m) => ActionChip(
                        label: Text('@${m.name.replaceAll(' ', '_')}'),
                        onPressed: () => _mention(m.name),
                      ))
                  .toList(),
            ),
          ),
        if (_showEmoji)
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: Colors.black26,
            child: GridView.count(
              crossAxisCount: 8,
              children: _emojis
                  .map((emoji) => InkWell(
                        onTap: () {
                          _message.text += emoji;
                          setState(() {});
                        },
                        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                      ))
                  .toList(),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(8, 5, 8, MediaQuery.viewInsetsOf(context).bottom + 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _showEmoji = !_showEmoji),
                icon: Icon(
                  _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                  color: _showEmoji ? const Color(0xFFD5FF63) : Colors.white70,
                ),
              ),
              IconButton(
                tooltip: 'Share current song',
                onPressed: context.read<PlayerProvider>().current == null
                    ? null
                    : () => _send(room, song: true),
                icon: const Icon(Icons.music_note, color: Color(0xFFD5FF63)),
              ),
              Expanded(
                child: TextField(
                  controller: _message,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _send(room),
                  decoration: const InputDecoration(
                    hintText: 'Message the room…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                onPressed: _message.text.trim().isEmpty ? null : () => _send(room),
                icon: const Icon(Icons.send, color: Color(0xFFD5FF63)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- TAB 2: SHARED QUEUE VIEW ---

  Widget _queueView(ListeningRoomController room) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openAddSongSheet(room),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add to Queue', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD5FF63),
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => room.requestSkipSong('next'),
                icon: const Icon(Icons.skip_next, size: 18),
                label: Text(room.isHost ? 'Skip Song' : 'Vote Skip', style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: room.roomQueue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.queue_music, size: 48, color: Colors.white24),
                      const SizedBox(height: 8),
                      const Text('Queue is empty', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Add songs so everyone can vote and listen together.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _openAddSongSheet(room),
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Search & Add Songs'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: room.roomQueue.length,
                  itemBuilder: (_, index) {
                    final item = room.roomQueue[index];
                    final hasVoted = item.votes.contains(room.currentUserId);

                    return Card(
                      color: const Color(0xFF1E231C),
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: hasVoted ? const Color(0xFFD5FF63).withValues(alpha: 0.3) : Colors.white10,
                        ),
                      ),
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            item.song.highResThumbnail,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(width: 44, height: 44, child: Icon(Icons.music_note)),
                          ),
                        ),
                        title: Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${item.song.artists.join(', ')} • Added by ${item.addedByName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: hasVoted ? 'Unvote' : 'Vote',
                              icon: Icon(
                                hasVoted ? Icons.thumb_up : Icons.thumb_up_alt_outlined,
                                color: hasVoted ? const Color(0xFFD5FF63) : Colors.white70,
                                size: 18,
                              ),
                              onPressed: () => room.voteSong(item.id),
                            ),
                            Text('${item.votes.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: hasVoted ? const Color(0xFFD5FF63) : Colors.white70)),
                            if (room.isHost) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Play now',
                                icon: const Icon(Icons.play_arrow, color: Color(0xFFD5FF63), size: 20),
                                onPressed: () => room.playQueuedSong(item.id),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                onPressed: () => room.removeFromRoomQueue(item.id),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- TAB 3: MEMBERS VIEW ---

  Widget _membersView(ListeningRoomController room) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        Text(
          'Room Members (${room.members.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...room.members.map((m) {
          final isHost = m.userId == room.room?.hostId;
          final isMe = m.userId == room.currentUserId;

          return Card(
            color: Colors.white.withValues(alpha: 0.04),
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: m.online ? const Color(0xFFD5FF63) : Colors.white24,
                child: Text(
                  m.name.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 12),
                ),
              ),
              title: Row(
                children: [
                  Text(m.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (isMe)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('(You)', style: TextStyle(color: Color(0xFFD5FF63), fontSize: 11)),
                    ),
                ],
              ),
              subtitle: Text(
                isHost ? 'Room Host 👑' : (m.online ? 'Online' : 'Offline'),
                style: TextStyle(
                  fontSize: 10,
                  color: isHost ? const Color(0xFFD5FF63) : (m.online ? Colors.greenAccent : Colors.white38),
                ),
              ),
              trailing: isHost
                  ? const Chip(
                      label: Text('HOST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      backgroundColor: Color(0xFF29321E),
                      labelStyle: TextStyle(color: Color(0xFFD5FF63)),
                      visualDensity: VisualDensity.compact,
                    )
                  : (m.online ? const Icon(Icons.circle, color: Colors.greenAccent, size: 10) : const Icon(Icons.circle_outlined, color: Colors.white24, size: 10)),
            ),
          );
        }),
      ],
    );
  }

  // --- ENTRY VIEW: CREATE OR JOIN ROOM WITH ROOM HISTORY ---

  Widget _entry(ListeningRoomController room) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.groups_2_outlined, size: 36, color: Color(0xFFD5FF63)),
                SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Listen Together', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('Collaborative queue & synchronized music', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Join Room')),
                ButtonSegment(value: true, label: Text('Create Room')),
              ],
              selected: {_creating},
              onSelectionChanged: (value) => setState(() => _creating = value.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _creating ? _name : _code,
              textCapitalization: _creating ? TextCapitalization.sentences : TextCapitalization.characters,
              maxLength: _creating ? 60 : 6,
              decoration: InputDecoration(
                labelText: _creating ? 'Room name' : '6-digit room code',
                hintText: _creating ? 'Late night chill' : 'e.g. 7X9K2A',
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: room.busy
                    ? null
                    : () => _creating ? room.createRoom(_name.text) : room.joinRoom(_code.text),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD5FF63),
                  foregroundColor: Colors.black,
                ),
                child: Text(
                  room.busy ? 'Connecting…' : (_creating ? 'Create & Host' : 'Join Room'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            if (room.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(room.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            const SizedBox(height: 14),
            const Divider(color: Colors.white12),
            // Room History Section
            _historySection(room),
          ],
        ),
      ),
    );
  }

  Widget _historySection(ListeningRoomController room) {
    final list = _historyTab == 0 ? room.joinedRoomsHistory : room.createdRoomsHistory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent Rooms', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70)),
            Row(
              children: [
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Joined', style: TextStyle(fontSize: 10)),
                  selected: _historyTab == 0,
                  onSelected: (val) { if (val) setState(() => _historyTab = 0); },
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Created', style: TextStyle(fontSize: 10)),
                  selected: _historyTab == 1,
                  onSelected: (val) { if (val) setState(() => _historyTab = 1); },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 140,
          child: list.isEmpty
              ? Center(
                  child: Text(
                    _historyTab == 0 ? 'No joined rooms yet' : 'No created rooms yet',
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, index) {
                    final item = list[index];
                    return InkWell(
                      onTap: () {
                        _code.text = item.code;
                        setState(() => _creating = false);
                        room.joinRoom(item.code);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.history, size: 16, color: Color(0xFFD5FF63)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name.isEmpty ? 'Room' : item.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                  Text('Code: ${item.code}', style: const TextStyle(fontSize: 10, color: Colors.white38)),
                                ],
                              ),
                            ),
                            const Text('Rejoin', style: TextStyle(fontSize: 11, color: Color(0xFFD5FF63), fontWeight: FontWeight.bold)),
                            const Icon(Icons.chevron_right, size: 16, color: Color(0xFFD5FF63)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- MODAL: SEARCH & ADD TO ROOM QUEUE ---

  Future<void> _openAddSongSheet(ListeningRoomController room) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141714),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _AddSongModal(room: room),
    );
  }

  Future<void> _reactionPicker(ListeningRoomController room, RoomChatMessage message) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          alignment: WrapAlignment.center,
          children: _emojis
              .map((value) => TextButton(
                    onPressed: () => Navigator.pop(context, value),
                    child: Text(value, style: const TextStyle(fontSize: 27)),
                  ))
              .toList(),
        ),
      ),
    );
    if (emoji != null) await room.toggleReaction(message.id, emoji);
  }
}

class _AddSongModal extends StatefulWidget {
  final ListeningRoomController room;
  const _AddSongModal({required this.room});
  @override
  State<_AddSongModal> createState() => _AddSongModalState();
}

class _AddSongModalState extends State<_AddSongModal> {
  final _searchController = TextEditingController();
  List<MediaItem> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _loading = true);
      try {
        final player = context.read<PlayerProvider>();
        final res = await player.api.search(query.trim());
        if (mounted) {
          setState(() {
            _results = res.shelves
                .expand((shelf) => shelf.items)
                .where((item) => item.videoId != null)
                .toList();
            _loading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * .75,
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.viewInsetsOf(context).bottom + 12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.playlist_add, color: Color(0xFFD5FF63)),
                const SizedBox(width: 8),
                const Text('Add Song to Room Queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: _onSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search songs, artists, albums…',
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const LinearProgressIndicator(color: Color(0xFFD5FF63)),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? const Center(
                      child: Text('Search for songs to add to the shared queue', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (_, index) {
                        final song = _results[index];
                        final isAlreadyInQueue = widget.room.roomQueue.any((q) => q.song.videoId == song.videoId);

                        return ListTile(
                          dense: true,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(
                              song.highResThumbnail,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const SizedBox(width: 40, height: 40, child: Icon(Icons.music_note)),
                            ),
                          ),
                          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          subtitle: Text(song.artists.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                          trailing: isAlreadyInQueue
                              ? const Chip(
                                  label: Text('In Queue', style: TextStyle(fontSize: 9)),
                                  visualDensity: VisualDensity.compact,
                                )
                              : IconButton(
                                  icon: const Icon(Icons.add_circle, color: Color(0xFFD5FF63)),
                                  onPressed: () {
                                    widget.room.addToRoomQueue(song);
                                    Navigator.pop(context);
                                  },
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
