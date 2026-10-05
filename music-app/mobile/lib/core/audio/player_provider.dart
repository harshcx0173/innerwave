import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../api/music_api.dart';
import '../models/media_model.dart';
import 'innerwave_audio_handler.dart';

enum PlayRepeatMode { off, all, one }

class PlayerProvider extends ChangeNotifier {
  final MusicApi api;
  final InnerWaveAudioHandler? audioHandler;
  final ja.AudioPlayer _audioPlayer = ja.AudioPlayer();
  final YoutubeExplode _youtube = YoutubeExplode();

  MediaItem? _current;
  List<MediaItem> _queue = [];
  int _queueIndex = 0;
  String? _queueContinuation;
  bool _isLoadingQueue = false;
  int _queueRequestId = 0;
  int _streamRequestId = 0;
  String? _loadedVideoId;
  String? _sessionOwnerId;
  int _sessionGeneration = 0;
  final Set<String> _seenIds = {};
  LyricsResponse? _currentLyrics;
  int _lyricsRequestId = 0;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferedPosition = Duration.zero;
  String? _error;
  double _volume = 0.8;
  bool _localPlaybackEnabled = true;
  bool _applyingRemoteCommand = false;
  bool Function(Map<String, dynamic> command)? _commandInterceptor;

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
  ja.ProcessingState _lastProcessingState = ja.ProcessingState.idle;

  PlayerProvider({required this.api, this.audioHandler}) {
    unawaited(_audioPlayer.setVolume(_volume));
    _initAudioSession();
    _initAudioServiceBridge();
    _initAudioStreams();
  }

  void _initAudioServiceBridge() {
    if (audioHandler == null) return;
    audioHandler!.onPlayCallback = () async => togglePlayPause();
    audioHandler!.onPauseCallback = () async => togglePlayPause();
    audioHandler!.onNextCallback = () async => next();
    audioHandler!.onPreviousCallback = () async => previous();
    audioHandler!.onSeekCallback = (pos) async => seek(pos);
    audioHandler!.onStopCallback = () async {
      unawaited(_audioPlayer.stop());
      _isPlaying = false;
      notifyListeners();
      _syncAudioService();
    };
  }

  void _syncAudioService() {
    if (audioHandler == null || _current == null) return;
    audioHandler!.setMediaItem(
      id: _current!.id,
      title: _current!.title,
      artist: _current!.artists.isNotEmpty
          ? _current!.artists.join(', ')
          : _current!.subtitle,
      album: 'InnerWave',
      artworkUrl: _current!.highResThumbnail,
      duration: _duration > Duration.zero ? _duration : null,
    );
    audioHandler!.updatePlaybackState(
      isPlaying: _isPlaying,
      processingState: _lastProcessingState,
      position: _position,
      bufferedPosition: _bufferedPosition,
      duration: _duration,
      hasNext: _queueIndex + 1 < _queue.length || _queueContinuation != null,
      hasPrevious: _queueIndex > 0 || _position.inSeconds > 4,
    );
  }

  Future<void> _preloadLyricsAndRelated(MediaItem item) async {
    final requestId = ++_lyricsRequestId;
    final videoId = item.videoId ?? item.id;
    final artist = item.artists.isNotEmpty
        ? item.artists.first
        : (item.subtitle.isNotEmpty ? item.subtitle : null);
    try {
      final lyrics = await api.getLyrics(
        videoId: videoId,
        title: item.title,
        artist: artist,
      );
      if (requestId != _lyricsRequestId || _current?.id != item.id) return;
      _currentLyrics = lyrics;
      notifyListeners();
    } catch (_) {}

    try {
      unawaited(api.getRelated(videoId, title: item.title, artist: artist));
    } catch (_) {}
  }

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(_volume * 0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_isPlaying) {
                unawaited(_audioPlayer.pause());
              }
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _audioPlayer.setVolume(_volume);
              break;
            case AudioInterruptionType.pause:
              unawaited(_audioPlayer.play());
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        unawaited(_audioPlayer.pause());
      });
    } catch (_) {}
  }

  MediaItem? get current => _current;
  List<MediaItem> get queue => _queue;
  int get queueIndex => _queueIndex;
  bool get isLoadingQueue => _isLoadingQueue;
  bool get hasMoreQueue => _queueContinuation != null;
  LyricsResponse? get currentLyrics => _currentLyrics;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  Duration get bufferedPosition => _bufferedPosition;
  String? get error => _error;
  double get volume => _volume;
  bool get localPlaybackEnabled => _localPlaybackEnabled;
  PlayRepeatMode get repeatMode => _repeatMode;
  bool get shuffle => _shuffle;
  List<MediaItem> get history => _history;
  Set<String> get likedIds => _likedIds;
  List<MediaItem> get likedSongs => _likedSongs;
  bool isLiked(String id) => _likedIds.contains(id);

  String _userKey(String base, String userId) => '$base:$userId';

  Future<void> setSessionOwner(String? userId) async {
    if (_sessionOwnerId == userId) return;
    final generation = ++_sessionGeneration;
    _sessionOwnerId = userId;
    ++_queueRequestId;
    ++_streamRequestId;
    _commandInterceptor = null;
    _localPlaybackEnabled = true;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    await _audioPlayer.stop();
    if (_sessionGeneration != generation || _sessionOwnerId != userId) return;
    _loadedVideoId = null;
    _current = null;
    _queue = [];
    _originalQueue = [];
    _queueIndex = 0;
    _queueContinuation = null;
    _isLoadingQueue = false;
    _seenIds.clear();
    _currentLyrics = null;
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    _error = null;
    _lastProcessingState = ja.ProcessingState.idle;
    _history = [];
    _playCounts = {};
    _likedIds = {};
    _likedSongs = [];
    audioHandler?.clearMediaItem();
    notifyListeners();
    if (userId != null) await _restoreSession(userId, generation);
  }

  bool get hasSleepTimer =>
      _sleepTimerEndsAt != null && _sleepTimerEndsAt!.isAfter(DateTime.now());
  Duration? get sleepTimerRemaining =>
      _sleepTimerEndsAt?.difference(DateTime.now());

  void toggleLike(MediaItem item) async {
    final ownerId = _sessionOwnerId;
    if (ownerId == null) return;
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
      if (_sessionOwnerId != ownerId) return;
      await prefs.setStringList(
        _userKey('innerwave_mobile_liked_ids', ownerId),
        _likedIds.toList(),
      );
      final jsonList = _likedSongs.map((e) => e.toJson()).toList();
      await prefs.setString(
        _userKey('innerwave_mobile_liked_songs', ownerId),
        json.encode(jsonList),
      );
    } catch (_) {}
  }

  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTimerEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      unawaited(_audioPlayer.pause());
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

  void _initAudioStreams() {
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (!_localPlaybackEnabled) return;
      _isPlaying = state.playing;
      if (state.processingState == ja.ProcessingState.completed &&
          _lastProcessingState != ja.ProcessingState.completed) {
        _onTrackEnded();
      }
      _lastProcessingState = state.processingState;
      notifyListeners();
      _syncAudioService();
    });

    _positionSubscription = _audioPlayer.positionStream.listen((position) {
      if (!_localPlaybackEnabled) return;
      _position = position;
      notifyListeners();
    });
    _durationSubscription = _audioPlayer.durationStream.listen((duration) {
      if (!_localPlaybackEnabled) return;
      _duration = duration ?? Duration.zero;
      notifyListeners();
      _syncAudioService();
    });
    _bufferedSubscription = _audioPlayer.bufferedPositionStream.listen((
      position,
    ) {
      if (!_localPlaybackEnabled) return;
      _bufferedPosition = position;
      notifyListeners();
    });
  }

  Future<void> _restoreSession(String userId, int generation) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_sessionOwnerId != userId || _sessionGeneration != generation) return;
      final savedJson = prefs.getString(
        _userKey('innertube_mobile_session', userId),
      );
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

      final historyJson = prefs.getString(
        _userKey('innerwave_mobile_history', userId),
      );
      if (historyJson != null) {
        final raw = json.decode(historyJson) as List<dynamic>;
        _history = raw
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      final countsJson = prefs.getString(
        _userKey('innerwave_mobile_play_counts', userId),
      );
      if (countsJson != null) {
        final rawCounts = json.decode(countsJson) as Map<String, dynamic>;
        _playCounts = rawCounts.map((k, v) => MapEntry(k, (v as num).toInt()));
      }

      final likedList = prefs.getStringList(
        _userKey('innerwave_mobile_liked_ids', userId),
      );
      if (likedList != null) {
        _likedIds = likedList.toSet();
      }

      final likedSongsJson = prefs.getString(
        _userKey('innerwave_mobile_liked_songs', userId),
      );
      if (likedSongsJson != null) {
        final raw = json.decode(likedSongsJson) as List<dynamic>;
        _likedSongs = raw
            .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      notifyListeners();
      if (_current != null) {
        unawaited(_preloadLyricsAndRelated(_current!));
      }
    } catch (_) {}
  }

  Future<void> _persistSession() async {
    try {
      final ownerId = _sessionOwnerId;
      if (ownerId == null) return;
      final prefs = await SharedPreferences.getInstance();
      if (_sessionOwnerId != ownerId) return;
      if (_current == null) return;
      final data = {
        'current': _current!.toJson(),
        'queue': _queue.map((e) => e.toJson()).toList(),
        'queueIndex': _queueIndex,
        'continuation': _queueContinuation,
      };
      await prefs.setString(
        _userKey('innertube_mobile_session', ownerId),
        json.encode(data),
      );

      // Save to recent history
      _history.removeWhere((item) => item.id == _current!.id);
      _history.insert(0, _current!);
      if (_history.length > 50) _history = _history.sublist(0, 50);
      await prefs.setString(
        _userKey('innerwave_mobile_history', ownerId),
        json.encode(_history.map((e) => e.toJson()).toList()),
      );

      // Increment and save play count
      _playCounts[_current!.id] = (_playCounts[_current!.id] ?? 0) + 1;
      await prefs.setString(
        _userKey('innerwave_mobile_play_counts', ownerId),
        json.encode(_playCounts),
      );
    } catch (_) {}
  }

  Future<void> play(MediaItem item, [List<MediaItem>? contextList]) async {
    if (item.videoId == null) return;
    if (_intercept({
      'action': 'play',
      'item': item.toJson(),
      'context': contextList?.map((entry) => entry.toJson()).toList(),
    })) {
      return;
    }

    final queueRequestId = ++_queueRequestId;
    _error = null;
    _current = item;
    _currentLyrics = null;

    if (contextList != null && contextList.isNotEmpty) {
      final playable = contextList.where((e) => e.videoId != null).toList();
      final idx = playable.indexWhere((e) => e.id == item.id);
      _queue = playable.isNotEmpty ? playable : [item];
      _queueIndex = idx >= 0 ? idx : 0;
      _queueContinuation = null;
      if (_queue.length == 1) {
        unawaited(_fetchRadioQueue(item, queueRequestId));
      }
    } else {
      _queue = [item];
      _queueIndex = 0;
      unawaited(_fetchRadioQueue(item, queueRequestId));
    }

    _seenIds.add(item.id);
    _originalQueue = List.from(_queue);

    notifyListeners();
    unawaited(_preloadLyricsAndRelated(item));
    unawaited(_loadAndPlayStream(item.videoId!));
    unawaited(_persistSession());
  }

  Future<void> _loadAndPlayStream(
    String videoId, {
    bool autoplay = true,
    Duration start = Duration.zero,
  }) async {
    final requestId = ++_streamRequestId;
    _position = Duration.zero;
    _duration = Duration.zero;
    _bufferedPosition = Duration.zero;
    if (autoplay) {
      _isPlaying = true;
      _lastProcessingState = ja.ProcessingState.loading;
      _syncAudioService();
    } else {
      _isPlaying = false;
      _lastProcessingState = ja.ProcessingState.idle;
      _syncAudioService();
    }

    try {
      // Resolve on the listener's device with resilient retry logic.
      // Retrying ensures background network re-connections (screen lock / doze)
      // do not cause the stream fetch to abort.
      StreamManifest? manifest;
      Object? lastManifestError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (requestId != _streamRequestId) return;
        try {
          manifest = await _youtube.videos.streams
              .getManifest(
                videoId,
                ytClients: const [YoutubeApiClient.visionOs],
              )
              .timeout(const Duration(seconds: 15));
          break;
        } catch (e) {
          lastManifestError = e;
          if (attempt < 2) {
            await Future.delayed(const Duration(milliseconds: 600));
          }
        }
      }

      if (manifest == null) {
        throw (lastManifestError ??
            StateError('YouTube returned no manifest.'));
      }
      if (requestId != _streamRequestId) return;

      final audioStreams = manifest.audioOnly.toList();
      if (audioStreams.isEmpty) {
        throw StateError('YouTube returned no audio-only streams.');
      }
      audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      Object? lastStreamError;
      for (final stream in audioStreams) {
        try {
          await _audioPlayer.setUrl(stream.url.toString());
          lastStreamError = null;
          break;
        } catch (error) {
          lastStreamError = error;
          debugPrint(
            '[PlayerProvider] stream itag ${stream.tag} failed for $videoId: $error',
          );
        }
      }
      if (lastStreamError != null) throw lastStreamError;
      if (requestId != _streamRequestId) {
        await _audioPlayer.stop();
        return;
      }
      _loadedVideoId = videoId;
      _error = null;
      if (start > Duration.zero) await _audioPlayer.seek(start);
      if (autoplay) {
        unawaited(_audioPlayer.play());
      } else {
        await _audioPlayer.pause();
      }
      _syncAudioService();
    } catch (error, stackTrace) {
      if (requestId != _streamRequestId) return;
      debugPrint(
        '[PlayerProvider] direct playback failed for $videoId: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _error = 'Unable to resolve this track from YouTube. Try another track or network.';
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> _fetchRadioQueue(MediaItem seed, int requestId) async {
    try {
      final result = await api.getRadioQueue(
        videoId: seed.videoId!,
        title: seed.title,
        artist: seed.artists.join(', '),
      );
      if (requestId != _queueRequestId || _current?.id != seed.id) return;
      final items = result['items'] as List<MediaItem>;
      final continuation = result['continuation'] as String?;

      final fresh = items
          .where((e) => e.id != seed.id && !_seenIds.contains(e.id))
          .toList();
      for (final it in fresh) {
        _seenIds.add(it.id);
      }

      if (fresh.isNotEmpty) {
        _queue = [seed, ...fresh];
        _originalQueue = List.from(_queue);
        _queueIndex = 0;
        _queueContinuation = continuation;
        notifyListeners();
        _checkAutoPrefetchQueue();
      }
    } catch (_) {}
  }

  void _checkAutoPrefetchQueue() {
    if (_queueContinuation != null &&
        !_isLoadingQueue &&
        (_queue.length - _queueIndex) <= 8) {
      unawaited(loadMoreQueue());
    }
  }

  Future<void> loadMoreQueue() async {
    if (_isLoadingQueue ||
        _queueContinuation == null ||
        _current?.videoId == null) {
      return;
    }
    _isLoadingQueue = true;
    notifyListeners();

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
        unawaited(_persistSession());
      } else {
        _queueContinuation = continuation;
      }
    } catch (_) {
      _queueContinuation = null;
    } finally {
      _isLoadingQueue = false;
      notifyListeners();
    }
  }

  void togglePlayPause() {
    if (_current == null) return;
    if (_intercept({'action': 'toggle'})) return;
    final videoId = _current!.videoId;
    if (videoId != null && _loadedVideoId != videoId) {
      _loadAndPlayStream(videoId);
      return;
    }
    if (_isPlaying) {
      unawaited(_audioPlayer.pause());
    } else {
      unawaited(_audioPlayer.play());
    }
  }

  void next() {
    if (_intercept({'action': 'next'})) return;
    if (_queueIndex + 1 < _queue.length) {
      _queueIndex++;
      final nextItem = _queue[_queueIndex];
      _current = nextItem;
      _currentLyrics = null;
      _seenIds.add(nextItem.id);
      notifyListeners();
      unawaited(_preloadLyricsAndRelated(nextItem));
      if (nextItem.videoId != null) {
        _loadAndPlayStream(nextItem.videoId!);
      }
      _persistSession();
      _checkAutoPrefetchQueue();
    } else if (_queueContinuation != null && !_isLoadingQueue) {
      unawaited(() async {
        await loadMoreQueue();
        if (_queueIndex + 1 < _queue.length) {
          next();
        } else {
          unawaited(_audioPlayer.stop());
          _isPlaying = false;
          notifyListeners();
        }
      }());
    } else {
      unawaited(_audioPlayer.stop());
      _isPlaying = false;
      notifyListeners();
    }
  }

  void previous() {
    if (_intercept({'action': 'previous'})) return;
    if (_position.inSeconds > 4) {
      unawaited(_audioPlayer.seek(Duration.zero));
      return;
    }

    if (_queueIndex > 0) {
      _queueIndex--;
      final prevItem = _queue[_queueIndex];
      _current = prevItem;
      _currentLyrics = null;
      _seenIds.add(prevItem.id);
      notifyListeners();
      unawaited(_preloadLyricsAndRelated(prevItem));
      if (prevItem.videoId != null) {
        _loadAndPlayStream(prevItem.videoId!);
      }
      _persistSession();
    } else {
      unawaited(_audioPlayer.seek(Duration.zero));
    }
  }

  void seek(Duration position) {
    if (_intercept({
      'action': 'seek',
      'time': position.inMilliseconds / 1000,
    })) {
      return;
    }
    _position = position;
    unawaited(_audioPlayer.seek(position));
    _syncAudioService();
  }

  void _onTrackEnded() {
    if (_repeatMode == PlayRepeatMode.one) {
      unawaited(_audioPlayer.seek(Duration.zero));
      unawaited(_audioPlayer.play());
    } else {
      next();
    }
  }

  void toggleRepeat() {
    if (_intercept({'action': 'repeat'})) return;
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
    if (_intercept({'action': 'shuffle'})) return;
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

  void moveQueueItem(int from, int to) {
    if (_intercept({'action': 'moveQueueItem', 'from': from, 'to': to})) return;
    if (from < 0 ||
        from >= _queue.length ||
        to < 0 ||
        to >= _queue.length ||
        from == to) {
      return;
    }
    if (from == _queueIndex) return;

    final item = _queue.removeAt(from);
    _queue.insert(to, item);
    if (_queueIndex > from && _queueIndex <= to) {
      _queueIndex--;
    } else if (_queueIndex < from && _queueIndex >= to) {
      _queueIndex++;
    }
    _originalQueue = List.from(_queue);
    notifyListeners();
    unawaited(_persistSession());
  }

  void reorderQueue(int oldIndex, int newIndex) {
    moveQueueItem(oldIndex, newIndex);
  }

  void removeFromQueue(int index) {
    if (_intercept({'action': 'removeFromQueue', 'index': index})) return;
    if (index < 0 || index >= _queue.length) return;
    if (index == _queueIndex) return;
    _queue.removeAt(index);
    if (_queueIndex > index) {
      _queueIndex--;
    }
    _originalQueue = List.from(_queue);
    notifyListeners();
    unawaited(_persistSession());
    _checkAutoPrefetchQueue();
  }

  void clearUpcomingQueue() {
    if (_intercept({'action': 'clearUpcomingQueue'})) return;
    if (_current == null || _queue.isEmpty) return;
    _queue = [_current!];
    _originalQueue = List.from(_queue);
    _queueIndex = 0;
    _queueContinuation = null;
    notifyListeners();
    unawaited(_persistSession());
  }

  bool _intercept(Map<String, dynamic> command) {
    if (_applyingRemoteCommand) return false;
    return _commandInterceptor?.call(command) ?? false;
  }

  void setCommandInterceptor(
    bool Function(Map<String, dynamic> command)? interceptor,
  ) {
    _commandInterceptor = interceptor;
  }

  Future<void> setVolume(double nextVolume) async {
    if (_intercept({'action': 'volume', 'volume': nextVolume})) return;
    _volume = nextVolume.clamp(0, 1).toDouble();
    if (_localPlaybackEnabled) await _audioPlayer.setVolume(_volume);
    notifyListeners();
  }

  void setLocalPlaybackEnabled(bool enabled) {
    _localPlaybackEnabled = enabled;
    if (!enabled) unawaited(_audioPlayer.pause());
  }

  Map<String, dynamic> createSyncSnapshot() => {
    'current': _current?.toJson(),
    'queue': _queue.map((item) => item.toJson()).toList(),
    'queueIndex': _queueIndex,
    'currentTime': _position.inMilliseconds / 1000,
    'duration': _duration.inMilliseconds / 1000,
    'volume': _volume,
    'isPlaying': _isPlaying,
    'queueContinuation': _queueContinuation,
    'capturedAt': DateTime.now().millisecondsSinceEpoch,
  };

  Future<void> applyRemoteCommand(Map<String, dynamic> command) async {
    _applyingRemoteCommand = true;
    try {
      final action = command['action'];
      if (action == 'play') {
        final item = MediaItem.fromJson(
          Map<String, dynamic>.from(command['item'] as Map),
        );
        final context = (command['context'] as List<dynamic>?)
            ?.map(
              (entry) =>
                  MediaItem.fromJson(Map<String, dynamic>.from(entry as Map)),
            )
            .toList();
        await play(item, context);
      } else if (action == 'toggle') {
        togglePlayPause();
      } else if (action == 'next') {
        next();
      } else if (action == 'previous') {
        previous();
      } else if (action == 'seek') {
        final seconds = ((command['time'] as num?) ?? 0).toDouble();
        seek(Duration(milliseconds: (seconds * 1000).round()));
      } else if (action == 'volume') {
        await setVolume(((command['volume'] as num?) ?? 0.8).toDouble());
      } else if (action == 'repeat') {
        toggleRepeat();
      } else if (action == 'shuffle') {
        toggleShuffle();
      } else if (action == 'moveQueueItem') {
        moveQueueItem(
          (command['from'] as num).toInt(),
          (command['to'] as num).toInt(),
        );
      } else if (action == 'removeFromQueue') {
        removeFromQueue((command['index'] as num).toInt());
      } else if (action == 'clearUpcomingQueue') {
        clearUpcomingQueue();
      }
    } finally {
      _applyingRemoteCommand = false;
    }
  }

  Future<void> applyRemoteSnapshot(
    Map<String, dynamic> snapshot, {
    required bool playLocally,
  }) async {
    _localPlaybackEnabled = playLocally;
    final previousTrackId = _current?.id;
    final currentJson = snapshot['current'];
    _current = currentJson is Map
        ? MediaItem.fromJson(Map<String, dynamic>.from(currentJson))
        : null;
    if (_current?.id != previousTrackId) {
      _currentLyrics = null;
      ++_lyricsRequestId;
    }
    _queue = (snapshot['queue'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((entry) => MediaItem.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    final maximumIndex = _queue.isEmpty ? 0 : _queue.length - 1;
    _queueIndex = ((snapshot['queueIndex'] as num?) ?? 0).toInt().clamp(
      0,
      maximumIndex,
    );
    final capturedAt =
        ((snapshot['capturedAt'] as num?) ??
                DateTime.now().millisecondsSinceEpoch)
            .toInt();
    final playing = snapshot['isPlaying'] == true;
    final elapsedMs = playing
        ? (DateTime.now().millisecondsSinceEpoch - capturedAt).clamp(0, 10000)
        : 0;
    _position = Duration(
      milliseconds:
          ((((snapshot['currentTime'] as num?) ?? 0).toDouble() * 1000)
              .round() +
          elapsedMs),
    );
    _duration = Duration(
      milliseconds: (((snapshot['duration'] as num?) ?? 0).toDouble() * 1000)
          .round(),
    );
    _volume = ((snapshot['volume'] as num?) ?? 0.8).toDouble().clamp(0, 1);
    _isPlaying = playing;
    _queueContinuation = snapshot['queueContinuation'] as String?;
    _seenIds.addAll(_queue.map((item) => item.id));
    notifyListeners();
    if (!playLocally) {
      await _audioPlayer.pause();
      return;
    }
    await _audioPlayer.setVolume(_volume);
    final videoId = _current?.videoId;
    if (_current != null && _currentLyrics == null) {
      unawaited(_preloadLyricsAndRelated(_current!));
    }
    if (videoId != null) {
      await _loadAndPlayStream(videoId, autoplay: playing, start: _position);
    }
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _bufferedSubscription?.cancel();
    unawaited(_audioPlayer.dispose());
    _youtube.close();
    super.dispose();
  }
}
