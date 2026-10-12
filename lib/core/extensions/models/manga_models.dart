import 'dart:convert';

enum MangaStatus {
  ongoing,
  completed,
  hiatus,
  cancelled,
  unknown;

  static MangaStatus fromString(String? val) {
    if (val == null) return MangaStatus.unknown;
    switch (val.toLowerCase().trim()) {
      case 'ongoing':
      case 'publishing':
        return MangaStatus.ongoing;
      case 'completed':
      case 'finished':
        return MangaStatus.completed;
      case 'hiatus':
      case 'on_hiatus':
        return MangaStatus.hiatus;
      case 'cancelled':
      case 'discontinued':
        return MangaStatus.cancelled;
      default:
        return MangaStatus.unknown;
    }
  }

  String toDisplayString() {
    switch (this) {
      case MangaStatus.ongoing:
        return 'Ongoing';
      case MangaStatus.completed:
        return 'Completed';
      case MangaStatus.hiatus:
        return 'On Hiatus';
      case MangaStatus.cancelled:
        return 'Cancelled';
      case MangaStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Representation of a Manga title in Animestream.
class MangaDetails {
  final String id;
  final String title;
  final String coverUrl;
  final String description;
  final String? author;
  final String? artist;
  final List<String> genres;
  final MangaStatus status;
  final String? releaseYear;
  final String providerId;
  final double? rating;
  final String? url;
  final int totalChapters;

  const MangaDetails({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.description,
    this.author,
    this.artist,
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.releaseYear,
    required this.providerId,
    this.rating,
    this.url,
    this.totalChapters = 0,
  });

  factory MangaDetails.fromJson(Map<String, dynamic> json, {String providerId = ''}) {
    return MangaDetails(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled',
      coverUrl: json['coverUrl']?.toString() ?? json['cover']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString(),
      artist: json['artist']?.toString(),
      genres: (json['genres'] as List? ?? []).map((e) => e.toString()).toList(),
      status: MangaStatus.fromString(json['status']?.toString()),
      releaseYear: json['releaseYear']?.toString() ?? json['year']?.toString(),
      providerId: json['providerId']?.toString() ?? providerId,
      rating: (json['rating'] is num) ? (json['rating'] as num).toDouble() : null,
      url: json['url']?.toString(),
      totalChapters: (json['totalChapters'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'description': description,
    'author': author,
    'artist': artist,
    'genres': genres,
    'status': status.name,
    'releaseYear': releaseYear,
    'providerId': providerId,
    'rating': rating,
    'url': url,
    'totalChapters': totalChapters,
  };
}

/// Individual Chapter of a Manga.
class MangaChapter {
  final String id;
  final String mangaId;
  final String title;
  final double chapterNumber;
  final String? scanlator;
  final String? releaseDate;
  final String? url;
  final bool isRead;
  final int lastPageRead;

  const MangaChapter({
    required this.id,
    required this.mangaId,
    required this.title,
    required this.chapterNumber,
    this.scanlator,
    this.releaseDate,
    this.url,
    this.isRead = false,
    this.lastPageRead = 0,
  });

  factory MangaChapter.fromJson(Map<String, dynamic> json, {String mangaId = ''}) {
    double parseChapNum(dynamic val) {
      if (val is num) return val.toDouble();
      if (val is String) {
        final parsed = double.tryParse(val);
        if (parsed != null) return parsed;
      }
      return 0.0;
    }

    return MangaChapter(
      id: json['id']?.toString() ?? '',
      mangaId: json['mangaId']?.toString() ?? mangaId,
      title: json['title']?.toString() ?? 'Chapter ${json['number'] ?? ''}',
      chapterNumber: parseChapNum(json['chapterNumber'] ?? json['number']),
      scanlator: json['scanlator']?.toString(),
      releaseDate: json['releaseDate']?.toString() ?? json['date']?.toString(),
      url: json['url']?.toString(),
      isRead: json['isRead'] as bool? ?? false,
      lastPageRead: json['lastPageRead'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'mangaId': mangaId,
    'title': title,
    'chapterNumber': chapterNumber,
    'scanlator': scanlator,
    'releaseDate': releaseDate,
    'url': url,
    'isRead': isRead,
    'lastPageRead': lastPageRead,
  };
}

/// Single Page of a chapter with image URL and request headers.
class MangaPage {
  final int index;
  final String imageUrl;
  final Map<String, String>? headers;

  const MangaPage({
    required this.index,
    required this.imageUrl,
    this.headers,
  });

  factory MangaPage.fromJson(Map<String, dynamic> json, int defaultIndex) {
    Map<String, String>? hdrs;
    if (json['headers'] is Map) {
      hdrs = (json['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    return MangaPage(
      index: (json['index'] as int?) ?? defaultIndex,
      imageUrl: json['imageUrl']?.toString() ?? json['url']?.toString() ?? '',
      headers: hdrs,
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'imageUrl': imageUrl,
    if (headers != null) 'headers': headers,
  };
}

/// Reading progress for a Manga title.
class ReadingProgress {
  final String mangaId;
  final String chapterId;
  final double chapterNumber;
  final int pageIndex;
  final int totalPages;
  final DateTime updatedAt;

  const ReadingProgress({
    required this.mangaId,
    required this.chapterId,
    required this.chapterNumber,
    required this.pageIndex,
    required this.totalPages,
    required this.updatedAt,
  });

  double get percent {
    if (totalPages <= 0) return 0.0;
    return ((pageIndex + 1) / totalPages).clamp(0.0, 1.0);
  }

  factory ReadingProgress.fromJson(Map<String, dynamic> json) => ReadingProgress(
    mangaId: json['mangaId'] as String,
    chapterId: json['chapterId'] as String,
    chapterNumber: (json['chapterNumber'] as num).toDouble(),
    pageIndex: json['pageIndex'] as int,
    totalPages: json['totalPages'] as int,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'mangaId': mangaId,
    'chapterId': chapterId,
    'chapterNumber': chapterNumber,
    'pageIndex': pageIndex,
    'totalPages': totalPages,
    'updatedAt': updatedAt.toIso8601String(),
  };
}
