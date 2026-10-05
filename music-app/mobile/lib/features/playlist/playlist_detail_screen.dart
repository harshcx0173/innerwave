import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/audio/player_provider.dart';
import '../../core/models/media_model.dart';
import '../../core/playlist/playlist_provider.dart';
import '../../core/playlist/user_playlist_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final UserPlaylist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<MediaItem> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() => _loading = true);
    final songs = await context.read<PlaylistProvider>().getPlaylistSongs(widget.playlist.id);
    if (mounted) {
      setState(() {
        _songs = songs;
        _loading = false;
      });
    }
  }

  Future<void> _removeSong(MediaItem song) async {
    await context.read<PlaylistProvider>().removeSongFromPlaylist(widget.playlist.id, song.id);
    setState(() {
      _songs.removeWhere((s) => s.id == song.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed "${song.title}" from playlist'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDeletePlaylist() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Playlist?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "${widget.playlist.name}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<PlaylistProvider>().deletePlaylist(widget.playlist.id);
      if (mounted) Navigator.pop(context);
    }
  }

  void _playAll([bool shuffle = false]) {
    if (_songs.isEmpty) return;
    final ordered = shuffle ? (List<MediaItem>.from(_songs)..shuffle()) : _songs;
    context.read<PlayerProvider>().play(ordered.first, ordered);
  }

  @override
  Widget build(BuildContext context) {
    final leadArt = _songs.isNotEmpty ? _songs.first : null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(
          widget.playlist.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white70),
            onPressed: _confirmDeletePlaylist,
            tooltip: 'Delete Playlist',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: leadArt != null
                              ? MediaArt(item: leadArt)
                              : Container(
                                  color: AppTheme.surfaceElevated,
                                  child: const Center(
                                    child: Icon(Icons.music_note, size: 64, color: AppTheme.textSecondary),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.playlist.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.playlist.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.playlist.description,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '${_songs.length} ${_songs.length == 1 ? "track" : "tracks"}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _songs.isEmpty ? null : () => _playAll(false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 20),
                            label: const Text('Play All', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _songs.isEmpty ? null : () => _playAll(true),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            icon: const Icon(Icons.shuffle, size: 18),
                            label: const Text('Shuffle'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(color: AppTheme.border, height: 1),

                // Track list
                if (_songs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        'No songs added to this playlist yet.\nAdd songs from the search or player menu.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary, height: 1.5),
                      ),
                    ),
                  )
                else
                  ..._songs.asMap().entries.map((entry) {
                    final index = entry.key;
                    final song = entry.value;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: SizedBox(
                        width: 50,
                        height: 50,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: MediaArt(item: song),
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                      subtitle: Text(
                        song.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.white38, size: 20),
                        onPressed: () => _removeSong(song),
                        tooltip: 'Remove',
                      ),
                      onTap: () {
                        context.read<PlayerProvider>().play(song, _songs.sublist(index));
                      },
                    );
                  }),
              ],
            ),
    );
  }
}
