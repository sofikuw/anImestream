import 'package:animestream/core/database/mal/login.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/metadata/metadataTypes.dart';
import 'package:animestream/core/network/network.dart';

/// MyAnimeList as a read-only metadata fallback.
///
/// Uses MAL's public client-id header, not the signed-in user's token: search
/// and browse must work without an account. The user token stays the business
/// of [MALLogin] and the list sync code.
class MalAnimeMetadata implements AnimeMetadataProvider {
  static const String _base = 'https://api.myanimelist.net/v2';

  static const Map<String, String> _headers = <String, String>{
    'X-MAL-CLIENT-ID': MALLogin.clientId,
    'Accept': 'application/json',
  };

  /// Details requests can fail while rankings still work (MAL reports
  /// maintenance per endpoint). Keeping the last summary lets the fallback
  /// card still open with its cover and title.
  static final Map<String, AnimeMetadataSummary> _summaries =
      <String, AnimeMetadataSummary>{};

  static const String _animeFields =
      'id,title,main_picture,alternative_titles,start_date,end_date,synopsis,'
      'mean,media_type,status,genres,num_episodes,average_episode_duration,'
      'studios,related_anime,recommendations';

  static const String _mangaFields =
      'id,title,main_picture,alternative_titles,start_date,end_date,synopsis,'
      'mean,media_type,status,genres,num_volumes,num_chapters,'
      'authors{first_name,last_name},related_manga,recommendations';

  @override
  String get id => 'mal';

  @override
  String get name => 'MyAnimeList';

  @override
  Future<List<AnimeMetadataSummary>> search(String query) =>
      _searchAnime(query);

  @override
  Future<List<AnimeMetadataSummary>> trending() =>
      _ranking('bypopularity');

  @override
  Future<List<AnimeMetadataSummary>> popular() =>
      _ranking('bypopularity');

  @override
  Future<List<AnimeMetadataSummary>> currentlyAiring() => _ranking('airing');

  @override
  Future<List<AnimeMetadataSummary>> recentlyUpdated() => _ranking('airing');

  @override
  Future<List<AnimeMetadataSummary>> recommended() => _ranking('favorite');

  Future<List<AnimeMetadataSummary>> _searchAnime(String query) async {
    final res = await get(
      '$_base/anime',
      headers: _headers,
      queryParameters: <String, String>{
        'q': query,
        'limit': '15',
        'nsfw': 'false',
        'fields': _animeFields,
      },
      cacheDuration: Duration.zero,
    );
    return _list(res.json);
  }

  Future<List<AnimeMetadataSummary>> _ranking(String rankingType) async {
    final res = await get(
      '$_base/anime/ranking',
      headers: _headers,
      queryParameters: <String, String>{
        'ranking_type': rankingType,
        'limit': '25',
        'nsfw': 'false',
        'fields': _animeFields,
      },
      cacheDuration: Duration.zero,
    );
    return _list(res.json);
  }

  static List<AnimeMetadataSummary> _list(dynamic json) {
    if (json is Map && json['error'] != null) {
      throw Exception('MAL: ${json['message'] ?? json['error']}');
    }
    if (json is! Map || json['data'] is! List) {
      return const <AnimeMetadataSummary>[];
    }
    return (json['data'] as List)
        .whereType<Map>()
        .map((row) => row['node'])
        .whereType<Map>()
        .map((node) => _summaryAnime(Map<String, dynamic>.from(node)))
        .toList();
  }

  static AnimeMetadataSummary _summaryAnime(Map<String, dynamic> node) {
    final picture = node['main_picture'];
    final cover = picture is Map
        ? (picture['large'] ?? picture['medium'])?.toString()
        : null;
    final genres = node['genres'];
    final episodes = _int(node['num_episodes']);

    final summary = AnimeMetadataSummary(
      source: 'mal',
      providerId: node['id'].toString(),
      title: _titleMap(node),
      cover: cover ?? '',
      rating: _double(node['mean']),
      // MAL reports 0 for a show whose episode count is not announced yet.
      totalEpisodes: episodes == 0 ? null : episodes,
      format: _format(node['media_type']),
      status: _animeStatus(node['status']),
      genres: genres is List
          ? genres
              .whereType<Map>()
              .map((genre) => genre['name']?.toString())
              .whereType<String>()
              .toList()
          : const <String>[],
    );
    _summaries[summary.providerId] = summary;
    return summary;
  }

  @override
  Future<AnimeMetadataDetails> details(String providerId) async {
    final cached = _summaries[providerId];
    try {
      final res = await get(
        '$_base/anime/$providerId',
        headers: _headers,
        queryParameters: <String, String>{'fields': _animeFields},
        cacheDuration: Duration.zero,
      );
      final json = res.json;
      if (json is! Map || json['id'] == null) {
        throw Exception('MAL returned no anime for id $providerId');
      }
      final node = Map<String, dynamic>.from(json);
      final summary = _summaryAnime(node);
      final alt = node['alternative_titles'];

      return AnimeMetadataDetails(
        summary: summary,
        synopsis: _clean(node['synopsis']?.toString()),
        banner: summary.banner,
        genres: summary.genres,
        studios: _names(node['studios']),
        duration: _duration(node['average_episode_duration']),
        episodes: summary.totalEpisodes,
        status: summary.status,
        type: summary.format,
        startDate: node['start_date']?.toString(),
        endDate: node['end_date']?.toString(),
        rating: summary.rating,
        related: _relations(node['related_anime']),
        recommended: _relations(node['recommendations']),
        synonyms: alt is Map && alt['synonyms'] is List
            ? (alt['synonyms'] as List).whereType<String>().toList()
            : const <String>[],
      );
    } catch (_) {
      if (cached == null) rethrow;
      // The ranking endpoint can answer while the details endpoint is in
      // maintenance. Show the card we already have rather than an error page.
      return AnimeMetadataDetails(
        summary: cached,
        genres: cached.genres,
        episodes: cached.totalEpisodes,
        status: cached.status,
        type: cached.format,
        rating: cached.rating,
      );
    }
  }

  static List<AnimeMetadataSummary> _relations(Object? value) {
    if (value is! List) return const <AnimeMetadataSummary>[];
    return value
        .whereType<Map>()
        .map((row) => row['node'])
        .whereType<Map>()
        .map((node) => _summaryAnime(Map<String, dynamic>.from(node)))
        .toList();
  }

  static Map<String, String?> _titleMap(Map<String, dynamic> node) {
    final alt = node['alternative_titles'];
    return <String, String?>{
      'english': alt is Map ? alt['en']?.toString() : null,
      'romaji': node['title']?.toString(),
      'native': alt is Map ? alt['ja']?.toString() : null,
    };
  }

  static String _title(Map<String, dynamic> node) {
    final titles = _titleMap(node);
    for (final key in const ['english', 'romaji', 'native']) {
      final value = titles[key];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return 'Unknown';
  }

  static List<String> _names(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<Map>()
        .map((item) => item['name']?.toString())
        .whereType<String>()
        .toList();
  }

  static String? _duration(Object? seconds) {
    if (seconds is! num || seconds <= 0) return null;
    return '${(seconds / 60).round()} min';
  }

  static String? _format(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text.toUpperCase();
  }

  static String? _animeStatus(Object? value) {
    switch (value?.toString()) {
      case 'currently_airing':
        return 'RELEASING';
      case 'finished_airing':
        return 'FINISHED';
      case 'not_yet_aired':
        return 'NOT_YET_RELEASED';
      default:
        return null;
    }
  }

  static String? _mangaStatus(Object? value) {
    switch (value?.toString()) {
      case 'currently_publishing':
        return 'RELEASING';
      case 'finished':
        return 'FINISHED';
      case 'not_yet_published':
        return 'NOT_YET_RELEASED';
      case 'on_hiatus':
        return 'HIATUS';
      case 'discontinued':
        return 'CANCELLED';
      default:
        return null;
    }
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double? _double(Object? value) =>
      value is num ? value.toDouble() : null;

  static String? _clean(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  static String? _nativeTitle(Map<String, dynamic> node) {
    final alt = node['alternative_titles'];
    return alt is Map ? alt['ja']?.toString() : null;
  }

  static List<String> _alternateTitles(Map<String, dynamic> node) {
    final titles = <String>[];
    final alt = node['alternative_titles'];
    if (alt is Map) {
      for (final key in const ['en', 'ja']) {
        final value = alt[key]?.toString();
        if (value != null && value.trim().isNotEmpty) titles.add(value);
      }
      if (alt['synonyms'] is List) {
        titles.addAll(
          (alt['synonyms'] as List).whereType<String>().where(
                (value) => value.trim().isNotEmpty,
              ),
        );
      }
    }
    final primary = _title(node);
    return titles.where((value) => value != primary).toList();
  }
}

/// MyAnimeList manga metadata. Shares the client-id header with the anime half.
class MalMangaMetadata implements MangaMetadataProvider {
  static const String _base = MalAnimeMetadata._base;

  static final Map<String, MangaSummary> _summaries = <String, MangaSummary>{};
  static const Map<String, String> _headers = MalAnimeMetadata._headers;
  static const String _fields = MalAnimeMetadata._mangaFields;

  @override
  String get id => 'mal';

  @override
  String get name => 'MyAnimeList';

  @override
  Future<List<MangaSummary>> search(String query) async {
    final res = await get(
      '$_base/manga',
      headers: _headers,
      queryParameters: <String, String>{
        'q': query,
        'limit': '15',
        'nsfw': 'false',
        'fields': _fields,
      },
      cacheDuration: Duration.zero,
    );
    return _list(res.json);
  }

  @override
  Future<List<MangaSummary>> trending() => _ranking('bypopularity');

  @override
  Future<List<MangaSummary>> popular() => _ranking('bypopularity');

  /// MAL has no "updated at" ordering. The popularity ranking is the closest
  /// read-only list it offers; Kitsu is tried first by the router for this rail.
  @override
  Future<List<MangaSummary>> latest() => _ranking('bypopularity');

  Future<List<MangaSummary>> _ranking(String rankingType) async {
    final res = await get(
      '$_base/manga/ranking',
      headers: _headers,
      queryParameters: <String, String>{
        'ranking_type': rankingType,
        'limit': '25',
        'nsfw': 'false',
        'fields': _fields,
      },
      cacheDuration: Duration.zero,
    );
    return _list(res.json);
  }

  static List<MangaSummary> _list(dynamic json) {
    if (json is Map && json['error'] != null) {
      throw Exception('MAL: ${json['message'] ?? json['error']}');
    }
    if (json is! Map || json['data'] is! List) return const <MangaSummary>[];
    return (json['data'] as List)
        .whereType<Map>()
        .map((row) => row['node'])
        .whereType<Map>()
        .map((node) => _summary(Map<String, dynamic>.from(node)))
        .toList();
  }

  static MangaSummary _summary(Map<String, dynamic> node) {
    final picture = node['main_picture'];
    final cover = picture is Map
        ? (picture['large'] ?? picture['medium'])?.toString()
        : null;
    final genres = node['genres'];

    final summary = MangaSummary(
      id: 'mal:${node['id']}',
      title: MalAnimeMetadata._title(node),
      cover: cover,
      rating: MalAnimeMetadata._double(node['mean']),
      format: MalAnimeMetadata._format(node['media_type']),
      status: MalAnimeMetadata._mangaStatus(node['status']),
      totalChapters: MalAnimeMetadata._int(node['num_chapters']),
      genres: genres is List
          ? genres
              .whereType<Map>()
              .map((genre) => genre['name']?.toString())
              .whereType<String>()
              .toList()
          : const <String>[],
    );
    _summaries[summary.id] = summary;
    return summary;
  }

  @override
  Future<MangaDetails> details(String providerId) async {
    final cached = _summaries['mal:$providerId'];
    try {
      final res = await get(
        '$_base/manga/$providerId',
        headers: _headers,
        queryParameters: <String, String>{'fields': _fields},
        cacheDuration: Duration.zero,
      );
      final json = res.json;
      if (json is! Map || json['id'] == null) {
        throw Exception('MAL returned no manga for id $providerId');
      }
      final node = Map<String, dynamic>.from(json);
      final summary = _summary(node);
      final authors = <String>[];
      final authorRows = node['authors'];
      if (authorRows is List) {
        for (final row in authorRows.whereType<Map>()) {
          final person = row['node'];
          if (person is! Map) continue;
          final name = [
            person['first_name']?.toString(),
            person['last_name']?.toString(),
          ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');
          if (name.isNotEmpty) authors.add(name);
        }
      }

      return MangaDetails(
        summary: summary,
        synopsis: MalAnimeMetadata._clean(node['synopsis']?.toString()),
        banner: null,
        authors: authors,
        characters: const <MangaCharacter>[],
        relations: _relations(node['related_manga']),
        volumes: MalAnimeMetadata._int(node['num_volumes']),
        startDate: node['start_date']?.toString(),
        endDate: node['end_date']?.toString(),
        alternateTitles: MalAnimeMetadata._alternateTitles(node),
        nativeTitle: MalAnimeMetadata._nativeTitle(node),
      );
    } catch (_) {
      if (cached == null) rethrow;
      return MangaDetails(
        summary: cached,
        banner: null,
        authors: const <String>[],
        characters: const <MangaCharacter>[],
        relations: const <MangaRelation>[],
      );
    }
  }

  static List<MangaRelation> _relations(Object? value) {
    if (value is! List) return const <MangaRelation>[];
    final found = <MangaRelation>[];
    for (final row in value.whereType<Map>()) {
      final node = row['node'];
      if (node is! Map) continue;
      final typed = Map<String, dynamic>.from(node);
      final picture = typed['main_picture'];
      found.add(
        MangaRelation(
          id: 'mal:${typed['id']}',
          title: MalAnimeMetadata._title(typed),
          cover: picture is Map
              ? (picture['large'] ?? picture['medium'])?.toString()
              : null,
          type: MalAnimeMetadata._format(typed['media_type']),
          relationType:
              (row['relation_type_formatted'] ?? row['relation_type'])?.toString(),
        ),
      );
    }
    return found;
  }
}
