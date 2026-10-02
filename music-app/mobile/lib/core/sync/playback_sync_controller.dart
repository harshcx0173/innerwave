import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_controller.dart';
import '../audio/player_provider.dart';

class PlaybackDevice {
  final String id;
  final String name;
  final String platform;

  const PlaybackDevice({
    required this.id,
    required this.name,
    required this.platform,
  });
}

class PlaybackSyncController extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  AuthController? _auth;
  PlayerProvider? _player;
  RealtimeChannel? _channel;
  Timer? _broadcastTimer;
  Timer? _persistTimer;
  Timer? _presenceReclaimTimer;
  Timer? _presenceTimer;
  StreamSubscription<Position>? _positionSubscription;
  Position? _position;
  String _locationPermission = 'unavailable';
  String? _userId;
  String? _deviceId;
  String? _activeDeviceId;
  int _revision = 0;
  bool _connected = false;
  bool _disposed = false;
  int _reconnectGeneration = 0;
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
    final generation = ++_reconnectGeneration;
    unawaited(_reconnect(generation));
  }

  Future<void> _reconnect(int generation) async {
    await _disconnect();
    if (generation != _reconnectGeneration || _disposed) return;
    final auth = _auth;
    final player = _player;
    final user = auth?.user;
    if (auth == null || player == null) return;
    await player.setSessionOwner(user?.id);
    if (generation != _reconnectGeneration || _disposed) return;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('innerwave_device_id');
    if (_deviceId == null) {
      _deviceId =
          '${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      await prefs.setString('innerwave_device_id', _deviceId!);
    }
    final deviceId = _deviceId!;
    final platform = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
        ? 'iOS'
        : Platform.operatingSystem;
    final device = {
      'id': deviceId,
      'name': 'Mobile • $platform',
      'platform': platform,
      'onlineAt': DateTime.now().toUtc().toIso8601String(),
    };
    final topic = 'innerwave:${user.id}:playback';
    final channel = _client.channel(
      topic,
      opts: RealtimeChannelConfig(private: true, key: deviceId, enabled: true),
    );
    _channel = channel;
    unawaited(_startPresenceReporting());

    channel
        .onPresenceSync((_) => _syncPresence(channel))
        .onBroadcast(
          event: 'command',
          callback: (raw) => unawaited(_receiveCommand(_payload(raw))),
        )
        .onBroadcast(
          event: 'state',
          callback: (raw) =>
              unawaited(_receiveState(_payload(raw), transfer: false)),
        )
        .onBroadcast(
          event: 'active_device',
          callback: (raw) =>
              unawaited(_receiveState(_payload(raw), transfer: true)),
        );

    Map<String, dynamic>? row;
    try {
      row = await _client
          .from('playback_sessions')
          .select('active_device_id,state,revision')
          .eq('user_id', user.id)
          .maybeSingle();
    } catch (error) {
      debugPrint(
        '[PlaybackSyncController] durable session unavailable; '
        'continuing with local playback: $error',
      );
    }
    if (_channel != channel || _disposed) return;
    _activeDeviceId = row?['active_device_id'] as String?;
    _revision = ((row?['revision'] as num?) ?? 0).toInt();
    final state = row?['state'];
    if (state is Map && state.isNotEmpty) {
      await player.applyRemoteSnapshot(
        Map<String, dynamic>.from(state),
        playLocally: _activeDeviceId == null || _activeDeviceId == deviceId,
      );
    } else {
      player.setLocalPlaybackEnabled(
        _activeDeviceId == null || _activeDeviceId == deviceId,
      );
    }

    player.setCommandInterceptor((command) {
      final target = _activeDeviceId;
      if (target == null || target == deviceId) return false;
      unawaited(
        channel.sendBroadcastMessage(
          event: 'command',
          payload: {
            'payload': {
              'id': _newId(),
              'origin': deviceId,
              'target': target,
              'command': command,
            },
          },
        ),
      );
      return true;
    });

    channel.subscribe((status, _) async {
      _connected = status == RealtimeSubscribeStatus.subscribed;
      _notify();
      if (_connected) {
        await channel.track(device);
      }
    });

    _broadcastTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_sendState(false)),
    );
    _persistTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_sendState(true)),
    );
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
    _presenceReclaimTimer?.cancel();
    final ownId = _deviceId;
    final activeId = _activeDeviceId;
    if (ownId != null &&
        unique.containsKey(ownId) &&
        (activeId == null || !unique.containsKey(activeId))) {
      _presenceReclaimTimer = Timer(const Duration(milliseconds: 800), () {
        final onlineIds = _devices.map((device) => device.id).toList()..sort();
        final elected = onlineIds.isEmpty ? null : onlineIds.first;
        final latestActive = _activeDeviceId;
        if (elected == ownId &&
            (latestActive == null || !onlineIds.contains(latestActive))) {
          unawaited(activateDevice(ownId));
        }
      });
    }
  }

  Future<void> _receiveCommand(Map<String, dynamic> payload) async {
    final player = _player;
    if (player == null ||
        payload['origin'] == _deviceId ||
        payload['target'] != _deviceId ||
        !isActiveDevice) {
      return;
    }
    final command = payload['command'];
    if (command is! Map) return;
    await player.applyRemoteCommand(Map<String, dynamic>.from(command));
    await _sendState(true);
  }

  Future<void> _receiveState(
    Map<String, dynamic> payload, {
    required bool transfer,
  }) async {
    if (payload['origin'] == _deviceId) return;
    final payloadActiveId = payload['activeDeviceId'] as String?;
    if (!transfer) {
      if (payload['origin'] != payloadActiveId) return;
      if (_activeDeviceId != null && payloadActiveId != _activeDeviceId) return;
    }
    final revision = ((payload['revision'] as num?) ?? 0).toInt();
    if (revision <= _revision) return;
    final snapshot = payload['snapshot'];
    if (snapshot is! Map) return;
    _revision = revision;
    _activeDeviceId = payloadActiveId;
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
    if (player == null ||
        user == null ||
        channel == null ||
        deviceId == null ||
        !isActiveDevice) {
      return;
    }
    final snapshot = player.createSyncSnapshot();
    final revision = ++_revision;
    final payload = {
      'origin': deviceId,
      'activeDeviceId': deviceId,
      'snapshot': snapshot,
      'revision': revision,
    };
    await channel.sendBroadcastMessage(
      event: 'state',
      payload: {'payload': payload},
    );
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
    if (player == null || user == null || channel == null || deviceId == null) {
      return;
    }
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
    await channel.sendBroadcastMessage(
      event: 'active_device',
      payload: {
        'payload': {
          'origin': deviceId,
          'activeDeviceId': targetId,
          'snapshot': snapshot,
          'revision': revision,
        },
      },
    );
    _notify();
  }

  Future<void> _disconnect() async {
    _broadcastTimer?.cancel();
    _persistTimer?.cancel();
    _presenceReclaimTimer?.cancel();
    _presenceTimer?.cancel();
    await _positionSubscription?.cancel();
    _broadcastTimer = null;
    _persistTimer = null;
    _presenceReclaimTimer = null;
    _presenceTimer = null;
    _positionSubscription = null;
    _position = null;
    _locationPermission = 'unavailable';
    _player?.setCommandInterceptor(null);
    final channel = _channel;
    _channel = null;
    if (channel != null) await _client.removeChannel(channel);
    _connected = false;
    _devices = const [];
    _activeDeviceId = null;
    _revision = 0;
    _player?.setLocalPlaybackEnabled(true);
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _startPresenceReporting() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _locationPermission = 'denied';
      } else if (await Geolocator.isLocationServiceEnabled()) {
        _locationPermission = 'granted';
        _positionSubscription =
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 50,
              ),
            ).listen((position) {
              _position = position;
              unawaited(_sendPresence());
            });
      }
    } catch (_) {
      _locationPermission = 'unavailable';
    }
    await _sendPresence();
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_sendPresence()),
    );
  }

  Future<void> _sendPresence() async {
    final auth = _auth;
    final player = _player;
    final token = auth?.session?.accessToken;
    final deviceId = _deviceId;
    if (auth?.user == null ||
        player == null ||
        token == null ||
        deviceId == null) {
      return;
    }
    final position = _position;
    final current = player.current;
    final base = player.api.baseUrl.endsWith('/')
        ? player.api.baseUrl.substring(0, player.api.baseUrl.length - 1)
        : player.api.baseUrl;
    try {
      await http
          .post(
            Uri.parse('$base/api/presence'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'platform': Platform.isAndroid
                  ? 'Android'
                  : Platform.isIOS
                  ? 'iOS'
                  : Platform.operatingSystem,
              'deviceId': deviceId,
              'isListening': player.isPlaying && current != null,
              'currentTrack': current == null
                  ? null
                  : {
                      'id': current.id,
                      'title': current.title,
                      'artists': current.artists,
                      'thumbnail': current.highResThumbnail,
                    },
              'locationPermission': _locationPermission,
              'latitude': _locationPermission == 'granted'
                  ? position?.latitude
                  : null,
              'longitude': _locationPermission == 'granted'
                  ? position?.longitude
                  : null,
              'accuracyMeters': _locationPermission == 'granted'
                  ? position?.accuracy
                  : null,
            }),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Presence analytics must never interrupt music playback.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_reconnectGeneration;
    unawaited(_disconnect());
    super.dispose();
  }
}
