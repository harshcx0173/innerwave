import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import '../audio/player_provider.dart';

class PlaybackDevice {
  final String id;
  final String name;
  final String platform;

  const PlaybackDevice({required this.id, required this.name, required this.platform});
}

class PlaybackSyncController extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  AuthController? _auth;
  PlayerProvider? _player;
  RealtimeChannel? _channel;
  Timer? _broadcastTimer;
  Timer? _persistTimer;
  String? _userId;
  String? _deviceId;
  String? _activeDeviceId;
  int _revision = 0;
  bool _connected = false;
  bool _disposed = false;
  List<PlaybackDevice> _devices = const [];

  List<PlaybackDevice> get devices => _devices;
  String? get deviceId => _deviceId;
  String? get activeDeviceId => _activeDeviceId;
  bool get connected => _connected;
  bool get isActiveDevice => _deviceId != null && _deviceId == _activeDeviceId;

  void update(AuthController auth, PlayerProvider player) {
    _auth = auth;
    _player = player;
    final nextUserId = auth.user?.id;
    if (nextUserId == _userId) return;
    _userId = nextUserId;
    unawaited(_reconnect());
  }

  Future<void> _reconnect() async {
    await _disconnect();
    final auth = _auth;
    final player = _player;
    final user = auth?.user;
    if (auth == null || player == null || user == null) return;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('innerwave_device_id');
    if (_deviceId == null) {
      _deviceId = '${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      await prefs.setString('innerwave_device_id', _deviceId!);
    }
    final deviceId = _deviceId!;
    final platform = Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : Platform.operatingSystem;
    final device = {'id': deviceId, 'name': 'Mobile • $platform', 'platform': platform, 'onlineAt': DateTime.now().toUtc().toIso8601String()};
    final topic = 'innerwave:${user.id}:playback';
    final channel = _client.channel(
      topic,
      opts: RealtimeChannelConfig(private: true, key: deviceId, enabled: true),
    );
    _channel = channel;

    channel
        .onPresenceSync((_) => _syncPresence(channel))
        .onBroadcast(event: 'command', callback: (raw) => unawaited(_receiveCommand(_payload(raw))))
        .onBroadcast(event: 'state', callback: (raw) => unawaited(_receiveState(_payload(raw), transfer: false)))
        .onBroadcast(event: 'active_device', callback: (raw) => unawaited(_receiveState(_payload(raw), transfer: true)));

    final row = await _client
        .from('playback_sessions')
        .select('active_device_id,state,revision')
        .eq('user_id', user.id)
        .maybeSingle();
    if (_channel != channel || _disposed) return;
    _activeDeviceId = row?['active_device_id'] as String? ?? deviceId;
    _revision = ((row?['revision'] as num?) ?? 0).toInt();
    final state = row?['state'];
    if (state is Map && state.isNotEmpty) {
      await player.applyRemoteSnapshot(
        Map<String, dynamic>.from(state),
        playLocally: _activeDeviceId == deviceId,
      );
    } else {
      player.setLocalPlaybackEnabled(_activeDeviceId == deviceId);
    }

    player.setCommandInterceptor((command) {
      final target = _activeDeviceId;
      if (target == null || target == deviceId) return false;
      unawaited(channel.sendBroadcastMessage(event: 'command', payload: {'payload': {
        'id': _newId(), 'origin': deviceId, 'target': target, 'command': command,
      }}));
      return true;
    });

    channel.subscribe((status, _) async {
      _connected = status == RealtimeSubscribeStatus.subscribed;
      _notify();
      if (_connected) {
        await channel.track(device);
        if (row?['active_device_id'] == null) await activateDevice(deviceId);
      }
    });

    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_sendState(false)));
    _persistTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(_sendState(true)));
    _notify();
  }

  Map<String, dynamic> _payload(Map<String, dynamic> raw) {
    final value = raw['payload'];
    return value is Map ? Map<String, dynamic>.from(value) : raw;
  }

  void _syncPresence(RealtimeChannel channel) {
    final unique = <String, PlaybackDevice>{};
    for (final state in channel.presenceState()) {
      for (final presence in state.presences) {
        final payload = presence.payload;
        final id = payload['id']?.toString();
        if (id == null) continue;
        unique[id] = PlaybackDevice(
          id: id,
          name: payload['name']?.toString() ?? 'InnerWave device',
          platform: payload['platform']?.toString() ?? 'Unknown',
        );
      }
    }
    _devices = unique.values.toList();
    _notify();
  }

  Future<void> _receiveCommand(Map<String, dynamic> payload) async {
    final player = _player;
    if (player == null || payload['origin'] == _deviceId || payload['target'] != _deviceId || !isActiveDevice) return;
    final command = payload['command'];
    if (command is! Map) return;
    await player.applyRemoteCommand(Map<String, dynamic>.from(command));
    await _sendState(true);
  }

  Future<void> _receiveState(Map<String, dynamic> payload, {required bool transfer}) async {
    if (payload['origin'] == _deviceId) return;
    final revision = ((payload['revision'] as num?) ?? 0).toInt();
    if (revision < _revision) return;
    final snapshot = payload['snapshot'];
    if (snapshot is! Map) return;
    _revision = revision;
    _activeDeviceId = payload['activeDeviceId'] as String?;
    await _player?.applyRemoteSnapshot(
      Map<String, dynamic>.from(snapshot),
      playLocally: transfer && _activeDeviceId == _deviceId,
    );
    _notify();
  }

  Future<void> _sendState(bool persist) async {
    final player = _player;
    final user = _auth?.user;
    final channel = _channel;
    final deviceId = _deviceId;
    if (player == null || user == null || channel == null || deviceId == null || !isActiveDevice) return;
    final snapshot = player.createSyncSnapshot();
    final revision = ++_revision;
    final payload = {'origin': deviceId, 'activeDeviceId': deviceId, 'snapshot': snapshot, 'revision': revision};
    await channel.sendBroadcastMessage(event: 'state', payload: {'payload': payload});
    if (persist) {
      await _client.from('playback_sessions').upsert({
        'user_id': user.id,
        'active_device_id': deviceId,
        'state': snapshot,
        'revision': revision,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<void> activateDevice(String targetId) async {
    final player = _player;
    final user = _auth?.user;
    final channel = _channel;
    final deviceId = _deviceId;
    if (player == null || user == null || channel == null || deviceId == null) return;
    final snapshot = player.createSyncSnapshot();
    final revision = ++_revision;
    _activeDeviceId = targetId;
    if (targetId == deviceId) {
      await player.applyRemoteSnapshot(snapshot, playLocally: true);
    } else {
      player.setLocalPlaybackEnabled(false);
    }
    await _client.from('playback_sessions').upsert({
      'user_id': user.id,
      'active_device_id': targetId,
      'state': snapshot,
      'revision': revision,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await channel.sendBroadcastMessage(event: 'active_device', payload: {'payload': {
      'origin': deviceId, 'activeDeviceId': targetId, 'snapshot': snapshot, 'revision': revision,
    }});
    _notify();
  }

  Future<void> _disconnect() async {
    _broadcastTimer?.cancel();
    _persistTimer?.cancel();
    _broadcastTimer = null;
    _persistTimer = null;
    _player?.setCommandInterceptor(null);
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel);
    _connected = false;
    _devices = const [];
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  void _notify() { if (!_disposed) notifyListeners(); }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_disconnect());
    super.dispose();
  }
}
