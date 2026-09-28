import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../api/music_api.dart';
import '../models/media_model.dart';

enum PlayRepeatMode { off, all, one }

class PlayerProvider extends ChangeNotifier {
  final MusicApi api;
  YoutubePlayerController? _youtubeController;
  bool _transportInitialized = false;

  MediaItem? _current;
  List<MediaItem> _queue = [];
  int _queueIndex = 0;
  String? _queueContinuation;
  bool _isLoadingQueue = false;
  int _streamRequestId = 0;
  String? _loadedVideoId;
  final Set<String> _seenIds = {};

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _error;

  PlayRepeatMode _repeatMode = PlayRepeatMode.off;
  bool _shuffle = false;
  List<MediaItem> _originalQueue = [];
  List<MediaItem> _history = [];
  Map<String, int> _playCounts = {};
  Set<String> _likedIds = {};
  List<MediaItem> _likedSongs = [];
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndsAt;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _bufferedSubscription;
  PlayerState _lastPlayerState = PlayerState.unknown;

  PlayerProvider({required this.api}) {
    _initAudioSession();
    _restoreSession();
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {}
  }

  MediaItem? get current => _current;
  List<MediaItem> get queue => _queue;
  int get queueIndex => _queueIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  String? get error => _error;
  PlayRepeatMode get repeatMode => _repeatMode;
  bool get shuffle => _shuffle;
  List<MediaItem> get history => _history;
  Set<String> get likedIds => _likedIds;
  List<MediaItem> get likedSongs => _likedSongs;
  YoutubePlayerController get youtubeController {
    _youtubeController ??= YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        enableCaption: false,
        pointerEvents: PointerEvents.none,
        playsInline: true,
        privacyEnhancedMode: false,
        videoStateUpdateInterval: 250,
      ),
    );
    if (!_transportInitialized) {
      _transportInitialized = true;
      _initAudioStreams(_youtubeController!);
    }
    return _youtubeController!;
  }

  bool isLiked(String id) => _likedIds.contains(id);

  bool get hasSleepTimer =>
      _sleepTimerEndsAt != null && _sleepTimerEndsAt!.isAfter(DateTime.now());
  Duration? get sleepTimerRemaining =>
      _sleepTimerEndsAt?.difference(DateTime.now());

  void toggleLike(MediaItem item) async {
    if (_likedIds.contains(item.id)) {
      _likedIds.remove(item.id);
      _likedSongs.removeWhere((e) => e.id == item.id);
    } else {
      _likedIds.add(item.id);
      if (!_likedSongs.any((e) => e.id == item.id)) {
        _likedSongs.insert(0, item);
      }
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'innerwave_mobile_liked_ids',
        _likedIds.toList(),
      );
      final jsonList = _likedSongs.map((e) => e.toJson()).toList();
      await prefs.setString(
        'innerwave_mobile_liked_songs',
        json.encode(jsonList),
      );
    } catch (_) {}
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      youtubeController.pauseVideo();
      _sleepTimerEndsAt = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimerEndsAt = null;
    notifyListeners();
  }

  List<MediaItem> get mostReplayed {
    if (_history.isEmpty) return [];
    final items = List<MediaItem>.from(_history);
    items.sort(
      (a, b) => (_playCounts[b.id] ?? 1).compareTo(_playCounts[a.id] ?? 1),
    );
    return items.take(12).toList();
  }

  void _initAudioStreams(YoutubePlayerController controller) {
    _playerStateSubscription = controller.stream.listen((value) {
      final state = value.playerState;
      _isPlaying = state == PlayerState.playing;
      if (state == PlayerState.ended && _lastPlayerState != PlayerState.ended) {
        _onTrackEnded();
      }
      _lastPlayerState = state;
      notifyListeners();
    });

    _positionSubscription = controller.videoStateStream.listen((state) async {
      _position = state.position;
      if (_duration == Duration.zero) {
        final seconds = await controller.duration;
        if (seconds > 0) {
          _duration = Duration(milliseconds: (seconds * 1000).round());
        }
      }
      _bufferedPosition = Duration(
        milliseconds: (_duration.inMilliseconds * state.loadedFraction).round(),
      );
      notifyListeners();
    });
  }

  Future<void> _restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedJson = prefs.getString('innertube_mobile_session');
      if (savedJson != null) {
        final data = json.decode(savedJson) as Map<String, dynamic>;
        if (data['current'] != null) {
          _current = MediaItem.fromJson(data['current']);
          if (data['queue'] is List) {
            _queue = (data['queue'] as List)
                .map((e) => MediaItem.fromJson(e))
                .toList();
          }
          _queueIndex = data['queueIndex'] as int? ?? 0;
          _queueContinuation = data['continuation'] as String?;
          _seenIds.addAll(_queue.map((e) => e.id));
        }
      }

      final historyJson = prefs.getString('innerwave_mobile_history');
      if (historyJson != null) {
        final raw = json.decode(historyJson) as List<dynamic>;
        _history = raw
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      final countsJson = prefs.getString('innerwave_mobile_play_counts');
      if (countsJson != null) {
        final rawCounts = json.decode(countsJson) as Map<String, dynamic>;
        _playCounts = rawCounts.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      final likedList = prefs.getStringList('innerwave_mobile_liked_ids');
      if (likedList != null) {
        _likedIds = likedList.toSet();
      }

      final likedSongsJson = prefs.getString('innerwave_mobile_liked_songs');
      if (likedSongsJson != null) {
        final raw = json.decode(likedSongsJson) as List<dynamic>;
        _likedSongs = raw
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _persistSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_current == null) return;
      final data = {
        'current': _current!.toJson(),
        'queue': _queue.map((e) => e.toJson()).toList(),
        'queueIndex': _queueIndex,
        'continuation': _queueContinuation,
      };
      await prefs.setString('innertube_mobile_session', json.encode(data));

      // Save to recent history
      _history.removeWhere((item) => item.id == _current!.id);
      _history.insert(0, _current!);
      if (_history.length > 50) _history = _history.sublist(0, 50);
      await prefs.setString(
        'innerwave_mobile_history',
        json.encode(_history.map((e) => e.toJson()).toList()),
      );

      // Increment and save play count
      _playCounts[_current!.id] = (_playCounts[_current!.id] ?? 0) + 1;
      await prefs.setString(
        'innerwave_mobile_play_counts',
        json.encode(_playCounts),
      );
    } catch (_) {}
  }

  Future<void> play(MediaItem item, [List<MediaItem>? contextList]) async {
    if (item.videoId == null) return;

    _error = null;
    _current = item;

    if (contextList != null && contextList.isNotEmpty) {
      final playable = contextList.where((e) => e.videoId != null).toList();
      final idx = playable.indexWhere((e) => e.id == item.id);
      _queue = playable.isNotEmpty ? playable : [item];
      _queueIndex = idx >= 0 ? idx : 0;
      _queueContinuation = null;
    } else {
      _queue = [item];
      _queueIndex = 0;
      _fetchRadioQueue(item.videoId!);
    }

    _seenIds.add(item.id);
    _originalQueue = List.from(_queue);

    notifyListeners();
    _loadAndPlayStream(item.videoId!);
    _persistSession();
  }

  Future<void> _loadAndPlayStream(String videoId) async {
    final requestId = ++_streamRequestId;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _isPlaying = false;
    try {
      // Use YouTube's supported iframe transport on the listener's device.
      // Direct googlevideo URLs are session-bound and return 403 in ExoPlayer.
      await youtubeController.loadVideoById(videoId: videoId);
      if (requestId != _streamRequestId) return;
      _loadedVideoId = videoId;
      _error = null;
    } catch (_) {
      if (requestId != _streamRequestId) return;
      _error = 'Unable to play this track from YouTube. Try another track or network.';
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> _fetchRadioQueue(String videoId) async {
    try {
      final result = await api.getRadioQueue(
        videoId: videoId,
        title: _current?.title,
        artist: _current?.artists.join(', '),
      );
      final items = result['items'] as List<MediaItem>;
      final continuation = result['continuation'] as String?;

      final fresh = items
          .where((e) => e.id != _current?.id && !_seenIds.contains(e.id))
          .toList();
      for (final it in fresh) {
        _seenIds.add(it.id);
      }

      if (fresh.isNotEmpty) {
        _queue = [_current!, ...fresh];
        _originalQueue = List.from(_queue);
        _queueIndex = 0;
        _queueContinuation = continuation;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> loadMoreQueue() async {
    if (_isLoadingQueue ||
        _queueContinuation == null ||
        _current?.videoId == null)
      return;
    _isLoadingQueue = true;

    try {
      final result = await api.getRadioQueue(
        videoId: _current!.videoId!,
        continuation: _queueContinuation,
      );
      final items = result['items'] as List<MediaItem>;
      final continuation = result['continuation'] as String?;

      final existingIds = _queue.map((e) => e.id).toSet();
      final fresh = items
          .where((e) => !existingIds.contains(e.id) && !_seenIds.contains(e.id))
          .toList();
      for (final it in fresh) {
        _seenIds.add(it.id);
      }

      if (fresh.isNotEmpty) {
        _queue.addAll(fresh);
        _originalQueue = List.from(_queue);
        _queueContinuation = continuation;
        notifyListeners();
      }
    } catch (_) {
      _queueContinuation = null;
    } finally {
      _isLoadingQueue = false;
    }
  }

  void togglePlayPause() {
    if (_current == null) return;
    final videoId = _current!.videoId;
    if (videoId != null && _loadedVideoId != videoId) {
      _loadAndPlayStream(videoId);
      return;
    }
    if (_isPlaying) {
      youtubeController.pauseVideo();
    } else {
      youtubeController.playVideo();
    }
  }

  void next() {
    if (_queueIndex + 1 < _queue.length) {
      _queueIndex++;
      final nextItem = _queue[_queueIndex];
      _current = nextItem;
      _seenIds.add(nextItem.id);
      notifyListeners();
      if (nextItem.videoId != null) {
        _loadAndPlayStream(nextItem.videoId!);
      }
      _persistSession();

      if (_queue.length - _queueIndex <= 6) {
        loadMoreQueue();
      }
    } else {
      youtubeController.stopVideo();
      _isPlaying = false;
      notifyListeners();
    }
  }

  void previous() {
    if (_position.inSeconds > 4) {
      youtubeController.seekTo(seconds: 0, allowSeekAhead: true);
      return;
    }

    if (_queueIndex > 0) {
      _queueIndex--;
      final prevItem = _queue[_queueIndex];
      _current = prevItem;
      _seenIds.add(prevItem.id);
      notifyListeners();
      if (prevItem.videoId != null) {
        _loadAndPlayStream(prevItem.videoId!);
      }
      _persistSession();
    } else {
      youtubeController.seekTo(seconds: 0, allowSeekAhead: true);
    }
  }

  void seek(Duration position) {
    youtubeController.seekTo(
      seconds: position.inMilliseconds / 1000,
      allowSeekAhead: true,
    );
  }

  void _onTrackEnded() {
    if (_repeatMode == PlayRepeatMode.one) {
      youtubeController.seekTo(seconds: 0, allowSeekAhead: true);
      youtubeController.playVideo();
    } else {
      next();
    }
  }

  void toggleRepeat() {
    if (_repeatMode == PlayRepeatMode.off) {
      _repeatMode = PlayRepeatMode.all;
    } else if (_repeatMode == PlayRepeatMode.all) {
      _repeatMode = PlayRepeatMode.one;
    } else {
      _repeatMode = PlayRepeatMode.off;
    }
    notifyListeners();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle && _queue.isNotEmpty) {
      final currentItem = _current;
      final rest = _queue.where((e) => e.id != currentItem?.id).toList()
        ..shuffle();
      _queue = currentItem != null ? [currentItem, ...rest] : rest;
      _queueIndex = 0;
    } else {
      _queue = List.from(_originalQueue);
      if (_current != null) {
        _queueIndex = _queue
            .indexWhere((e) => e.id == _current!.id)
            .clamp(0, _queue.length - 1);
      }
    }
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length)
      return;
    if (oldIndex == _queueIndex) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    if (_queueIndex > oldIndex && _queueIndex <= newIndex) {
      _queueIndex--;
    } else if (_queueIndex < oldIndex && _queueIndex >= newIndex) {
      _queueIndex++;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferedSubscription?.cancel();
    _youtubeController?.close();
    super.dispose();
  }
}
