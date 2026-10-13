import 'package:animestream/core/anime/providers/types.dart';
import 'package:animestream/core/database/types.dart';

class ServerSelectionBottomSheetContentData {
  final int episodeIndex;
  final String title;
  final List<String> epLinks;
  final String selectedSource;
  final int id;
  final String cover;
  final int? totalEpisodes;
  final double? lastWatchDuration;

  ServerSelectionBottomSheetContentData({
    required this.episodeIndex,
    required this.epLinks,
    required this.selectedSource,
    required this.title,
    required this.id,
    required this.cover,
    required this.lastWatchDuration,
    this.totalEpisodes,
  });
}

class WatchPageInfo {
  int episodeNumber;
  final String animeTitle;
  VideoStream streamInfo;
  int id;
  List<AlternateDatabaseId> altDatabases;
  double? lastWatchDuration;
  List<VideoStream> allStreams;

  WatchPageInfo({
    required this.id,
    required this.animeTitle,
    required this.episodeNumber,
    required this.streamInfo,
    required this.altDatabases,
    required this.lastWatchDuration,
    this.allStreams = const [],
  });
}

/// One row on the Home page: a Continue Watching entry, an airing show, or a
/// planned title.
///
/// [id] is a String rather than an int because a row can now describe a manga,
/// and AniList manga ids and provider-scoped ids are not guaranteed to stay
/// integers. Anime call sites pass `item.id.toString()`; the persistence layer
/// (`watching.dart`) already round-trips through a Map, so nothing else has to
/// change type.
class HomePageList {
  final String coverImage;
  final double? rating;
  final Map<String, String?> title;
  final String id;
  final int? totalEpisodes;
  final int? watchedEpisodeCount;

  /// Which details page this row opens: "anime" or "manga".
  ///
  /// Kept as a plain String rather than an enum so stored rows written before
  /// this field existed still deserialize -- [fromMap] defaults it to "anime",
  /// which is what every pre-existing row was.
  final String contentType;

  HomePageList({
    required this.coverImage,
    required this.rating,
    required this.title,
    required this.id,
    this.totalEpisodes,
    this.watchedEpisodeCount,
    this.contentType = 'anime',
  });

  static String contentTypeOf(Map<String, dynamic> map) {
    final raw = map['contentType'];
    return raw is String && raw.isNotEmpty ? raw : 'anime';
  }

  factory HomePageList.fromMap(Map<String, dynamic> map) => HomePageList(
        coverImage: map['coverImage'] as String,
        rating: (map['rating'] as num?)?.toDouble(),
        title: (map['title'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value as String?),
            ) ??
            const <String, String?>{},
        id: map['id'].toString(),
        totalEpisodes: (map['totalEpisodes'] as num?)?.toInt(),
        watchedEpisodeCount: (map['watchedEpisodeCount'] as num?)?.toInt(),
        contentType: contentTypeOf(map),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'coverImage': coverImage,
        'rating': rating,
        'title': title,
        'id': id,
        'totalEpisodes': totalEpisodes,
        'watchedEpisodeCount': watchedEpisodeCount,
        'contentType': contentType,
      };
}