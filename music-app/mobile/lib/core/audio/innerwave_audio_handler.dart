import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as ja;

class InnerWaveAudioHandler extends BaseAudioHandler with SeekHandler {
  Future<void> Function()? onPlayCallback;
  Future<void> Function()? onPauseCallback;
  Future<void> Function()? onNextCallback;
  Future<void> Function()? onPreviousCallback;
  Future<void> Function(Duration position)? onSeekCallback;
  Future<void> Function()? onStopCallback;

  InnerWaveAudioHandler() {
    playbackState.add(
      PlaybackState(
        controls: const [
          MediaControl.skipToPrevious,
          MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (onPlayCallback != null) {
      await onPlayCallback!();
    }
  }

  @override
  Future<void> pause() async {
    if (onPauseCallback != null) {
      await onPauseCallback!();
    }
  }

  @override
  Future<void> skipToNext() async {
    if (onNextCallback != null) {
      await onNextCallback!();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (onPreviousCallback != null) {
      await onPreviousCallback!();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (onSeekCallback != null) {
      await onSeekCallback!(position);
    }
  }

  @override
  Future<void> stop() async {
    if (onStopCallback != null) {
      await onStopCallback!();
    }
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }

  void updatePlaybackState({
    required bool isPlaying,
    required ja.ProcessingState processingState,
    required Duration position,
    required Duration bufferedPosition,
    required Duration duration,
    required bool hasNext,
    required bool hasPrevious,
  }) {
    final controls = <MediaControl>[
      if (hasPrevious) MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      if (hasNext) MediaControl.skipToNext,
    ];

    final compactIndices = <int>[];
    if (controls.contains(MediaControl.skipToPrevious)) {
      compactIndices.add(controls.indexOf(MediaControl.skipToPrevious));
    }
    final playPauseControl = isPlaying ? MediaControl.pause : MediaControl.play;
    if (controls.contains(playPauseControl)) {
      compactIndices.add(controls.indexOf(playPauseControl));
    }
    if (controls.contains(MediaControl.skipToNext)) {
      compactIndices.add(controls.indexOf(MediaControl.skipToNext));
    }

    final mappedProcessingState = switch (processingState) {
      ja.ProcessingState.idle => AudioProcessingState.idle,
      ja.ProcessingState.loading => AudioProcessingState.loading,
      ja.ProcessingState.buffering => AudioProcessingState.buffering,
      ja.ProcessingState.ready => AudioProcessingState.ready,
      ja.ProcessingState.completed => AudioProcessingState.completed,
    };

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: compactIndices,
        processingState: mappedProcessingState,
        playing: isPlaying,
        updatePosition: position,
        bufferedPosition: bufferedPosition,
        speed: 1.0,
      ),
    );
  }

  void setMediaItem({
    required String id,
    required String title,
    required String artist,
    String? album,
    String? artworkUrl,
    Duration? duration,
  }) {
    mediaItem.add(
      MediaItem(
        id: id,
        title: title,
        artist: artist,
        album: album ?? 'InnerWave',
        duration: duration,
        artUri: artworkUrl != null && artworkUrl.isNotEmpty
            ? Uri.tryParse(artworkUrl)
            : null,
      ),
    );
  }

  void clearMediaItem() {
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        controls: const [],
        systemActions: const {},
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
  }
}
