import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_model.dart';

class _CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  _CacheEntry({required this.data, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class MusicApi {
  static const String productionUrl = 'https://innerwave.onrender.com';

  static String get defaultBaseUrl => productionUrl;

  static const Map<String, String> defaultHeaders = {
    'ngrok-skip-browser-warning': 'true',
    'Accept': 'application/json',
  };

  final String baseUrl;
  final http.Client _client;

  // In-memory caching and request de-duplication
  final Map<String, _CacheEntry<dynamic>> _memoryCache = {};
  final Map<String, Future<dynamic>> _inFlightRequests = {};

  MusicApi({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl,
      _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, dynamic>? queryParameters]) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final parsed = Uri.parse('$cleanBase$cleanPath');
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final filtered = <String, String>{};
      queryParameters.forEach((key, value) {
        if (value != null) filtered[key] = value.toString();
      });
      return parsed.replace(queryParameters: filtered);
    }
    return parsed;
  }

  /// Generic cached request executor with TTL, in-flight deduplication, and offline fallback
  Future<T> _fetchCached<T>({
    required String cacheKey,
    required Duration ttl,
    required Future<T> Function() networkFetch,
    T Function(Map<String, dynamic> json)? fromJson,
    Map<String, dynamic> Function(T data)? toJson,
    bool forceRefresh = false,
  }) async {
    // 1. Check in-memory cache if not forcing refresh
    if (!forceRefresh) {
      final cached = _memoryCache[cacheKey];
      if (cached != null && !cached.isExpired && cached.data is T) {
        return cached.data as T;
      }
    }

    // 2. Deduplicate in-flight network requests
    if (_inFlightRequests.containsKey(cacheKey)) {
      try {
        final result = await _inFlightRequests[cacheKey]!;
        if (result is T) return result;
      } catch (_) {}
    }

    final future = () async {
      try {
        final result = await networkFetch();
        _memoryCache[cacheKey] = _CacheEntry<T>(
          data: result,
          expiresAt: DateTime.now().add(ttl),
        );

        // Asynchronously persist key cache entries
        if (toJson != null) {
          SharedPreferences.getInstance()
              .then((prefs) {
                final payload = json.encode({
                  'data': toJson(result),
                  'expiresAt': DateTime.now().add(ttl).millisecondsSinceEpoch,
                });
                prefs.setString('iw_cache_$cacheKey', payload);
              })
              .catchError((_) {});
        }

        return result;
      } catch (networkError) {
        // Fallback to expired in-memory cache if available
        final stale = _memoryCache[cacheKey];
        if (stale != null && stale.data is T) {
          return stale.data as T;
        }

        // Fallback to persisted disk cache if available
        if (fromJson != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            final savedStr = prefs.getString('iw_cache_$cacheKey');
            if (savedStr != null && savedStr.isNotEmpty) {
              final parsed = json.decode(savedStr) as Map<String, dynamic>;
              final diskData = fromJson(parsed['data'] as Map<String, dynamic>);
              _memoryCache[cacheKey] = _CacheEntry<T>(
                data: diskData,
                expiresAt: DateTime.fromMillisecondsSinceEpoch(
                  parsed['expiresAt'] as int? ?? 0,
                ),
              );
              return diskData;
            }
          } catch (_) {}
        }

        rethrow;
      } finally {
        _inFlightRequests.remove(cacheKey);
      }
    }();

    _inFlightRequests[cacheKey] = future;
    return future;
  }

  /// Initial Home Feed (cached for 10 minutes)
  Future<Feed> getHome({bool forceRefresh = false}) async {
    return _fetchCached<Feed>(
      cacheKey: 'feed_home',
      ttl: const Duration(minutes: 10),
      forceRefresh: forceRefresh,
      fromJson: (json) => Feed.fromJson(json),
      toJson: (feed) => feed.toJson(),
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/home'),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return Feed.fromJson(data);
        }
        throw Exception('Failed to load home feed: ${response.statusCode}');
      },
    );
  }

  /// More Home Discovery Shelves (cached for 15 minutes per page/chip)
  Future<Feed> getMoreHome({
    int page = 1,
    String? continuation,
    String? chip,
    bool forceRefresh = false,
  }) async {
    final chipKey = (chip != null && chip.isNotEmpty)
        ? chip.toLowerCase()
        : 'all';
    final cacheKey =
        'feed_more_${page}_${chipKey}_${continuation?.hashCode ?? 0}';

    return _fetchCached<Feed>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 15),
      forceRefresh: forceRefresh,
      fromJson: (json) => Feed.fromJson(json),
      toJson: (feed) => feed.toJson(),
      networkFetch: () async {
        final query = <String, dynamic>{
          'page': page,
          if (continuation != null && continuation.isNotEmpty)
            'continuation': continuation,
          if (chip != null && chip.isNotEmpty) 'chip': chip,
        };
        final response = await _client.get(
          _uri('/api/home/more', query),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return Feed.fromJson(data);
        }
        throw Exception('Failed to load more shelves: ${response.statusCode}');
      },
    );
  }

  /// Recommendations based on artist history (cached for 20 minutes)
  Future<List<Shelf>> getRecommendations(
    List<String> artists, {
    bool forceRefresh = false,
  }) async {
    if (artists.isEmpty) return [];
    final cleanArtists = artists.take(3).join(',');
    final cacheKey = 'feed_recs_${cleanArtists.toLowerCase().hashCode}';

    return _fetchCached<List<Shelf>>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 20),
      forceRefresh: forceRefresh,
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/recommendations', {'artists': cleanArtists}),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          final rawShelves = data['shelves'] as List<dynamic>? ?? [];
          return rawShelves
              .map((e) => Shelf.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        return [];
      },
    );
  }

  /// Search across tracks, artists, albums, and playlists (cached for 5 minutes)
  Future<Feed> search(String query, {bool forceRefresh = false}) async {
    final cleanQuery = query.trim().toLowerCase();
    final cacheKey = 'search_$cleanQuery';

    return _fetchCached<Feed>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 5),
      forceRefresh: forceRefresh,
      fromJson: (json) => Feed.fromJson(json),
      toJson: (feed) => feed.toJson(),
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/search', {'q': query.trim()}),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return Feed.fromJson(data);
        }
        throw Exception('Search request failed: ${response.statusCode}');
      },
    );
  }

  /// Search Suggestions (cached for 3 minutes)
  Future<List<String>> getSearchSuggestions(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return [];
    final cacheKey = 'sugg_$cleanQuery';

    return _fetchCached<List<String>>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 3),
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/search/suggestions', {'q': query.trim()}),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (data is Map && data['suggestions'] is List) {
            return (data['suggestions'] as List)
                .map((e) => e.toString())
                .toList();
          }
        }
        return [];
      },
    );
  }

  /// Browse Album / Playlist / Artist collections (cached for 30 minutes)
  Future<Feed> browse(
    String browseId, [
    String? params,
    bool forceRefresh = false,
  ]) async {
    final cacheKey = 'browse_${browseId}_${params?.hashCode ?? 0}';

    return _fetchCached<Feed>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 30),
      forceRefresh: forceRefresh,
      fromJson: (json) => Feed.fromJson(json),
      toJson: (feed) => feed.toJson(),
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/browse', {'id': browseId, 'params': ?params}),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return Feed.fromJson(data);
        }
        throw Exception('Browse request failed: ${response.statusCode}');
      },
    );
  }

  /// Up Next / Radio Queue (cached for 10 minutes)
  Future<Map<String, dynamic>> getRadioQueue({
    required String videoId,
    String? title,
    String? artist,
    String? playlistId,
    String? continuation,
    bool forceRefresh = false,
  }) async {
    // Versioned so devices do not reuse the older search-generated queues
    // after the backend switched back to YouTube Music radio-first results.
    final cacheKey =
        'queue_v2_${videoId}_${playlistId ?? ''}_${continuation?.hashCode ?? 0}';

    return _fetchCached<Map<String, dynamic>>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 10),
      forceRefresh: forceRefresh,
      networkFetch: () async {
        final query = <String, dynamic>{
          'videoId': videoId,
          'title': ?title,
          'artist': ?artist,
          'playlistId': ?playlistId,
          'continuation': ?continuation,
        };
        final response = await _client.get(
          _uri('/api/next', query),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          final rawItems = data['items'] as List<dynamic>? ?? [];
          final items = rawItems
              .map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
              .toList();
          return {
            'items': items,
            'continuation': data['continuation'] as String?,
          };
        }
        throw Exception('Radio queue request failed: ${response.statusCode}');
      },
    );
  }

  /// Lyrics (cached for 24 hours)
  Future<LyricsResponse> getLyrics({
    required String videoId,
    required String title,
    String? artist,
    int? duration,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'lyrics_$videoId';

    return _fetchCached<LyricsResponse>(
      cacheKey: cacheKey,
      ttl: const Duration(hours: 24),
      forceRefresh: forceRefresh,
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/lyrics', {
            'videoId': videoId,
            'title': title,
            'artist': ?artist,
            'duration': ?duration,
          }),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return LyricsResponse.fromJson(data);
        }
        throw Exception('Lyrics request failed: ${response.statusCode}');
      },
    );
  }

  /// Related tracks and content (cached for 30 minutes)
  Future<Feed> getRelated(
    String videoId, {
    String? title,
    String? artist,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'related_$videoId';

    return _fetchCached<Feed>(
      cacheKey: cacheKey,
      ttl: const Duration(minutes: 30),
      forceRefresh: forceRefresh,
      fromJson: (json) => Feed.fromJson(json),
      toJson: (feed) => feed.toJson(),
      networkFetch: () async {
        final response = await _client.get(
          _uri('/api/related', {
            'videoId': videoId,
            'title': ?title,
            'artist': ?artist,
          }),
          headers: defaultHeaders,
        );
        if (response.statusCode == 200) {
          final data = json.decode(
            utf8.decode(response.bodyBytes),
          ) as Map<String, dynamic>;
          return Feed.fromJson(data);
        }
        throw Exception('Related request failed: ${response.statusCode}');
      },
    );
  }

  /// Stream Audio URL helper
  String getStreamUrl(String videoId) {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$cleanBase/api/stream/$videoId';
  }

  /// Clear in-memory and persistent cache
  void clearMemoryCache() {
    _memoryCache.clear();
  }
}
