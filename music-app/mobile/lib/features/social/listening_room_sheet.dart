import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/audio/player_provider.dart';
import '../../core/social/listening_room_controller.dart';

String formatRoomTime(String value, {DateTime? now}) {
  final created = DateTime.parse(value).toUtc().add(const Duration(hours: 5, minutes: 30));
  final current = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 5, minutes: 30));
  final age = current.difference(created);
  if (age.inMinutes < 60) return '${age.inMinutes.clamp(1, 59)}m';
  final clock = DateFormat('h:mm a').format(created);
  final today = DateTime(current.year, current.month, current.day), day = DateTime(created.year, created.month, created.day);
  if (day == today) return clock;
  if (today.difference(day).inDays == 1) return 'Yesterday $clock';
  return '${DateFormat('dd/MM/yyyy').format(created)} $clock';
}

class ListeningRoomSheet extends StatefulWidget {
  const ListeningRoomSheet({super.key});
  @override State<ListeningRoomSheet> createState() => _ListeningRoomSheetState();
}

class _ListeningRoomSheetState extends State<ListeningRoomSheet> {
  final _code = TextEditingController(), _name = TextEditingController(text: 'My listening room'), _message = TextEditingController();
  final _scroll = ScrollController(); bool _creating = false, _showEmoji = false; RoomChatMessage? _reply;
  static const _emojis = ['❤️', '🔥', '😂', '👏', '🎵', '😍'];
  @override void dispose() { _code.dispose(); _name.dispose(); _message.dispose(); _scroll.dispose(); super.dispose(); }

  List<RoomMember> _mentions(List<RoomMember> members) {
    final match = RegExp(r'(?:^|\s)@([\w.-]*)$').firstMatch(_message.text); if (match == null) return const [];
    final query = (match.group(1) ?? '').toLowerCase(); return members.where((m) => m.name.toLowerCase().contains(query)).take(5).toList();
  }
  void _mention(String name) { _message.text = _message.text.replaceFirst(RegExp(r'@([\w.-]*)$'), '@${name.replaceAll(' ', '_')} '); _message.selection = TextSelection.collapsed(offset: _message.text.length); setState(() {}); }
  Future<void> _send(ListeningRoomController room, {bool song = false}) async { final current = context.read<PlayerProvider>().current; final sent = await room.sendMessage(song ? 'Suggested this song' : _message.text, replyTo: _reply?.id, song: song ? current : null); if (sent && mounted) { _message.clear(); setState(() { _reply = null; _showEmoji = false; }); } }

  @override Widget build(BuildContext context) => Consumer<ListeningRoomController>(builder: (context, room, child) {
    final active = room.room; if (active == null) return _entry(room);
    final messageById = {for (final message in room.messages) message.id: message};
    WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 180), curve: Curves.easeOut); });
    return SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .88, child: Column(children: [
      ListTile(title: Text(active.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${active.code} • ${room.connected ? 'Live' : 'Connecting…'}'), leading: const CircleAvatar(backgroundColor: Color(0xFFD5FF63), child: Icon(Icons.groups, color: Colors.black)), trailing: IconButton(icon: const Icon(Icons.logout), tooltip: 'Leave room', onPressed: () => room.leaveRoom())),
      SizedBox(height: 34, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: room.members.map((m) => Padding(padding: const EdgeInsets.only(right: 7), child: Chip(avatar: CircleAvatar(backgroundColor: m.online ? const Color(0xFFD5FF63) : Colors.white12, child: Text(m.name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.black))), label: Text(m.name, style: const TextStyle(fontSize: 10))))).toList())),
      const Divider(),
      Expanded(child: room.messages.isEmpty ? const Center(child: Text('Say hello — everyone sees it instantly.', style: TextStyle(color: Colors.white54))) : ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(12, 8, 12, 18), itemCount: room.messages.length, itemBuilder: (_, index) {
        final message = room.messages[index], parent = message.replyTo == null ? null : messageById[message.replyTo]; final grouped = message.reactions.map((r) => r.emoji).toSet();
        return Align(alignment: message.senderId == room.currentUserId ? Alignment.centerRight : Alignment.centerLeft, child: GestureDetector(onLongPress: () => _reactionPicker(room, message), child: Container(width: MediaQuery.sizeOf(context).width * .82, margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: message.senderId == room.currentUserId ? const Color(0xFF29321E) : const Color(0xFF202320), borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(message.senderName, style: const TextStyle(color: Color(0xFFD5FF63), fontSize: 11, fontWeight: FontWeight.w800))), Text(formatRoomTime(message.createdAt), style: const TextStyle(color: Colors.white38, fontSize: 9)), IconButton(visualDensity: VisualDensity.compact, iconSize: 15, onPressed: () => setState(() => _reply = message), icon: const Icon(Icons.reply))]),
          if (parent != null) Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: Colors.black26, border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2))), child: Text('${parent.senderName}: ${parent.body.isEmpty ? 'Shared a song' : parent.body}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 10))),
          if (message.body.isNotEmpty) Text(message.body),
          if (message.song != null) InkWell(onTap: () => context.read<PlayerProvider>().play(message.song!), child: Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(9)), child: Row(children: [ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.network(message.song!.highResThumbnail, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => const SizedBox(width: 44, height: 44, child: Icon(Icons.music_note)))), const SizedBox(width: 9), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message.song!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), Text(message.song!.artists.join(', '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 10))])), const Icon(Icons.play_arrow, color: Color(0xFFD5FF63))]))),
          if (grouped.isNotEmpty) Wrap(spacing: 4, children: grouped.map((emoji) => ActionChip(label: Text('$emoji ${message.reactions.where((r) => r.emoji == emoji).length}', style: const TextStyle(fontSize: 10)), onPressed: () => room.toggleReaction(message.id, emoji))).toList()),
        ]))));
      })),
      if (_reply != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 13), child: Row(children: [Expanded(child: Text('Replying to ${_reply!.senderName}', style: const TextStyle(color: Colors.white54, fontSize: 11))), IconButton(onPressed: () => setState(() => _reply = null), icon: const Icon(Icons.close, size: 16))])),
      if (_mentions(room.members).isNotEmpty) SizedBox(height: 38, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: _mentions(room.members).map((m) => ActionChip(label: Text('@${m.name.replaceAll(' ', '_')}'), onPressed: () => _mention(m.name))).toList())),
      if (_showEmoji) Wrap(children: _emojis.map((emoji) => TextButton(onPressed: () { _message.text += emoji; setState(() {}); }, child: Text(emoji, style: const TextStyle(fontSize: 20)))).toList()),
      Padding(padding: EdgeInsets.fromLTRB(8, 5, 8, MediaQuery.viewInsetsOf(context).bottom + 8), child: Row(children: [IconButton(onPressed: () => setState(() => _showEmoji = !_showEmoji), icon: const Icon(Icons.emoji_emotions_outlined)), IconButton(onPressed: context.read<PlayerProvider>().current == null ? null : () => _send(room, song: true), icon: const Icon(Icons.music_note)), Expanded(child: TextField(controller: _message, onChanged: (_) => setState(() {}), onSubmitted: (_) => _send(room), decoration: const InputDecoration(hintText: 'Message the room…', isDense: true, border: OutlineInputBorder()))), IconButton(onPressed: _message.text.trim().isEmpty ? null : () => _send(room), icon: const Icon(Icons.send, color: Color(0xFFD5FF63)))])),
    ])));
  });

  Widget _entry(ListeningRoomController room) => SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.groups_2_outlined, size: 50, color: Color(0xFFD5FF63)), const SizedBox(height: 10), const Text('Listen together', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), const Text('One synchronized queue with group chat.', style: TextStyle(color: Colors.white54)), const SizedBox(height: 20),
    SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Join room')), ButtonSegment(value: true, label: Text('Create room'))], selected: {_creating}, onSelectionChanged: (value) => setState(() => _creating = value.first)), const SizedBox(height: 14),
    TextField(controller: _creating ? _name : _code, textCapitalization: _creating ? TextCapitalization.sentences : TextCapitalization.characters, maxLength: _creating ? 60 : 6, decoration: InputDecoration(labelText: _creating ? 'Room name' : '6-character room code', counterText: '')), const SizedBox(height: 10),
    SizedBox(width: double.infinity, child: FilledButton(onPressed: room.busy ? null : () => _creating ? room.createRoom(_name.text) : room.joinRoom(_code.text), child: Text(room.busy ? 'Please wait…' : _creating ? 'Create room' : 'Join room'))),
    if (room.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(room.error!, style: const TextStyle(color: Colors.redAccent, fontSize: 11))),
  ])));

  Future<void> _reactionPicker(ListeningRoomController room, RoomChatMessage message) async { final emoji = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Wrap(alignment: WrapAlignment.center, children: _emojis.map((value) => TextButton(onPressed: () => Navigator.pop(context, value), child: Text(value, style: const TextStyle(fontSize: 27)))).toList()))); if (emoji != null) await room.toggleReaction(message.id, emoji); }
}
