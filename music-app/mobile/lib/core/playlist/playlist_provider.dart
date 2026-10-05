import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/media_model.dart';
import 'user_playlist_model.dart';

class PlaylistProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  List<UserPlaylist> _playlists = [];
  bool _isLoading = false;

  List<UserPlaylist> get playlists => _playlists;
  bool get isLoading => _isLoading;

  String? get _userId => _client.auth.currentUser?.id;

  PlaylistProvider() {
    loadPlaylists();
  }

  Future<void> loadPlaylists() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = _userId;
      if (userId != null) {
        final response = await _client
            .from('user_playlists')
            .select('id, name, description, cover_url, created_at, updated_at, user_playlist_items(count)')
            .eq('user_id', userId)
            .order('updated_at', ascending: false);

        final items = (response as List<dynamic>).map((row) {
          final map = Map<String, dynamic>.from(row as Map);
          final itemsCount = (map['user_playlist_items'] as List<dynamic>?)?.isNotEmpty == true
              ? ((map['user_playlist_items'] as List<dynamic>)[0] as Map)['count'] as num?
              : 0;
          map['song_count'] = itemsCount?.toInt() ?? 0;
          return UserPlaylist.fromJson(map);
        }).toList();

        _playlists = items;
        await _saveLocalPlaylists(items);
        _isLoading = false;
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[PlaylistProvider] Cloud load error: $e');
    }

    // Fallback to local cache
    _playlists = await _loadLocalPlaylists();
    _isLoading = false;
    notifyListeners();
  }

  Future<List<UserPlaylist>> _loadLocalPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('innerwave_user_playlists_${_userId ?? "guest"}');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        return decoded.map((e) => UserPlaylist.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveLocalPlaylists(List<UserPlaylist> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(items.map((e) => e.toJson()).toList());
      await prefs.setString('innerwave_user_playlists_${_userId ?? "guest"}', encoded);
    } catch (_) {}
  }

  Future<UserPlaylist> createPlaylist(String name, [String description = '']) async {
    final trimmed = name.trim().isEmpty ? 'Untitled Playlist' : name.trim();
    final tempId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();

    UserPlaylist created = UserPlaylist(
      id: tempId,
      name: trimmed,
      description: description,
      coverUrl: null,
      songCount: 0,
      createdAt: now,
      updatedAt: now,
    );

    final userId = _userId;
    if (userId != null) {
      try {
        final res = await _client.from('user_playlists').insert({
          'user_id': userId,
          'name': trimmed,
          'description': description,
        }).select().single();

        created = UserPlaylist.fromJson(Map<String, dynamic>.from(res));
      } catch (e) {
        debugPrint('[PlaylistProvider] Cloud create error: $e');
      }
    }

    _playlists.insert(0, created);
    await _saveLocalPlaylists(_playlists);
    notifyListeners();
    return created;
  }

  Future<void> deletePlaylist(String playlistId) async {
    final userId = _userId;
    if (userId != null && !playlistId.startsWith('local_')) {
      try {
        await _client.from('user_playlists').delete().eq('id', playlistId).eq('user_id', userId);
      } catch (e) {
        debugPrint('[PlaylistProvider] Cloud delete error: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('innerwave_playlist_items_$playlistId');
    } catch (_) {}

    _playlists.removeWhere((p) => p.id == playlistId);
    await _saveLocalPlaylists(_playlists);
    notifyListeners();
  }

  Future<List<MediaItem>> getPlaylistSongs(String playlistId) async {
    final userId = _userId;
    if (userId != null && !playlistId.startsWith('local_')) {
      try {
        final res = await _client
            .from('user_playlist_items')
            .select('song')
            .eq('playlist_id', playlistId)
            .order('position', ascending: true);

        final songs = (res as List<dynamic>)
            .map((row) => MediaItem.fromJson(Map<String, dynamic>.from((row as Map)['song'] as Map)))
            .toList();

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'innerwave_playlist_items_$playlistId',
          json.encode(songs.map((e) => e.toJson()).toList()),
        );
        return songs;
      } catch (e) {
        debugPrint('[PlaylistProvider] Cloud get songs error: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('innerwave_playlist_items_$playlistId');
      if (raw != null) {
        final List<dynamic> decoded = json.decode(raw);
        return decoded
            .map((e) => MediaItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {}

    return [];
  }

  Future<bool> addSongToPlaylist(String playlistId, MediaItem song) async {
    final currentSongs = await getPlaylistSongs(playlistId);
    if (currentSongs.any((item) => item.id == song.id)) {
      return false; // already in playlist
    }

    currentSongs.add(song);

    // Save local
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'innerwave_playlist_items_$playlistId',
        json.encode(currentSongs.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}

    final userId = _userId;
    if (userId != null && !playlistId.startsWith('local_')) {
      try {
        await _client.from('user_playlist_items').insert({
          'playlist_id': playlistId,
          'user_id': userId,
          'song': song.toJson(),
          'position': currentSongs.length - 1,
        });

        await _client.from('user_playlists').update({
          'updated_at': DateTime.now().toIso8601String(),
          'cover_url': song.thumbnail,
        }).eq('id', playlistId);
      } catch (e) {
        debugPrint('[PlaylistProvider] Cloud add song error: $e');
      }
    }

    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].copyWith(
        songCount: currentSongs.length,
        coverUrl: _playlists[index].coverUrl ?? song.thumbnail,
        updatedAt: DateTime.now(),
      );
      await _saveLocalPlaylists(_playlists);
      notifyListeners();
    }

    return true;
  }

  Future<void> removeSongFromPlaylist(String playlistId, String songId) async {
    final currentSongs = await getPlaylistSongs(playlistId);
    currentSongs.removeWhere((item) => item.id == songId);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'innerwave_playlist_items_$playlistId',
        json.encode(currentSongs.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}

    final userId = _userId;
    if (userId != null && !playlistId.startsWith('local_')) {
      try {
        await _client
            .from('user_playlist_items')
            .delete()
            .eq('playlist_id', playlistId)
            .contains('song', {'id': songId});
      } catch (e) {
        debugPrint('[PlaylistProvider] Cloud remove song error: $e');
      }
    }

    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] = _playlists[index].copyWith(
        songCount: currentSongs.length,
        coverUrl: currentSongs.isNotEmpty ? currentSongs.first.thumbnail : null,
        updatedAt: DateTime.now(),
      );
      await _saveLocalPlaylists(_playlists);
      notifyListeners();
    }
  }
}
