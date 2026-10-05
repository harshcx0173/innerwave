import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/music_api.dart';
import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';

class ArtistProfileScreen extends StatefulWidget {
  final String artistName;

  const ArtistProfileScreen({super.key, required this.artistName});

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  List<MediaItem> _tracks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArtistSongs();
  }

  Future<void> _loadArtistSongs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = context.read<MusicApi>();
      final feed = await api.search('${widget.artistName} top songs tracks');
      final allItems = feed.shelves.expand((s) => s.items).where((it) => it.videoId != null).toList();
      final unique = <String, MediaItem>{};
      for (final it in allItems) {
        unique.putIfAbsent(it.id, () => it);
      }

      if (mounted) {
        setState(() {
          _tracks = unique.values.toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load artist tracks.';
          _loading = false;
        });
      }
    }
  }

  void _playAll([bool shuffle = false]) {
    if (_tracks.isEmpty) return;
    final ordered = shuffle ? (List<MediaItem>.from(_tracks)..shuffle()) : _tracks;
    context.read<PlayerProvider>().play(ordered.first, ordered);
  }

  @override
  Widget build(BuildContext context) {
    final leadTrack = _tracks.isNotEmpty ? _tracks.first : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppTheme.surfaceElevated,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.artistName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (leadTrack != null)
                    Opacity(
                      opacity: 0.35,
                      child: MediaArt(item: leadTrack),
                    )
                  else
                    Container(color: const Color(0xFF231638)),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0xFF0F1117)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 60,
                    left: 20,
                    child: Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.accent, width: 2),
                          ),
                          child: ClipOval(
                            child: leadTrack != null
                                ? MediaArt(item: leadTrack)
                                : Container(
                                    color: AppTheme.surfaceElevated,
                                    child: Center(
                                      child: Text(
                                        widget.artistName.substring(0, widget.artistName.length >= 2 ? 2 : 1).toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.verified, size: 14, color: AppTheme.accent),
                                SizedBox(width: 4),
                                Text(
                                  'VERIFIED ARTIST',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.artistName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action buttons
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _tracks.isEmpty ? null : () => _playAll(false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play Radio', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _tracks.isEmpty ? null : () => _playAll(true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.shuffle, size: 18),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),

          // Top Tracks List
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final track = _tracks[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: MediaArt(item: track),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      track.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.play_circle_outline, color: Colors.white60),
                    onTap: () {
                      context.read<PlayerProvider>().play(track, _tracks.sublist(i));
                    },
                  );
                },
                childCount: _tracks.length,
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 120),
          ),
        ],
      ),
    );
  }
}
