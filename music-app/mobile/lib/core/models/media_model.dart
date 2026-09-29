class MediaItem {
  final String id;
  final String? videoId;
  final String? browseId;
  final String? browseParams;
  final String? playlistId;
  final String title;
  final String subtitle;
  final List<String> artists;
  final String? thumbnail;
  final String type;
  final String? duration;
  final String? watchParams;
  final int? index;

  MediaItem({
    required this.id,
    this.videoId,
    this.browseId,
    this.browseParams,
    this.playlistId,
    required this.title,
    required this.subtitle,
    required this.artists,
    this.thumbnail,
    required this.type,
    this.duration,
    this.watchParams,
    this.index,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: json['id'] as String? ?? '',
      videoId: json['videoId'] as String?,
      browseId: json['browseId'] as String?,
      browseParams: json['browseParams'] as String?,
      playlistId: json['playlistId'] as String?,
      title: json['title'] as String? ?? 'Untitled',
      subtitle: json['subtitle'] as String? ?? '',
      artists: (json['artists'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      thumbnail: json['thumbnail'] as String?,
      type: json['type'] as String? ?? 'song',
      duration: json['duration'] as String?,
      watchParams: json['watchParams'] as String?,
      index: json['index'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'videoId': videoId,
      'browseId': browseId,
      'browseParams': browseParams,
      'playlistId': playlistId,
      'title': title,
      'subtitle': subtitle,
      'artists': artists,
      'thumbnail': thumbnail,
      'type': type,
      'duration': duration,
      'watchParams': watchParams,
      'index': index,
    };
  }

  String get highResThumbnail {
    if (thumbnail != null && thumbnail!.isNotEmpty) {
      return thumbnail!;
    }
    if (videoId != null && videoId!.isNotEmpty) {
      return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }
    return '';
  }
}

class Shelf {
  final String id;
  final String title;
  final String layout; // 'list', 'songs', 'carousel'
  final List<MediaItem> items;

  Shelf({
    required this.id,
    required this.title,
    required this.layout,
    required this.items,
  });

  factory Shelf.fromJson(Map<String, dynamic> json) {
    return Shelf(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      layout: json['layout'] as String? ?? 'carousel',
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => MediaItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'layout': layout,
      'items': items.map((e) => e.toJson()).toList(),
    };
  }
}

class Feed {
  final List<Shelf> shelves;
  final String? continuation;
  final List<String>? chips;
  final bool? hasMore;
  final int? nextPage;

  Feed({
    required this.shelves,
    this.continuation,
    this.chips,
    this.hasMore,
    this.nextPage,
  });

  factory Feed.fromJson(Map<String, dynamic> json) {
    return Feed(
      shelves: (json['shelves'] as List<dynamic>?)
              ?.map((e) => Shelf.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      continuation: json['continuation'] as String?,
      chips: (json['chips'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      hasMore: json['hasMore'] as bool?,
      nextPage: json['nextPage'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shelves': shelves.map((e) => e.toJson()).toList(),
      'continuation': continuation,
      'chips': chips,
      'hasMore': hasMore,
      'nextPage': nextPage,
    };
  }
}

List<Shelf> orderHomeShelves(List<Shelf> shelves) {
  int rank(Shelf shelf) {
    if (shelf.id == 'quick-picks' || shelf.title.toLowerCase().contains('quick picks')) return 0;
    if (shelf.id.startsWith('discover-')) {
      final numStr = shelf.id.replaceAll('discover-', '');
      final pageNum = int.tryParse(numStr);
      if (pageNum != null) return pageNum * 10;
    }
    if (shelf.id.startsWith('personal-')) return 25;
    return 200;
  }

  final sorted = List<Shelf>.from(shelves);
  sorted.sort((a, b) => rank(a).compareTo(rank(b)));
  return sorted;
}

class TimedLyric {
  final double time;
  final String text;

  TimedLyric({required this.time, required this.text});

  factory TimedLyric.fromJson(Map<String, dynamic> json) {
    return TimedLyric(
      time: (json['time'] as num?)?.toDouble() ?? 0.0,
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'time': time,
    'text': text,
  };
}

class LyricsResponse {
  final String lyrics;
  final String? source;
  final bool synced;
  final String? syncSource;
  final List<TimedLyric> lines;

  LyricsResponse({
    required this.lyrics,
    this.source,
    this.synced = false,
    this.syncSource,
    this.lines = const [],
  });

  factory LyricsResponse.fromJson(Map<String, dynamic> json) {
    return LyricsResponse(
      lyrics: json['lyrics'] as String? ?? '',
      source: json['source'] as String?,
      synced: json['synced'] as bool? ?? false,
      syncSource: json['syncSource'] as String?,
      lines: (json['lines'] as List<dynamic>?)
              ?.map((e) => TimedLyric.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'lyrics': lyrics,
    'source': source,
    'synced': synced,
    'syncSource': syncSource,
    'lines': lines.map((e) => e.toJson()).toList(),
  };
}
