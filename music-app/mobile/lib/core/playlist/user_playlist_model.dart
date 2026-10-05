class UserPlaylist {
  final String id;
  final String name;
  final String description;
  final String? coverUrl;
  final int songCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.coverUrl,
    this.songCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserPlaylist.fromJson(Map<String, dynamic> json) {
    return UserPlaylist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled Playlist',
      description: json['description'] as String? ?? '',
      coverUrl: json['cover_url'] as String?,
      songCount: (json['song_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'cover_url': coverUrl,
    'song_count': songCount,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  UserPlaylist copyWith({
    String? name,
    String? description,
    String? coverUrl,
    int? songCount,
    DateTime? updatedAt,
  }) {
    return UserPlaylist(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      coverUrl: coverUrl ?? this.coverUrl,
      songCount: songCount ?? this.songCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
