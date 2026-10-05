import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/audio/player_provider.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/models/media_model.dart';
import '../../core/playlist/playlist_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/media_art.dart';
import '../playlist/playlist_detail_screen.dart';
import '../playlist/add_to_playlist_sheet.dart';
import '../player/widgets/song_share_sheet.dart';
import '../explore/artist_profile_screen.dart';
import '../profile/profile_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  List<MediaItem> _history = [];
  String _selectedFilter = 'All'; // 'All', 'Liked Songs', 'Recently Played'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('innerwave_mobile_history');
    List<MediaItem> items = [];
    if (historyJson != null) {
      try {
        final List<dynamic> decoded = json.decode(historyJson);
        items = decoded.map((e) => MediaItem.fromJson(e)).toList();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _history = items;
      });
    }
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('innerwave_mobile_history');
    setState(() => _history = []);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final playlistProv = context.watch<PlaylistProvider>();
    final playlists = playlistProv.playlists;
    final userName = context.watch<AuthController>().displayName;
    final likedSongs = player.likedSongs;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Your Library',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: () {
              _loadData();
            },
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // 1. Profile Header Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.accent, Color(0xFF00B4D8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      userName
                          .substring(0, userName.length >= 2 ? 2 : 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${likedSongs.length} Liked · ${_history.length} Recent',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppTheme.accent,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 2. Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _filterChip('All'),
                const SizedBox(width: 8),
                _filterChip('Playlists', count: playlists.length),
                const SizedBox(width: 8),
                _filterChip('Liked Songs', count: likedSongs.length),
                const SizedBox(width: 8),
                _filterChip('Recently Played', count: _history.length),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2.5. Custom User Playlists Section (Shown in 'All' or 'Playlists')
          if (_selectedFilter == 'All' || _selectedFilter == 'Playlists') ...[
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CUSTOM PLAYLISTS',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  InkWell(
                    onTap: () => _showCreatePlaylistDialog(context),
                    child: const Row(
                      children: [
                        Icon(Icons.add, size: 16, color: AppTheme.accent),
                        SizedBox(width: 4),
                        Text(
                          'New Playlist',
                          style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (playlists.isEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.playlist_add, color: AppTheme.accent, size: 28),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Create your first playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('Collect your favorite songs in one place', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: AppTheme.accent),
                      onPressed: () => _showCreatePlaylistDialog(context),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 155,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: playlists.length,
                  itemBuilder: (ctx, i) {
                    final pl = playlists[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PlaylistDetailScreen(playlist: pl)),
                        );
                      },
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 100,
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.border),
                                image: pl.coverUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(pl.coverUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: pl.coverUrl == null
                                  ? const Center(
                                      child: Icon(Icons.queue_music, size: 36, color: AppTheme.accent),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pl.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${pl.songCount} ${pl.songCount == 1 ? "track" : "tracks"}',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
          ],

          // 3. Dedicated Liked Songs Feature Card (Shown in 'All' or 'Liked Songs')
          if (_selectedFilter != 'Recently Played' && _selectedFilter != 'Playlists') ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF3B1E6D),
                    Color(0xFF1E1333),
                    Color(0xFF12141A),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.purpleAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.purpleAccent,
                                  Color(0xFFFF2E93),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purpleAccent.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Liked Songs',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${likedSongs.length} favorite ${likedSongs.length == 1 ? "track" : "tracks"}',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (likedSongs.isNotEmpty) ...[
                            IconButton.filled(
                              onPressed: () =>
                                  player.play(likedSongs.first, likedSongs),
                              icon: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 26,
                              ),
                              style: IconButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () {
                                final shuffled = List<MediaItem>.from(
                                  likedSongs,
                                )..shuffle();
                                player.play(shuffled.first, shuffled);
                              },
                              icon: const Icon(
                                Icons.shuffle_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // 4. Liked Songs List (When 'Liked Songs' is active or in 'All' if has items)
          if (_selectedFilter == 'Liked Songs' ||
              (_selectedFilter == 'All' && likedSongs.isNotEmpty)) ...[
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 16,
                bottom: 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'YOUR FAVORITES',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '${likedSongs.length} total',
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (likedSongs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Center(
                  child: Text(
                    'No liked songs yet.\nTap the heart icon on any song to save it here!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              )
            else
              ...likedSongs.map((item) {
                final isCurrent = player.current?.id == item.id;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  child: Material(
                    color: isCurrent
                        ? AppTheme.accent.withValues(alpha: 0.1)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: MediaArt(
                        item: item,
                        width: 46,
                        height: 46,
                        borderRadius: 8,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppTheme.accent : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        item.subtitle.isNotEmpty
                            ? item.subtitle
                            : item.artists.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.favorite_rounded,
                              color: Colors.purpleAccent,
                              size: 20,
                            ),
                            onPressed: () => player.toggleLike(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                            onPressed: () => _showSongOptions(context, item),
                          ),
                        ],
                      ),
                      onTap: () => player.play(item, likedSongs),
                      onLongPress: () => _showSongOptions(context, item),
                    ),
                  ),
                );
              }),
          ],

          // 5. Recently Played Section
          if (_selectedFilter != 'Liked Songs') ...[
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                top: 22,
                bottom: 8,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'RECENTLY PLAYED',
                    style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (_history.isNotEmpty)
                    GestureDetector(
                      onTap: _clearHistory,
                      child: const Text(
                        'Clear',
                        style: TextStyle(color: AppTheme.accent, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),

            if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Center(
                  child: Text(
                    'Your recently played tracks will appear here.',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ),
              )
            else
              ..._history.map((item) {
                final isCurrent = player.current?.id == item.id;
                final isLiked = player.isLiked(item.id);

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 3,
                  ),
                  child: Material(
                    color: isCurrent
                        ? AppTheme.accent.withValues(alpha: 0.08)
                        : Colors.white.withValues(alpha: 0.02),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      leading: MediaArt(
                        item: item,
                        width: 44,
                        height: 44,
                        borderRadius: 8,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppTheme.accent : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        item.subtitle.isNotEmpty
                            ? item.subtitle
                            : item.artists.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              isLiked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: isLiked
                                  ? Colors.purpleAccent
                                  : Colors.white24,
                              size: 18,
                            ),
                            onPressed: () => player.toggleLike(item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, color: Colors.white38, size: 18),
                            onPressed: () => _showSongOptions(context, item),
                          ),
                        ],
                      ),
                      onTap: () => player.play(item, _history),
                      onLongPress: () => _showSongOptions(context, item),
                    ),
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String label, {int? count}) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accent : AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Text(
          count != null ? '$label ($count)' : label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter playlist title...',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AppTheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx);
                await context.read<PlaylistProvider>().createPlaylist(text);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showSongOptions(BuildContext context, MediaItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: SizedBox(
                  width: 44,
                  height: 44,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: MediaArt(item: item),
                  ),
                ),
                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ),
              const Divider(color: AppTheme.border),
              ListTile(
                leading: const Icon(Icons.playlist_add, color: AppTheme.accent),
                title: const Text('Add to Playlist', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  AddToPlaylistSheet.show(context, item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.cyanAccent),
                title: const Text('Share Song Card', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  SongShareSheet.show(context, item);
                },
              ),
              if (item.artists.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.purpleAccent),
                  title: Text('View Artist (${item.artists.first})', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistProfileScreen(artistName: item.artists.first),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
