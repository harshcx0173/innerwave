import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class QueuedRoomSong {
  final String id;
  final MediaItem song;
  final String addedById;
  final String addedByName;
  final List<String> votes;
  final String addedAt;

  const QueuedRoomSong({
    required this.id,
    required this.song,
    required this.addedById,
    required this.addedByName,
    required this.votes,
    required this.addedAt,
  });

  factory QueuedRoomSong.fromJson(Map<String, dynamic> json) => QueuedRoomSong(
    id: json['id']?.toString() ?? '',
    song: MediaItem.fromJson(Map<String, dynamic>.from(json['song'] as Map)),
    addedById: (json['addedBy'] is Map ? json['addedBy']['id']?.toString() : null) ?? '',
    addedByName: (json['addedBy'] is Map ? json['addedBy']['name']?.toString() : null) ?? 'Listener',
    votes: (json['votes'] as List<dynamic>? ?? const []).map((e) => e.toString()).toList(),
    addedAt: json['addedAt']?.toString() ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'song': song.toJson(),
    'addedBy': {'id': addedById, 'name': addedByName},
    'votes': votes,
    'addedAt': addedAt,
  };
}

class RoomHistoryItem {
  final String? id;
  final String code;
  final String name;
  final String timestamp;
  const RoomHistoryItem({this.id, required this.code, required this.name, required this.timestamp});
  factory RoomHistoryItem.fromJson(Map<String, dynamic> json) => RoomHistoryItem(
    id: json['id']?.toString(),
    code: json['code']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    timestamp: json['timestamp']?.toString() ?? '',
  );
  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'code': code,
    'name': name,
    'timestamp': timestamp,
  };
}

class ListeningRoomController extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  AuthController? _auth; PlayerProvider? _player; RealtimeChannel? _channel;
  Timer? _syncTimer, _persistTimer; String? _userId; int _generation = 0, _revision = 0;
  final String _clientId = '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  bool _disposed = false;
  final Set<String> _knownMessageIds = {}; bool _messagesReady = false;
  ListeningRoom? _room; List<RoomMember> _members = const []; List<RoomChatMessage> _messages = const [];
  List<QueuedRoomSong> _roomQueue = const [];
  List<RoomHistoryItem> _createdRoomsHistory = const [];
  List<RoomHistoryItem> _joinedRoomsHistory = const [];
  bool _connected = false, _busy = false; String? _error;

  bool _isLive = true;
  Map<String, dynamic>? _latestHostSnapshot;

  ListeningRoom? get room => _room; List<RoomMember> get members => _members; List<RoomChatMessage> get messages => _messages;
  List<QueuedRoomSong> get roomQueue => _roomQueue;
  List<RoomHistoryItem> get createdRoomsHistory => _createdRoomsHistory;
  List<RoomHistoryItem> get joinedRoomsHistory => _joinedRoomsHistory;
  bool get connected => _connected; bool get busy => _busy; String? get error => _error;
  String? get currentUserId => _userId;
  bool get isLive => _isLive;
  bool get isInRoom => _room != null;
  bool get isHost => _room != null && _userId != null && _room!.hostId == _userId;

  void update(AuthController auth, PlayerProvider player) {
    _auth = auth; _player = player; final next = auth.user?.id;
    if (next == _userId) return; _userId = next; final generation = ++_generation; unawaited(_resetForAuth(generation));
    if (next != null) {
      unawaited(loadRoomHistory());
    }
  }

  Future<void> _resetForAuth(int generation) async {
    await _detach();
    if (generation != _generation) return;
    _room = null;
    _members = const [];
    _messages = const [];
    _roomQueue = const [];
    _createdRoomsHistory = const [];
    _joinedRoomsHistory = const [];
    _notify();
  }

  Future<void> loadRoomHistory() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final rows = await _client
          .from('listening_rooms')
          .select('id, code, name, created_at')
          .eq('host_id', userId)
          .order('created_at', ascending: false)
          .limit(30);
      _createdRoomsHistory = (rows as List)
          .map((r) => RoomHistoryItem(
                id: r['id']?.toString(),
                code: r['code']?.toString() ?? '',
                name: r['name']?.toString() ?? '',
                timestamp: r['created_at']?.toString() ?? '',
              ))
          .toList();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('innerwave_joined_rooms_$userId');
      if (saved != null) {
        final list = json.decode(saved) as List;
        _joinedRoomsHistory = list
            .map((e) => RoomHistoryItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}
    _notify();
  }

  Future<void> _recordJoinedRoom(ListeningRoom joined) async {
    final userId = _userId;
    if (userId == null || joined.hostId == userId) return;
    try {
      final item = RoomHistoryItem(
        id: joined.id,
        code: joined.code,
        name: joined.name,
        timestamp: DateTime.now().toUtc().toIso8601String(),
      );
      final next = [item, ..._joinedRoomsHistory.where((e) => e.code != joined.code)].take(30).toList();
      _joinedRoomsHistory = next;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('innerwave_joined_rooms_$userId', json.encode(next.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  Future<bool> createRoom([String name = 'My listening room']) async {
    unawaited(RoomNotificationService.requestPermission());
    _setBusy(true); try {
      final raw = await _client.rpc('create_listening_room', params: {'p_name': name.trim()});
      final created = ListeningRoom.fromJson(Map<String, dynamic>.from(raw as Map));
      await _attach(created);
      unawaited(loadRoomHistory());
      return true;
    } catch (e) { _error = e.toString(); return false; } finally { _setBusy(false); }
  }

  Future<bool> joinRoom(String code) async {
    unawaited(RoomNotificationService.requestPermission());
    _setBusy(true); try {
      final raw = await _client.rpc('join_listening_room', params: {'p_code': code.trim().toUpperCase()});
      final joined = ListeningRoom.fromJson(Map<String, dynamic>.from(raw as Map));
      await _attach(joined);
      unawaited(_recordJoinedRoom(joined));
      return true;
    } catch (e) { _error = e.toString(); return false; } finally { _setBusy(false); }
  }

  Future<void> _attach(ListeningRoom next) async {
    await _detach(); _knownMessageIds.clear(); _messagesReady = false; _room = next; _revision = next.revision;
    _isLive = true;
    _latestHostSnapshot = next.playbackState.isNotEmpty ? next.playbackState : null;
    final initialQueue = next.playbackState['roomQueue'] as List<dynamic>? ?? const [];
    _roomQueue = initialQueue.whereType<Map>().map((e) => QueuedRoomSong.fromJson(Map<String, dynamic>.from(e))).toList();

    if (next.hostId != _userId && next.playbackState.isNotEmpty) {
      await _player?.applyRemoteSnapshot(next.playbackState, playLocally: true);
    }
    await Future.wait([_loadMessages(), _loadMembers()]);
    final channel = _client.channel('room:${next.id}', opts: RealtimeChannelConfig(private: true, key: _clientId, enabled: true)); _channel = channel;
    channel.onPresenceSync((_) => _loadMembersFromPresence(channel))
      .onBroadcast(event: 'playback', callback: (raw) => unawaited(_receivePlayback(_payload(raw))))
      .onBroadcast(event: 'change_song', callback: (raw) => unawaited(_receiveChangeSong(_payload(raw))))
      .onBroadcast(event: 'skip_song', callback: (raw) => unawaited(_receiveSkipSong(_payload(raw))))
      .onBroadcast(event: 'add_to_queue', callback: (raw) => unawaited(_receiveAddToQueue(_payload(raw))))
      .onBroadcast(event: 'vote_queue', callback: (raw) => unawaited(_receiveVoteQueue(_payload(raw))))
      .onBroadcast(event: 'play_queued', callback: (raw) => unawaited(_receivePlayQueued(_payload(raw))))
      .onBroadcast(event: 'remove_from_queue', callback: (raw) => unawaited(_receiveRemoveFromQueue(_payload(raw))))
      .onBroadcast(event: 'room_queue_sync', callback: (raw) => unawaited(_receiveRoomQueueSync(_payload(raw))))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: next.id), callback: (_) => unawaited(_loadMessages()))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'message_reactions', callback: (_) => unawaited(_loadMessages()))
      .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'room_members', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'room_id', value: next.id), callback: (_) => unawaited(_loadMembers()));
    channel.subscribe((status, _) async {
      _connected = status == RealtimeSubscribeStatus.subscribed;
      _notify();
      if (_connected) {
        await channel.track({'userId': _userId, 'name': _auth?.displayName ?? 'Listener', 'clientId': _clientId});
        if (room?.hostId == _userId && _roomQueue.isNotEmpty) {
          unawaited(channel.sendBroadcastMessage(
            event: 'room_queue_sync',
            payload: {'payload': {'queue': _roomQueue.map((e) => e.toJson()).toList()}},
          ));
        }
      }
    });
    _syncTimer = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_broadcastPlayback()));
    _persistTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_persistPlayback())); _notify();
  }

  Map<String, dynamic> _payload(Map<String, dynamic> raw) => raw['payload'] is Map ? Map<String, dynamic>.from(raw['payload'] as Map) : raw;

  Future<void> _broadcastPlayback() async {
    final channel = _channel, player = _player, userId = _userId, room = _room;
    if (channel == null || player == null || userId == null || room == null) return;
    // Host-only authority: Only the host broadcasts playback state to the room
    if (room.hostId != userId) return;
    final snapshot = player.createSyncSnapshot();
    snapshot['roomQueue'] = _roomQueue.map((e) => e.toJson()).toList();
    final now = DateTime.now().millisecondsSinceEpoch;
    _revision = max(_revision + 1, now);
    try {
      await channel.sendBroadcastMessage(
        event: 'playback',
        payload: {
          'payload': {
            'origin': _clientId,
            'userId': userId,
            'revision': _revision,
            'snapshot': snapshot,
          }
        },
      );
    } catch (e) {
      debugPrint('[ListeningRoomController] broadcast failed: $e');
    }
  }

  Future<void> _receivePlayback(Map<String, dynamic> payload) async {
    final room = _room, userId = _userId;
    if (room == null || userId == null) return;
    if (room.hostId == userId) return;
    if (payload['origin'] == _clientId) return;
    final senderUserId = payload['userId']?.toString();
    if (senderUserId != null && senderUserId != room.hostId) return;

    final revision = ((payload['revision'] as num?) ?? 0).toInt();
    if (revision <= _revision) return;
    final raw = payload['snapshot'];
    if (raw is! Map) return;
    final snapshot = Map<String, dynamic>.from(raw);
    _revision = revision;
    _latestHostSnapshot = snapshot;
    if (!_isLive) return;
    await _player?.applyRemoteSnapshot(snapshot, playLocally: true);
  }

  Future<void> _receiveChangeSong(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final songRaw = payload['song'];
    if (songRaw is! Map) return;
    final song = MediaItem.fromJson(Map<String, dynamic>.from(songRaw));
    final requesterName = payload['requesterName']?.toString() ?? 'A listener';
    _player?.play(song);
    unawaited(RoomNotificationService.show(
      sender: 'Song Changed',
      body: '$requesterName started playing ${song.title}',
      messageId: 'change-${DateTime.now().millisecondsSinceEpoch}',
    ));
  }

  Future<void> _receiveSkipSong(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final direction = payload['direction']?.toString() ?? 'next';
    if (direction == 'next') {
      if (_roomQueue.isNotEmpty) {
        final top = _roomQueue.first;
        final remaining = _roomQueue.sublist(1);
        _roomQueue = remaining;
        _notify();
        unawaited(_channel?.sendBroadcastMessage(
          event: 'room_queue_sync',
          payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
        ));
        _player?.play(top.song);
      } else {
        _player?.next();
      }
    } else {
      _player?.previous();
    }
  }

  Future<void> _receiveAddToQueue(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final itemRaw = payload['item'];
    if (itemRaw is! Map) return;
    final item = QueuedRoomSong.fromJson(Map<String, dynamic>.from(itemRaw));
    if (_roomQueue.any((q) => q.song.videoId == item.song.videoId)) return;
    final nextQueue = [..._roomQueue, item];
    _roomQueue = nextQueue;
    _notify();
    unawaited(_channel?.sendBroadcastMessage(
      event: 'room_queue_sync',
      payload: {
        'payload': {
          'queue': nextQueue.map((e) => e.toJson()).toList(),
          'actorName': item.addedByName,
          'action': 'add',
          'songTitle': item.song.title,
        }
      },
    ));
  }

  Future<void> _receiveVoteQueue(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final queueItemId = payload['queueItemId']?.toString();
    final voterId = payload['userId']?.toString();
    if (queueItemId == null || voterId == null) return;
    final nextQueue = _roomQueue.map((item) {
      if (item.id != queueItemId) return item;
      final hasVoted = item.votes.contains(voterId);
      final nextVotes = hasVoted ? item.votes.where((id) => id != voterId).toList() : [...item.votes, voterId];
      return QueuedRoomSong(id: item.id, song: item.song, addedById: item.addedById, addedByName: item.addedByName, votes: nextVotes, addedAt: item.addedAt);
    }).toList();
    nextQueue.sort((a, b) => b.votes.length.compareTo(a.votes.length));
    _roomQueue = nextQueue;
    _notify();
    unawaited(_channel?.sendBroadcastMessage(
      event: 'room_queue_sync',
      payload: {'payload': {'queue': nextQueue.map((e) => e.toJson()).toList()}},
    ));
  }

  Future<void> _receivePlayQueued(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final queueItemId = payload['queueItemId']?.toString();
    if (queueItemId == null) return;
    final target = _roomQueue.where((item) => item.id == queueItemId).firstOrNull;
    if (target != null) {
      final remaining = _roomQueue.where((item) => item.id != queueItemId).toList();
      _roomQueue = remaining;
      _notify();
      unawaited(_channel?.sendBroadcastMessage(
        event: 'room_queue_sync',
        payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
      ));
      _player?.play(target.song);
    }
  }

  Future<void> _receiveRemoveFromQueue(Map<String, dynamic> payload) async {
    if (!isHost) return;
    final queueItemId = payload['queueItemId']?.toString();
    if (queueItemId == null) return;
    final remaining = _roomQueue.where((item) => item.id != queueItemId).toList();
    _roomQueue = remaining;
    _notify();
    unawaited(_channel?.sendBroadcastMessage(
      event: 'room_queue_sync',
      payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
    ));
  }

  Future<void> _receiveRoomQueueSync(Map<String, dynamic> payload) async {
    if (isHost) return;
    final rawList = payload['queue'] as List<dynamic>? ?? const [];
    _roomQueue = rawList.whereType<Map>().map((e) => QueuedRoomSong.fromJson(Map<String, dynamic>.from(e))).toList();
    _notify();
  }

  // --- Public actions for Collaborative Playback & Shared Queue ---

  void requestPlaySong(MediaItem song, [List<MediaItem>? context]) {
    if (_room == null) return;
    if (isHost) {
      _player?.play(song);
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'change_song',
        payload: {
          'payload': {
            'song': song.toJson(),
            'requesterName': _auth?.displayName ?? 'A listener',
            'requesterId': _userId ?? '',
          }
        },
      ));
    }
  }

  void requestSkipSong([String direction = 'next']) {
    if (_room == null) return;
    if (isHost) {
      if (direction == 'next') {
        if (_roomQueue.isNotEmpty) {
          final top = _roomQueue.first;
          final remaining = _roomQueue.sublist(1);
          _roomQueue = remaining;
          _notify();
          unawaited(_channel?.sendBroadcastMessage(
            event: 'room_queue_sync',
            payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
          ));
          _player?.play(top.song);
        } else {
          _player?.next();
        }
      } else {
        _player?.previous();
      }
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'skip_song',
        payload: {
          'payload': {
            'direction': direction,
            'requesterName': _auth?.displayName ?? 'A listener',
          }
        },
      ));
    }
  }

  void addToRoomQueue(MediaItem song) {
    if (_room == null) return;
    final item = QueuedRoomSong(
      id: '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}',
      song: song,
      addedById: _userId ?? '',
      addedByName: _auth?.displayName ?? 'Listener',
      votes: [_userId ?? ''],
      addedAt: DateTime.now().toUtc().toIso8601String(),
    );
    if (isHost) {
      if (!_roomQueue.any((q) => q.song.videoId == song.videoId)) {
        final nextQueue = [..._roomQueue, item];
        _roomQueue = nextQueue;
        _notify();
        unawaited(_channel?.sendBroadcastMessage(
          event: 'room_queue_sync',
          payload: {
            'payload': {
              'queue': nextQueue.map((e) => e.toJson()).toList(),
              'actorName': item.addedByName,
              'action': 'add',
              'songTitle': item.song.title,
            }
          },
        ));
      }
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'add_to_queue',
        payload: {'payload': {'item': item.toJson()}},
      ));
    }
  }

  void voteSong(String queueItemId) {
    final uid = _userId;
    if (_room == null || uid == null) return;
    if (isHost) {
      final nextQueue = _roomQueue.map((item) {
        if (item.id != queueItemId) return item;
        final hasVoted = item.votes.contains(uid);
        final nextVotes = hasVoted ? item.votes.where((id) => id != uid).toList() : [...item.votes, uid];
        return QueuedRoomSong(id: item.id, song: item.song, addedById: item.addedById, addedByName: item.addedByName, votes: nextVotes, addedAt: item.addedAt);
      }).toList();
      nextQueue.sort((a, b) => b.votes.length.compareTo(a.votes.length));
      _roomQueue = nextQueue;
      _notify();
      unawaited(_channel?.sendBroadcastMessage(
        event: 'room_queue_sync',
        payload: {'payload': {'queue': nextQueue.map((e) => e.toJson()).toList()}},
      ));
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'vote_queue',
        payload: {'payload': {'queueItemId': queueItemId, 'userId': uid}},
      ));
    }
  }

  void playQueuedSong(String queueItemId) {
    if (_room == null) return;
    if (isHost) {
      final target = _roomQueue.where((item) => item.id == queueItemId).firstOrNull;
      if (target != null) {
        final remaining = _roomQueue.where((item) => item.id != queueItemId).toList();
        _roomQueue = remaining;
        _notify();
        unawaited(_channel?.sendBroadcastMessage(
          event: 'room_queue_sync',
          payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
        ));
        _player?.play(target.song);
      }
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'play_queued',
        payload: {'payload': {'queueItemId': queueItemId}},
      ));
    }
  }

  void removeFromRoomQueue(String queueItemId) {
    if (_room == null) return;
    if (isHost) {
      final remaining = _roomQueue.where((item) => item.id != queueItemId).toList();
      _roomQueue = remaining;
      _notify();
      unawaited(_channel?.sendBroadcastMessage(
        event: 'room_queue_sync',
        payload: {'payload': {'queue': remaining.map((e) => e.toJson()).toList()}},
      ));
    } else {
      unawaited(_channel?.sendBroadcastMessage(
        event: 'remove_from_queue',
        payload: {'payload': {'queueItemId': queueItemId}},
      ));
    }
  }

  void pauseListener() {
    _isLive = false;
    _notify();
    _player?.pause();
  }

  Future<void> goLive() async {
    _isLive = true;
    _notify();
    if (_latestHostSnapshot != null) {
      await _player?.applyRemoteSnapshot(_latestHostSnapshot!, playLocally: true);
    }
  }

  Future<void> _persistPlayback() async {
    final room = _room, player = _player, userId = _userId;
    if (room == null || player == null || userId == null) return;
    // Only the host persists playback state
    if (room.hostId != userId) return;
    try {
      final snap = player.createSyncSnapshot();
      snap['roomQueue'] = _roomQueue.map((e) => e.toJson()).toList();
      await _client.from('listening_rooms').update({
        'playback_state': snap,
        'revision': _revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', room.id);
    } catch (e) {
      debugPrint('[ListeningRoomController] persist failed: $e');
    }
  }

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
  Future<void> leaveRoom() async { final active = _room; await _detach(); if (active != null && _userId != null) await _client.from('room_members').delete().eq('room_id', active.id).eq('user_id', _userId!); _room = null; _members = const []; _messages = const []; _roomQueue = const []; _notify(); }
  Future<void> _detach() async { _syncTimer?.cancel(); _persistTimer?.cancel(); _syncTimer = null; _persistTimer = null; final channel = _channel; _channel = null; if (channel != null) await _client.removeChannel(channel); _connected = false; _isLive = true; _latestHostSnapshot = null; _roomQueue = const []; }
  void _setBusy(bool value) { _busy = value; if (value) _error = null; _notify(); }
  void _notify() { if (!_disposed) notifyListeners(); }
  @override void dispose() { _disposed = true; _syncTimer?.cancel(); _persistTimer?.cancel(); if (_channel != null) unawaited(_client.removeChannel(_channel!)); super.dispose(); }
}
