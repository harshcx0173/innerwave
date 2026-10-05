import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import '../audio/player_provider.dart';
import '../models/media_model.dart';
import 'room_notification_service.dart';

class ListeningRoom {
  final String id, code, name, hostId;
  final int revision;
  final Map<String, dynamic> playbackState;
  const ListeningRoom({required this.id, required this.code, required this.name, required this.hostId, required this.revision, required this.playbackState});
  factory ListeningRoom.fromJson(Map<String, dynamic> json) => ListeningRoom(
    id: json['id'].toString(), code: json['code'].toString(), name: json['name']?.toString() ?? 'Listening room',
    hostId: json['host_id'].toString(), revision: ((json['revision'] as num?) ?? 0).toInt(),
    playbackState: json['playback_state'] is Map ? Map<String, dynamic>.from(json['playback_state'] as Map) : {},
  );
}

class RoomMember {
  final String userId, name, role; final bool online;
  const RoomMember({required this.userId, required this.name, required this.role, required this.online});
}

class RoomReaction {
  final String userId, emoji;
  const RoomReaction(this.userId, this.emoji);
}

class RoomChatMessage {
  final String id, senderId, senderName, body, createdAt;
  final String? replyTo; final MediaItem? song; final List<RoomReaction> reactions;
  const RoomChatMessage({required this.id, required this.senderId, required this.senderName, required this.body, required this.createdAt, this.replyTo, this.song, this.reactions = const []});
}

class ListeningRoomController extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  AuthController? _auth; PlayerProvider? _player; RealtimeChannel? _channel;
  Timer? _syncTimer, _persistTimer; String? _userId; int _generation = 0, _revision = 0, _suppressUntil = 0;
  final String _clientId = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  String? _controllerId; Map<String, dynamic>? _lastSnapshot; bool _disposed = false;
  final Set<String> _knownMessageIds = {}; bool _messagesReady = false;
  ListeningRoom? _room; List<RoomMember> _members = const []; List<RoomChatMessage> _messages = const [];
  bool _connected = false, _busy = false; String? _error;

  ListeningRoom? get room => _room; List<RoomMember> get members => _members; List<RoomChatMessage> get messages => _messages;
  bool get connected => _connected; bool get busy => _busy; String? get error => _error;
  String? get currentUserId => _userId;

  void update(AuthController auth, PlayerProvider player) {
    _auth = auth; _player = player; final next = auth.user?.id;
    if (next == _userId) return; _userId = next; final generation = ++_generation; unawaited(_resetForAuth(generation));
  }

  Future<void> _resetForAuth(int generation) async { await _detach(); if (generation != _generation) return; _room = null; _members = const []; _messages = const []; _notify(); }

  Future<bool> createRoom([String name = 'My listening room']) async {
    unawaited(RoomNotificationService.requestPermission());
    _setBusy(true); try {
      final raw = await _client.rpc('create_listening_room', params: {'p_name': name.trim()});
      await _attach(ListeningRoom.fromJson(Map<String, dynamic>.from(raw as Map))); return true;
    } catch (e) { _error = e.toString(); return false; } finally { _setBusy(false); }
  }

  Future<bool> joinRoom(String code) async {
    unawaited(RoomNotificationService.requestPermission());
    _setBusy(true); try {
      final raw = await _client.rpc('join_listening_room', params: {'p_code': code.trim().toUpperCase()});
      await _attach(ListeningRoom.fromJson(Map<String, dynamic>.from(raw as Map))); return true;
    } catch (e) { _error = e.toString(); return false; } finally { _setBusy(false); }
  }

  Future<void> _attach(ListeningRoom next) async {
    await _detach(); _knownMessageIds.clear(); _messagesReady = false; _room = next; _revision = next.revision; _controllerId = next.hostId == _userId ? _clientId : null;
    if (next.playbackState.isNotEmpty) { _suppressUntil = DateTime.now().millisecondsSinceEpoch + 1200; await _player?.applyRemoteSnapshot(next.playbackState, playLocally: true); _lastSnapshot = next.playbackState; }
    await Future.wait([_loadMessages(), _loadMembers()]);
    final channel = _client.channel('room:${next.id}', opts: RealtimeChannelConfig(private: true, key: _clientId, enabled: true)); _channel = channel;
    channel.onPresenceSync((_) => _loadMembersFromPresence(channel))
      .onBroadcast(event: 'playback', callback: (raw) => unawaited(_receivePlayback(_payload(raw))))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: next.id), callback: (_) => unawaited(_loadMessages()))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'message_reactions', callback: (_) => unawaited(_loadMessages()))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_members', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: next.id), callback: (_) => unawaited(_loadMembers()));
    channel.subscribe((status, _) async { _connected = status == RealtimeSubscribeStatus.subscribed; _notify(); if (_connected) await channel.track({'userId': _userId, 'name': _auth?.displayName ?? 'Listener', 'clientId': _clientId}); });
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_broadcastPlayback()));
    _persistTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_persistPlayback())); _notify();
  }

  Map<String, dynamic> _payload(Map<String, dynamic> raw) => raw['payload'] is Map ? Map<String, dynamic>.from(raw['payload'] as Map) : raw;
  bool _significant(Map<String, dynamic>? a, Map<String, dynamic> b) {
    if (a == null) return true;
    final ac = a['current'] is Map ? (a['current'] as Map)['id'] : null, bc = b['current'] is Map ? (b['current'] as Map)['id'] : null;
    return ac != bc || a['queueIndex'] != b['queueIndex'] || a['isPlaying'] != b['isPlaying'] ||
      ((((a['volume'] as num?) ?? 0).toDouble() - ((b['volume'] as num?) ?? 0).toDouble()).abs() > .02) ||
      ((((a['currentTime'] as num?) ?? 0).toDouble() - ((b['currentTime'] as num?) ?? 0).toDouble()).abs() > 2.25);
  }

  Future<void> _broadcastPlayback() async {
    final channel = _channel, player = _player, userId = _userId; if (channel == null || player == null || userId == null) return;
    final snapshot = player.createSyncSnapshot(); final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= _suppressUntil && _significant(_lastSnapshot, snapshot)) _controllerId = _clientId; _lastSnapshot = snapshot;
    if (_controllerId != _clientId) return; _revision = max(_revision + 1, now);
    await channel.sendBroadcastMessage(event: 'playback', payload: {'payload': {'origin': _clientId, 'userId': userId, 'revision': _revision, 'snapshot': snapshot}});
  }

  Future<void> _receivePlayback(Map<String, dynamic> payload) async {
    if (payload['origin'] == _clientId) return; final revision = ((payload['revision'] as num?) ?? 0).toInt(); if (revision <= _revision) return;
    final raw = payload['snapshot']; if (raw is! Map) return; final snapshot = Map<String, dynamic>.from(raw);
    _revision = revision; _controllerId = payload['origin']?.toString(); _suppressUntil = DateTime.now().millisecondsSinceEpoch + 900; _lastSnapshot = snapshot;
    await _player?.applyRemoteSnapshot(snapshot, playLocally: true);
  }

  Future<void> _persistPlayback() async { if (_controllerId != _clientId || _room == null || _player == null) return; await _client.from('listening_rooms').update({'playback_state': _player!.createSyncSnapshot(), 'revision': _revision, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', _room!.id); }

  Future<void> _loadMembers([Set<String>? online]) async {
    final active = _room; if (active == null) return; final rows = await _client.from('room_members').select('user_id,role').eq('room_id', active.id);
    final ids = (rows as List).map((e) => e['user_id'].toString()).toList(); final profiles = ids.isEmpty ? <dynamic>[] : await _client.from('profiles').select('id,display_name').inFilter('id', ids);
    final names = {for (final p in profiles) p['id'].toString(): p['display_name']?.toString() ?? 'Listener'};
    _members = (rows as List).map((e) => RoomMember(userId: e['user_id'].toString(), name: names[e['user_id'].toString()] ?? (e['user_id'] == _userId ? _auth?.displayName ?? 'You' : 'Listener'), role: e['role'].toString(), online: online?.contains(e['user_id'].toString()) ?? false)).toList(); _notify();
  }

  void _loadMembersFromPresence(RealtimeChannel channel) { final online = <String>{}; for (final state in channel.presenceState()) { for (final p in state.presences) { final id = p.payload['userId']?.toString(); if (id != null) online.add(id); } } unawaited(_loadMembers(online)); }

  Future<void> _loadMessages() async {
    final active = _room; if (active == null) return; final rows = await _client.from('room_messages').select('id,sender_id,body,reply_to,song,created_at').eq('room_id', active.id).order('created_at').limit(200);
    final list = rows as List; final senderIds = list.map((e) => e['sender_id'].toString()).toSet().toList(); final messageIds = list.map((e) => e['id'].toString()).toList();
    final profiles = senderIds.isEmpty ? <dynamic>[] : await _client.from('profiles').select('id,display_name').inFilter('id', senderIds);
    final reactions = messageIds.isEmpty ? <dynamic>[] : await _client.from('message_reactions').select('message_id,user_id,emoji').inFilter('message_id', messageIds);
    final names = {for (final p in profiles) p['id'].toString(): p['display_name']?.toString() ?? 'Listener'};
    final nextMessages = list.map((e) { final senderId = e['sender_id'].toString(); return RoomChatMessage(id: e['id'].toString(), senderId: senderId, senderName: names[senderId] ?? (senderId == _userId ? _auth?.displayName ?? 'You' : 'Listener'), body: e['body']?.toString() ?? '', createdAt: e['created_at'].toString(), replyTo: e['reply_to']?.toString(), song: e['song'] is Map ? MediaItem.fromJson(Map<String, dynamic>.from(e['song'] as Map)) : null, reactions: reactions.where((r) => r['message_id'].toString() == e['id'].toString()).map((r) => RoomReaction(r['user_id'].toString(), r['emoji'].toString())).toList()); }).toList();
    final fresh = _messagesReady ? nextMessages.where((message) => !_knownMessageIds.contains(message.id) && message.senderId != _userId).toList() : <RoomChatMessage>[];
    _knownMessageIds..clear()..addAll(nextMessages.map((message) => message.id)); _messagesReady = true; _messages = nextMessages; _notify();
    if (fresh.isNotEmpty) { final newest = fresh.last; unawaited(RoomNotificationService.show(sender: newest.senderName, body: newest.song != null ? '🎵 ${newest.song!.title}' : newest.body, messageId: newest.id)); }
  }

  Future<bool> sendMessage(String body, {String? replyTo, MediaItem? song}) async { if (_room == null || _userId == null || (body.trim().isEmpty && song == null)) return false; try { await _client.from('room_messages').insert({'room_id': _room!.id, 'sender_id': _userId, 'body': body.trim(), 'reply_to': replyTo, 'song': song?.toJson()}); await _loadMessages(); return true; } catch (e) { _error = e.toString(); _notify(); return false; } }
  Future<void> toggleReaction(String messageId, String emoji) async { if (_userId == null) return; final exists = _messages.any((m) => m.id == messageId && m.reactions.any((r) => r.userId == _userId && r.emoji == emoji)); if (exists) { await _client.from('message_reactions').delete().eq('message_id', messageId).eq('user_id', _userId!).eq('emoji', emoji); } else { await _client.from('message_reactions').insert({'message_id': messageId, 'user_id': _userId, 'emoji': emoji}); } await _loadMessages(); }
  Future<void> leaveRoom() async { final active = _room; await _detach(); if (active != null && _userId != null) await _client.from('room_members').delete().eq('room_id', active.id).eq('user_id', _userId!); _room = null; _members = const []; _messages = const []; _notify(); }
  Future<void> _detach() async { _syncTimer?.cancel(); _persistTimer?.cancel(); _syncTimer = null; _persistTimer = null; final channel = _channel; _channel = null; if (channel != null) await _client.removeChannel(channel); _connected = false; _controllerId = null; }
  void _setBusy(bool value) { _busy = value; if (value) _error = null; _notify(); }
  void _notify() { if (!_disposed) notifyListeners(); }
  @override void dispose() { _disposed = true; _syncTimer?.cancel(); _persistTimer?.cancel(); if (_channel != null) unawaited(_client.removeChannel(_channel!)); super.dispose(); }
}
