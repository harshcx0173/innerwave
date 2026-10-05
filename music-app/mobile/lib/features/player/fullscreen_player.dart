import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';
import '../collection/collection_screen.dart';

class FullscreenPlayerScreen extends StatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  State<FullscreenPlayerScreen> createState() => _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends State<FullscreenPlayerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  LyricsResponse? _lyrics;
  bool _loadingLyrics = false;
  int _lyricsRequestId = 0;
  String? _loadedLyricsTrackId;
  double _lyricsOffset = 0.0;
  final ScrollController _lyricsScrollController = ScrollController();
  int _lastActiveLyricIndex = -1;
  List<GlobalKey> _lyricKeys = [];
  bool _userIsScrolling = false;
  Timer? _userScrollTimer;

  // Real Image Adaptive Palette
  Color _dominantColor = const Color(0xFF1E2638);
  Color _secondaryColor = const Color(0xFF0F1522);
  Color _accentColor = AppTheme.accent;
  String? _extractedImageUrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final player = context.read<PlayerProvider>();
      if (player.current != null) {
        _loadLyrics(player.current!, player);
        _extractColors(player.current!.highResThumbnail);
      }
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final player = context.read<PlayerProvider>();
    final current = player.current;
    if (current == null) return;

    if (_tabController.index == 2) {
      _lastActiveLyricIndex = -1;
      _userIsScrolling = false;
      _userScrollTimer?.cancel();
      if (_lyrics == null || _loadedLyricsTrackId != current.id) {
        _loadLyrics(current, player);
      } else if (_lyrics != null && _lyrics!.lines.isNotEmpty) {
        final playbackSeconds = player.position.inMilliseconds / 1000.0 + _lyricsOffset;
        int active = -1;
        for (int i = 0; i < _lyrics!.lines.length; i++) {
          if (playbackSeconds >= _lyrics!.lines[i].time &&
              (i == _lyrics!.lines.length - 1 || playbackSeconds < _lyrics!.lines[i + 1].time)) {
            active = i;
            break;
          }
        }
        if (active >= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveLyric(active, force: true);
          });
        }
      }
    }
  }

  Future<void> _extractColors(String imageUrl) async {
    if (imageUrl.isEmpty || imageUrl == _extractedImageUrl) return;
    _extractedImageUrl = imageUrl;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(imageUrl),
        maximumColorCount: 16,
      );
      if (mounted) {
        setState(() {
          final dominant = palette.dominantColor?.color ?? palette.vibrantColor?.color ?? const Color(0xFF1E2638);
          final secondary = palette.darkVibrantColor?.color ?? palette.mutedColor?.color ?? dominant;

          _dominantColor = _tintColor(dominant, 0.22);
          _secondaryColor = _tintColor(secondary, 0.12);
          _accentColor = AppTheme.accent;
        });
      }
    } catch (_) {}
  }

  Color _tintColor(Color color, double lightness) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness(lightness).withSaturation((hsl.saturation * 1.1).clamp(0.25, 0.85)).toColor();
  }

  Future<void> _loadLyrics(MediaItem item, PlayerProvider player) async {
    if (player.currentLyrics != null && item.id == player.current?.id) {
      if (mounted) {
        setState(() {
          _lyrics = player.currentLyrics;
          _loadedLyricsTrackId = item.id;
          _lyricKeys = List.generate(_lyrics!.lines.length, (_) => GlobalKey());
          _loadingLyrics = false;
        });
      }
      return;
    }
    if (item.id == _loadedLyricsTrackId && (_loadingLyrics || _lyrics != null)) return;
    final requestId = ++_lyricsRequestId;
    setState(() => _loadingLyrics = true);
    _loadedLyricsTrackId = item.id;

    try {
      final res = await player.api.getLyrics(
        videoId: item.videoId ?? item.id,
        title: item.title,
        artist: item.artists.isNotEmpty ? item.artists.first : (item.subtitle.isNotEmpty ? item.subtitle : null),
        duration: player.duration.inSeconds > 0 ? player.duration.inSeconds : null,
      );
      if (mounted && requestId == _lyricsRequestId && item.id == _loadedLyricsTrackId && player.current?.id == item.id) {
        setState(() {
          _lyrics = res;
          _lyricKeys = List.generate(res.lines.length, (_) => GlobalKey());
        });
      }
    } catch (_) {
      if (mounted && requestId == _lyricsRequestId && item.id == _loadedLyricsTrackId && player.current?.id == item.id) {
        setState(() {
          _lyrics = LyricsResponse(lyrics: 'No lyrics available for this track.');
          _lyricKeys = [];
        });
      }
    } finally {
      if (mounted && requestId == _lyricsRequestId) setState(() => _loadingLyrics = false);
    }
  }

  void _scrollToActiveLyric(int activeIndex, {bool force = false}) {
    if (_tabController.index != 2) return;
    if (!force && activeIndex == _lastActiveLyricIndex) return;
    if (_userIsScrolling && !force) return;

    _lastActiveLyricIndex = activeIndex;

    if (activeIndex >= 0 && activeIndex < _lyricKeys.length) {
      final key = _lyricKeys[activeIndex];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentContext = key.currentContext;
        if (currentContext != null && currentContext.mounted) {
          Scrollable.ensureVisible(
            currentContext,
            alignment: 0.45,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _tabController.dispose();
    _lyricsScrollController.dispose();
    _userScrollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, player, child) {
        final current = player.current;
        if (current == null) {
          return const Scaffold(body: Center(child: Text('No song selected')));
        }

        // Preload lyrics & extract adaptive palette when track changes
        if (current.id != _loadedLyricsTrackId) {
          ++_lyricsRequestId;
          _lastActiveLyricIndex = -1;
          _lyrics = null;
          _loadingLyrics = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadLyrics(current, player);
              _extractColors(current.highResThumbnail);
            }
          });
        }

        final thumbUrl = current.highResThumbnail;

        return Scaffold(
          body: Stack(
            children: [
              // 1. Dynamic Adaptive Mesh Gradient Base
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _dominantColor,
                        _secondaryColor,
                        const Color(0xFF07090C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),

              // 2. Ambient Colored Orbs for Depth & Apple Music Glow
              Positioned(
                top: -60,
                left: -60,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _dominantColor.withValues(alpha: 0.60),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                right: -60,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accentColor.withValues(alpha: 0.40),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Ambient Blurred Thumbnail Backdrop
              if (thumbUrl.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.48,
                    child: CachedNetworkImage(
                      imageUrl: thumbUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => const SizedBox.shrink(),
                    ),
                  ),
                ),

              // 4. Frosted Glass Blur & Adaptive Contrast Overlay
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.55),
                          const Color(0xFF07090C).withValues(alpha: 0.88),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
              ),

              // 4. Foreground UI
              SafeArea(
                child: Column(
                  children: [
                    // Pull-Down Drag Pill Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 2),
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Top App Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 32),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Column(
                            children: [
                             const Text(
                              'PLAYING FROM',
                              style: TextStyle(
                                color: Color(0x99FFFFFF),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                              Text(
                                current.playlistId != null ? 'Selected Playlist' : 'Song Radio',
                                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70, size: 24),
                            onPressed: () => _showTrackOptionsModal(context, player, current),
                          ),
                        ],
                      ),
                    ),

                    // Tab View (Click-Only Tab Switching, No Horizontal Swipe)
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          // Tab 0: Now Playing (Swipe Down Closes Player)
                          _buildNowPlayingTab(context, player, current),

                          // Tab 1: Up Next Queue
                          _buildQueueTab(context, player),

                          // Tab 2: Apple Music Style Auto-Scrolling Lyrics
                          _buildLyricsTab(context, player),
                        ],
                      ),
                    ),

                    // Bottom Tab Bar (Divider Removed)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0x14FFFFFF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.35),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.black,
                        unselectedLabelColor: AppTheme.textSecondary,
                        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        tabs: const [
                          Tab(text: 'TRACK'),
                          Tab(text: 'UP NEXT'),
                          Tab(text: 'LYRICS'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Now Playing Tab with Swipe-Down-To-Close Support
  Widget _buildNowPlayingTab(BuildContext context, PlayerProvider player, MediaItem current) {
    final size = MediaQuery.of(context).size;
    final artSize = size.width * 0.78;
    final isLiked = player.isLiked(current.id);

    return GestureDetector(
      onVerticalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 250) {
          Navigator.of(context).pop();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // Big Artwork Card with Adaptive Glow
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _dominantColor.withValues(alpha: 0.55),
                      blurRadius: 36,
                      spreadRadius: 2,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: MediaArt(
                  item: current,
                  width: artSize,
                  height: artSize,
                  borderRadius: 24,
                ),
              ),
              const SizedBox(height: 28),

              // Track details & Favorite Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          current.subtitle.isNotEmpty ? current.subtitle : current.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isLiked ? Colors.redAccent : Colors.white70,
                          size: 26,
                        ),
                        onPressed: () => player.toggleLike(current),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white60, size: 22),
                        onPressed: () => _showTrackOptionsModal(context, player, current),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Seekbar
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _accentColor,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: _accentColor,
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: player.position.inMilliseconds.toDouble().clamp(0.0, player.duration.inMilliseconds > 0 ? player.duration.inMilliseconds.toDouble() : 1.0),
                  min: 0.0,
                  max: player.duration.inMilliseconds > 0 ? player.duration.inMilliseconds.toDouble() : 1.0,
                  onChanged: (val) {
                    player.seek(Duration(milliseconds: val.toInt()));
                  },
                ),
              ),

              // Durations
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatDuration(player.position), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                    Text(_formatDuration(player.duration), style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Transport controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: player.shuffle ? _accentColor : Colors.white60,
                      size: 24,
                    ),
                    onPressed: player.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 36),
                    onPressed: player.previous,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.accent.withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 34,
                      ),
                      onPressed: player.togglePlayPause,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 36),
                    onPressed: player.next,
                  ),
                  IconButton(
                    icon: Icon(
                      player.repeatMode == PlayRepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: player.repeatMode != PlayRepeatMode.off ? _accentColor : Colors.white60,
                      size: 24,
                    ),
                    onPressed: player.toggleRepeat,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClearUpcomingQueue(BuildContext context, PlayerProvider player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2638),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Clear upcoming queue?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'This will remove all upcoming tracks and keep only the currently playing song.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              player.clearUpcomingQueue();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Up Next Queue Tab
  Widget _buildQueueTab(BuildContext context, PlayerProvider player) {
    final queue = player.queue;
    if (queue.isEmpty) {
      return const Center(
        child: Text('No tracks in queue', style: TextStyle(color: AppTheme.textMuted)),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PLAYING NEXT (${queue.length})',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (queue.length > 1)
                GestureDetector(
                  onTap: () => _confirmClearUpcomingQueue(context, player),
                  child: const Text(
                    'CLEAR UPCOMING',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                )
              else
                const Icon(Icons.drag_indicator, color: Colors.white30, size: 18),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (scrollInfo) {
              if (scrollInfo.metrics.pixels >=
                  scrollInfo.metrics.maxScrollExtent - 240) {
                if (!player.isLoadingQueue && player.hasMoreQueue) {
                  player.loadMoreQueue();
                }
              }
              return false;
            },
            child: ReorderableListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: queue.length,
              onReorder: (oldIndex, newIndex) {
                if (newIndex > oldIndex) newIndex--;
                player.reorderQueue(oldIndex, newIndex);
              },
              footer: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (player.isLoadingQueue)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Loading more tracks...',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (player.hasMoreQueue)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () => player.loadMoreQueue(),
                          icon: Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: _accentColor,
                          ),
                          label: Text(
                            'Load more songs',
                            style: TextStyle(
                              color: _accentColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
              itemBuilder: (context, index) {
                final item = queue[index];
                final isCurrent = index == player.queueIndex;

                return Padding(
                  key: ValueKey('${item.id}-$index'),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  child: Material(
                    color: isCurrent ? const Color(0x1FFFFFFF) : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isCurrent ? const BorderSide(color: AppTheme.accent) : BorderSide.none,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      leading: MediaArt(item: item, width: 42, height: 42, borderRadius: 8),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppTheme.accent : Colors.white,
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        item.subtitle.isNotEmpty ? item.subtitle : item.artists.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!isCurrent)
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white38,
                                size: 18,
                              ),
                              tooltip: 'Remove from queue',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: () => player.removeFromQueue(index),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.volume_up_rounded,
                                color: _accentColor,
                                size: 18,
                              ),
                            ),
                          const Icon(
                            Icons.drag_handle_rounded,
                            color: Colors.white38,
                            size: 20,
                          ),
                        ],
                      ),
                      onTap: () => player.play(item, player.queue),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Apple Music Style Auto-Scrolling Karaoke Lyrics Tab
  Widget _buildLyricsTab(BuildContext context, PlayerProvider player) {
    if (_loadingLyrics) {
      return Center(child: CircularProgressIndicator(color: _accentColor));
    }

    if (_lyrics == null || (_lyrics!.lines.isEmpty && _lyrics!.lyrics.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_none_rounded, color: AppTheme.textMuted, size: 40),
            const SizedBox(height: 12),
            const Text('No lyrics found for this track', style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _loadLyrics(player.current!, player),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceElevated),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final lyrics = _lyrics!;
    final playbackSeconds = player.position.inMilliseconds / 1000.0 + _lyricsOffset;

    if (!lyrics.synced) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          lyrics.lyrics,
          style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.8),
        ),
      );
    }

    int activeIndex = -1;
    for (int i = 0; i < lyrics.lines.length; i++) {
      if (playbackSeconds >= lyrics.lines[i].time &&
          (i == lyrics.lines.length - 1 || playbackSeconds < lyrics.lines[i + 1].time)) {
        activeIndex = i;
        break;
      }
    }
    if (activeIndex >= 0) {
      _scrollToActiveLyric(activeIndex);
    }

    // Synced interactive lyrics view
    return Column(
      children: [
        // Offset adjustments (-0.5s, Reset, +0.5s)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SYNCED · ${lyrics.syncSource ?? "LRCLIB"} · TAP TO JUMP',
                style: TextStyle(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              Row(
                children: [
                  _timingButton('-0.5s', () => setState(() => _lyricsOffset -= 0.5)),
                  const SizedBox(width: 4),
                  _timingButton('${_lyricsOffset > 0 ? "+" : ""}${_lyricsOffset.toStringAsFixed(1)}s', () => setState(() => _lyricsOffset = 0.0)),
                  const SizedBox(width: 4),
                  _timingButton('+0.5s', () => setState(() => _lyricsOffset += 0.5)),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is UserScrollNotification && notification.direction != ScrollDirection.idle) {
                _userIsScrolling = true;
                _userScrollTimer?.cancel();
                _userScrollTimer = Timer(const Duration(seconds: 4), () {
                  if (mounted) {
                    setState(() => _userIsScrolling = false);
                  }
                });
              }
              return false;
            },
            child: ListView.builder(
              controller: _lyricsScrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: 20,
                vertical: MediaQuery.of(context).size.height * 0.35,
              ),
              itemCount: lyrics.lines.length,
              itemBuilder: (context, index) {
                final line = lyrics.lines[index];
                final isActive = index == activeIndex;
                final isPast = activeIndex >= 0 && index < activeIndex;
                final key = index < _lyricKeys.length ? _lyricKeys[index] : null;

                return Container(
                  key: key,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        _userIsScrolling = false;
                        _userScrollTimer?.cancel();
                        final targetSeconds = (line.time - _lyricsOffset).clamp(0.0, 86400.0);
                        player.seek(Duration(milliseconds: (targetSeconds * 1000).toInt()));
                        _scrollToActiveLyric(index, force: true);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: isActive ? 14 : 10),
                        decoration: BoxDecoration(
                          color: isActive ? _accentColor.withValues(alpha: 0.16) : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                          border: isActive ? Border.all(color: _accentColor.withValues(alpha: 0.45), width: 1.2) : null,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (isActive)
                              Container(
                                margin: const EdgeInsets.only(right: 12),
                                width: 4,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: _accentColor,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _accentColor.withValues(alpha: 0.6),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  color: isActive
                                      ? Colors.white
                                      : (isPast ? Colors.white.withValues(alpha: 0.60) : Colors.white.withValues(alpha: 0.25)),
                                  fontSize: isActive ? 22 : 17,
                                  fontWeight: isActive ? FontWeight.w800 : (isPast ? FontWeight.w600 : FontWeight.w500),
                                  height: 1.4,
                                  letterSpacing: isActive ? -0.2 : 0,
                                ),
                                child: Text(line.text),
                              ),
                            ),
                            if (isActive)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(Icons.music_note_rounded, color: _accentColor, size: 18),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _timingButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// Apple Music / Spotify Style Track Actions Bottom Sheet
  void _showTrackOptionsModal(BuildContext context, PlayerProvider player, MediaItem current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF13171B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final isLiked = player.isLiked(current.id);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Preview
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Row(
                    children: [
                      MediaArt(item: current, width: 48, height: 48, borderRadius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              current.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              current.subtitle.isNotEmpty ? current.subtitle : current.artists.join(', '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        // child: const Text(
                        //   'OPUS 160K',
                        //   style: TextStyle(color: AppTheme.accent, fontSize: 9, fontWeight: FontWeight.bold),
                        // ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10, height: 18),

                // 1. Like / Favorite
                ListTile(
                  leading: Icon(
                    isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isLiked ? Colors.redAccent : Colors.white70,
                  ),
                  title: Text(isLiked ? 'Remove from Liked Songs' : 'Save to Liked Songs', style: const TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    player.toggleLike(current);
                    Navigator.of(ctx).pop();
                  },
                ),

                // 2. Sleep Timer
                ListTile(
                  leading: Icon(
                    Icons.timer_outlined,
                    color: player.hasSleepTimer ? AppTheme.accent : Colors.white70,
                  ),
                  title: Row(
                    children: [
                      const Text('Sleep Timer', style: TextStyle(color: Colors.white, fontSize: 13)),
                      if (player.hasSleepTimer)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '(${player.sleepTimerRemaining?.inMinutes ?? 0}m left)',
                            style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showSleepTimerDialog(context, player);
                  },
                ),

                // 3. More Like This / Song Radio
                ListTile(
                  leading: const Icon(Icons.radio_rounded, color: Colors.white70),
                  title: const Text('Start Radio / More Like This', style: TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (current.videoId != null) {
                      player.play(current, [current]);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Starting Song Radio for “${current.title}”'),
                          backgroundColor: AppTheme.surfaceElevated,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),

                // 4. View Collection / Album
                if (current.browseId != null)
                  ListTile(
                    leading: const Icon(Icons.album_outlined, color: Colors.white70),
                    title: const Text('View Album / Collection', style: TextStyle(color: Colors.white, fontSize: 13)),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CollectionScreen(item: current)),
                      );
                    },
                  ),

                // 5. Share
                ListTile(
                  leading: const Icon(Icons.share_outlined, color: Colors.white70),
                  title: const Text('Share Track', style: TextStyle(color: Colors.white, fontSize: 13)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final shareText = 'Listen to "${current.title}" on InnerWave: https://music.youtube.com/watch?v=${current.videoId}';
                    Clipboard.setData(ClipboardData(text: shareText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Track link copied to clipboard!'),
                        backgroundColor: AppTheme.surfaceElevated,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Sleep Timer Picker Dialog
  void _showSleepTimerDialog(BuildContext context, PlayerProvider player) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13171B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.timer_outlined, color: AppTheme.accent),
            SizedBox(width: 8),
            Text('Sleep Timer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sleepOption(ctx, player, '15 Minutes', const Duration(minutes: 15)),
            _sleepOption(ctx, player, '30 Minutes', const Duration(minutes: 30)),
            _sleepOption(ctx, player, '45 Minutes', const Duration(minutes: 45)),
            _sleepOption(ctx, player, '1 Hour', const Duration(hours: 1)),
            _sleepOption(ctx, player, 'End of this Track', player.duration - player.position),
            if (player.hasSleepTimer)
              ListTile(
                title: const Text('Turn Off Timer', style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _sleepOption(BuildContext ctx, PlayerProvider player, String label, Duration duration) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
      onTap: () {
        player.setSleepTimer(duration);
        Navigator.of(ctx).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sleep timer set for $label'),
            backgroundColor: AppTheme.surfaceElevated,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
