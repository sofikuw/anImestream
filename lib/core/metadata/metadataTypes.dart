import 'package:animestream/core/manga/types.dart';

/// Thrown when AniList is unavailable and none of the configured fallbacks
/// could answer. Callers already treat metadata failures as recoverable, so
/// this is a plain exception rather than a new error channel.
class MetadataUnavailableException implements Exception {
  final String message;

  const MetadataUnavailableException(this.message);

  @override
  String toString() => message;
}

/// A search / browse result from a fallback metadata provider.
///
/// [source] is the provider's stable id ("mal", "kitsu") and [providerId] is
/// the id that provider uses. The routers turn the pair into an app-local id
/// before handing a result to the UI, so the rest of the app never has to know
/// which site a card came from.
class AnimeMetadataSummary {
  final String source;
  final String providerId;
  final Map<String, String?> title;
  final String cover;
  final String? banner;

  /// 0..10, matching the app's cards and [DatabaseInfo.rating].
  final double? rating;

  final int? totalEpisodes;
  final String? format;
  final String? status;
  final List<String> genres;

  AnimeMetadataSummary({
    required this.source,
    required this.providerId,
    required this.title,
    required this.cover,
    this.banner,
    this.rating,
    this.totalEpisodes,
    this.format,
    this.status,
    List<String> genres = const <String>[],
  }) : genres = List<String>.unmodifiable(genres);
}

class AnimeMetadataDetails {
  final AnimeMetadataSummary summary;
  final String? synopsis;
  final String? banner;
  final List<String> genres;
  final List<String> studios;
  final String? duration;
  final int? episodes;
  final String? status;
  final String? type;
  final String? startDate;
  final String? endDate;
  final double? rating;
  final List<AnimeMetadataSummary> related;
  final List<AnimeMetadataSummary> recommended;
  final List<String> synonyms;

  AnimeMetadataDetails({
    required this.summary,
    this.synopsis,
    this.banner,
    List<String> genres = const <String>[],
    List<String> studios = const <String>[],
    this.duration,
    this.episodes,
    this.status,
    this.type,
    this.startDate,
    this.endDate,
    this.rating,
    List<AnimeMetadataSummary> related = const <AnimeMetadataSummary>[],
    List<AnimeMetadataSummary> recommended = const <AnimeMetadataSummary>[],
    List<String> synonyms = const <String>[],
  })  : genres = List<String>.unmodifiable(genres),
        studios = List<String>.unmodifiable(studios),
        related = List<AnimeMetadataSummary>.unmodifiable(related),
        recommended = List<AnimeMetadataSummary>.unmodifiable(recommended),
        synonyms = List<String>.unmodifiable(synonyms);
}

abstract class AnimeMetadataProvider {
  /// Stable id used in settings: "mal" or "kitsu".
  String get id;

  /// Display name.
  String get name;

  Future<List<AnimeMetadataSummary>> search(String query);
  Future<List<AnimeMetadataSummary>> trending();
  Future<List<AnimeMetadataSummary>> popular();
  Future<List<AnimeMetadataSummary>> currentlyAiring();
  Future<List<AnimeMetadataSummary>> recentlyUpdated();
  Future<List<AnimeMetadataSummary>> recommended();
  Future<AnimeMetadataDetails> details(String providerId);
}

abstract class MangaMetadataProvider {
  /// Stable id used in settings: "mal" or "kitsu".
  String get id;

  /// Display name.
  String get name;

  Future<List<MangaSummary>> search(String query);
  Future<List<MangaSummary>> trending();
  Future<List<MangaSummary>> popular();
  Future<List<MangaSummary>> latest();

  /// [providerId] is the raw id from this provider, without the app prefix.
  Future<MangaDetails> details(String providerId);
}
