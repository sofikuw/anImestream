/// Video source result returned by anime extensions.
class ExtensionVideoSource {
  final String url;
  final String quality;
  final bool isM3U8;
  final Map<String, String>? headers;

  const ExtensionVideoSource({
    required this.url,
    required this.quality,
    this.isM3U8 = false,
    this.headers,
  });

  factory ExtensionVideoSource.fromJson(Map<String, dynamic> json) {
    Map<String, String>? hdrs;
    if (json['headers'] is Map) {
      hdrs = (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    final rawUrl = json['url']?.toString() ?? '';
    return ExtensionVideoSource(
      url: rawUrl,
      quality: json['quality']?.toString() ?? 'Auto',
      isM3U8: (json['isM3U8'] as bool?) ?? rawUrl.contains('.m3u8'),
      headers: hdrs,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'quality': quality,
    'isM3U8': isM3U8,
    if (headers != null) 'headers': headers,
  };
}

/// Subtitle track returned by anime extensions.
class ExtensionSubtitleTrack {
  final String url;
  final String language;
  final String format; // vtt, srt, ass

  const ExtensionSubtitleTrack({
    required this.url,
    required this.language,
    this.format = 'vtt',
  });

  factory ExtensionSubtitleTrack.fromJson(Map<String, dynamic> json) {
    return ExtensionSubtitleTrack(
      url: json['url']?.toString() ?? '',
      language: json['language']?.toString() ?? json['lang']?.toString() ?? 'English',
      format: json['format']?.toString() ?? 'vtt',
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'language': language,
    'format': format,
  };
}

/// Search or popular title item returned by anime extensions.
class ExtensionAnimeItem {
  final String id;
  final String title;
  final String posterUrl;
  final String? releaseYear;
  final String? type; // TV, Movie, OVA
  final double? rating;

  const ExtensionAnimeItem({
    required this.id,
    required this.title,
    required this.posterUrl,
    this.releaseYear,
    this.type,
    this.rating,
  });

  factory ExtensionAnimeItem.fromJson(Map<String, dynamic> json) {
    return ExtensionAnimeItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      posterUrl: json['posterUrl']?.toString() ?? json['poster']?.toString() ?? json['image']?.toString() ?? '',
      releaseYear: json['releaseYear']?.toString() ?? json['year']?.toString(),
      type: json['type']?.toString(),
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'posterUrl': posterUrl,
    'releaseYear': releaseYear,
    'type': type,
    'rating': rating,
  };
}

/// Anime Episode item.
class ExtensionAnimeEpisode {
  final String id;
  final int episodeNumber;
  final String title;
  final String? thumbnail;
  final String? description;

  const ExtensionAnimeEpisode({
    required this.id,
    required this.episodeNumber,
    required this.title,
    this.thumbnail,
    this.description,
  });

  factory ExtensionAnimeEpisode.fromJson(Map<String, dynamic> json) {
    int parseEp(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? 1;
      return 1;
    }

    return ExtensionAnimeEpisode(
      id: json['id']?.toString() ?? '',
      episodeNumber: parseEp(json['episodeNumber'] ?? json['number']),
      title: json['title']?.toString() ?? 'Episode ${json['number'] ?? ''}',
      thumbnail: json['thumbnail']?.toString() ?? json['image']?.toString(),
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'episodeNumber': episodeNumber,
    'title': title,
    'thumbnail': thumbnail,
    'description': description,
  };
}
