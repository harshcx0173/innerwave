import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';

class CollectionScreen extends StatefulWidget {
  final MediaItem item;

  const CollectionScreen({super.key, required this.item});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  Feed? _feed;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCollection();
  }

  Future<void> _loadCollection() async {
    final player = context.read<PlayerProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await player.api.browse(
        widget.item.browseId ?? widget.item.id,
        widget.item.browseParams,
      );
      if (mounted) setState(() => _feed = res);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load collection details.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final tracks = _feed?.shelves.expand((s) => s.items).where((item) => item.videoId != null).toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadCollection,
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceElevated),
                        child: const Text('Retry', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                )
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.5),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: MediaArt(
                                  item: widget.item,
                                  width: 170,
                                  height: 170,
                                  borderRadius: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              widget.item.type.toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.item.title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.item.subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.play_arrow, color: Colors.black, size: 20),
                                  label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accent,
                                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  onPressed: tracks.isNotEmpty ? () => player.play(tracks.first, tracks) : null,
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.shuffle, color: Colors.white, size: 18),
                                  label: const Text('Shuffle', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white24),
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                  ),
                                  onPressed: tracks.isNotEmpty
                                      ? () {
                                          final shuffled = List<MediaItem>.from(tracks)..shuffle();
                                          player.play(shuffled.first, shuffled);
                                        }
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final track = tracks[index];
                          final isCurrent = player.current?.id == track.id;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            child: Material(
                              color: isCurrent ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                leading: SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: isCurrent ? AppTheme.accent : AppTheme.textMuted,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isCurrent ? AppTheme.accent : Colors.white,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  track.subtitle.isNotEmpty ? track.subtitle : track.artists.join(', '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                                ),
                                trailing: track.duration != null
                                    ? Text(track.duration!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11))
                                    : const Icon(Icons.play_arrow, color: Colors.white30, size: 18),
                                onTap: () => player.play(track, tracks),
                              ),
                            ),
                          );
                        },
                        childCount: tracks.length,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
    );
  }
}
