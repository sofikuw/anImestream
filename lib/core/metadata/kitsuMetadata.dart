import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/metadata/metadataTypes.dart';
import 'package:animestream/core/network/network.dart';

/// Kitsu as a read-only metadata fallback.
///
/// Kitsu needs no API key. It speaks JSON:API, so every payload arrives under
/// `data` and the useful fields sit under `attributes`.
class KitsuAnimeMetadata implements AnimeMetadataProvider {
  static const String _base = 'https://kitsu.io/api/edge';
  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/vnd.api+json',
  };

  @override
  String get id => 'kitsu';

  @override
  String get name => 'Kitsu';

  @override
  Future<List<AnimeMetadataSummary>> search(String query) async {
    final res = await get(
      '$_base/anime',
      headers: _headers,
      queryParameters: <String, String>{
        'filter[text]': query,
        'page[limit]': '15',
      },
      cacheDuration: const Duration(minutes: 10),
    );
    return _list(res.json);
  }

  @override
  Future<List<AnimeMetadataSummary>> trending() =>
      _listQuery(<String, String>{
        'filter[status]': 'current',
        'sort': '-userCount',
        'page[limit]': '20',
      });

  @override
  Future<List<AnimeMetadataSummary>> popular() =>
      _listQuery(<String, String>{
        'sort': '-userCount',
        'page[limit]': '20',
      });

  @override
  Future<List<AnimeMetadataSummary>> currentlyAiring() =>
      _listQuery(<String, String>{
        'filter[status]': 'current',
        'sort': '-userCount',
        'page[limit]': '20',
      });

  /// Kitsu's `-updatedAt` is a metadata timestamp, not an airing timestamp, and
  /// combining it with `filter[status]=current` returns an empty page. The
  /// currently-airing list is the useful fallback for this rail.
  @override
  Future<List<AnimeMetadataSummary>> recentlyUpdated() =>
      _listQuery(<String, String>{
        'filter[status]': 'current',
        'sort': '-userCount',
        'page[limit]': '20',
      });

  @override
  Future<List<AnimeMetadataSummary>> recommended() =>
      _listQuery(<String, String>{
        'sort': '-averageRating',
        'page[limit]': '20',
      });

  Future<List<AnimeMetadataSummary>> _listQuery(
    Map<String, String> query,
  ) async {
    final res = await get(
      '$_base/anime',
      headers: _headers,
      queryParameters: query,
      cacheDuration: const Duration(hours: 1),
    );
    return _list(res.json);
  }

  static List<AnimeMetadataSummary> _list(dynamic json) {
    if (json is! Map || json['data'] is! List) {
      return const <AnimeMetadataSummary>[];
    }
    return (json['data'] as List)
        .whereType<Map>()
        .where(_isSafe)
        .map((item) => _summary(Map<String, dynamic>.from(item)))
        .toList();
  }

  static AnimeMetadataSummary _summary(Map<String, dynamic> item) {
    final attributes = item['attributes'];
    if (attributes is! Map) {
      throw Exception('Kitsu returned an anime without attributes');
    }
    final attrs = Map<String, dynamic>.from(attributes);
    final genres = <String>[];

    return AnimeMetadataSummary(
      source: 'kitsu',
      providerId: item['id'].toString(),
      title: _titleMap(attrs),
      cover: _cover(attrs) ?? '',
      banner: _banner(attrs),
      rating: _rating(attrs['averageRating']),
      totalEpisodes: _int(attrs['episodeCount']),
      format: _format(attrs['subtype']),
      status: _animeStatus(attrs['status']),
      genres: genres,
    );
  }

  @override
  Future<AnimeMetadataDetails> details(String providerId) async {
    final res = await get(
      '$_base/anime/$providerId',
      headers: _headers,
      queryParameters: <String, String>{
        'include': 'categories,animeProductions.producer',
      },
      cacheDuration: const Duration(hours: 12),
    );
    final json = res.json;
    final data = json is Map ? json['data'] : null;
    if (data is! Map) {
      throw Exception('Kitsu returned no anime for id $providerId');
    }
    final item = Map<String, dynamic>.from(data);
    final summary = _summary(item);
    final attrs = Map<String, dynamic>.from(item['attributes'] as Map);
    final included = json is Map && json['included'] is List
        ? (json['included'] as List).whereType<Map>()
        : const <Map>[];

    final genres = <String>[];
    final studios = <String>[];
    for (final entry in included) {
      final type = entry['type']?.toString();
      final entryAttrs = entry['attributes'];
      if (entryAttrs is! Map) continue;
      if (type == 'categories') {
        final title = entryAttrs['title']?.toString();
        if (title != null && title.trim().isNotEmpty) genres.add(title);
      } else if (type == 'producers') {
        final name = entryAttrs['name']?.toString();
        if (name != null && name.trim().isNotEmpty) studios.add(name);
      }
    }

    return AnimeMetadataDetails(
      summary: summary,
      synopsis: _clean(attrs['synopsis']?.toString()),
      banner: summary.banner,
      genres: genres.isEmpty ? summary.genres : genres,
      studios: studios,
      duration: _duration(attrs['episodeLength']),
      episodes: summary.totalEpisodes,
      status: summary.status,
      type: summary.format,
      startDate: attrs['startDate']?.toString(),
      endDate: attrs['endDate']?.toString(),
      rating: summary.rating,
      synonyms: attrs['abbreviatedTitles'] is List
          ? (attrs['abbreviatedTitles'] as List)
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .toList()
          : const <String>[],
    );
  }

  static Map<String, String?> _titleMap(Map<String, dynamic> attrs) {
    final titles = attrs['titles'];
    final canonical = attrs['canonicalTitle']?.toString();
    return <String, String?>{
      'english': titles is Map ? titles['en']?.toString() : null,
      'romaji': titles is Map
          ? (titles['en_jp'] ?? titles['ja_jp'])?.toString()
          : canonical,
      'native': titles is Map ? titles['ja_jp']?.toString() : null,
    };
  }

  static String _title(Map<String, dynamic> attrs) {
    final canonical = attrs['canonicalTitle']?.toString();
    if (canonical != null && canonical.trim().isNotEmpty) return canonical;
    final titles = _titleMap(attrs);
    for (final key in const ['english', 'romaji', 'native']) {
      final value = titles[key];
      if (value != null && value.trim().isNotEmpty) return value;
    }
    return 'Unknown';
  }

  static String? _cover(Map<String, dynamic> attrs) {
    final poster = attrs['posterImage'];
    if (poster is! Map) return null;
    return (poster['large'] ?? poster['original'] ?? poster['medium'])
        ?.toString();
  }

  static String? _banner(Map<String, dynamic> attrs) {
    final cover = attrs['coverImage'];
    if (cover is! Map) return null;
    return (cover['large'] ?? cover['original'])?.toString();
  }

  static double? _rating(Object? value) {
    final raw = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (raw == null) return null;
    return double.parse((raw / 10).toStringAsFixed(1));
  }

  static String? _duration(Object? minutes) {
    if (minutes is! num || minutes <= 0) return null;
    return '${minutes.round()} min';
  }

  static String? _format(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text.toUpperCase();
  }

  static String? _animeStatus(Object? value) {
    switch (value?.toString()) {
      case 'current':
        return 'RELEASING';
      case 'finished':
        return 'FINISHED';
      case 'tba':
      case 'unreleased':
      case 'upcoming':
        return 'NOT_YET_RELEASED';
      default:
        return null;
    }
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static String? _clean(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return text
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .trim();
  }

  static bool _isSafe(Map item) {
    final attributes = item['attributes'];
    return attributes is! Map || attributes['nsfw'] != true;
  }
}

/// Kitsu manga metadata. Kitsu is the only fallback with a real
/// `sort=-updatedAt` list, which is why the router tries it first for the
/// "latest" manga rail.
class KitsuMangaMetadata implements MangaMetadataProvider {
  static const String _base = KitsuAnimeMetadata._base;
  static const Map<String, String> _headers = KitsuAnimeMetadata._headers;

  @override
  String get id => 'kitsu';

  @override
  String get name => 'Kitsu';

  @override
  Future<List<MangaSummary>> search(String query) async {
    final res = await get(
      '$_base/manga',
      headers: _headers,
      queryParameters: <String, String>{
        'filter[text]': query,
        'page[limit]': '15',
      },
      cacheDuration: const Duration(minutes: 10),
    );
    return _list(res.json);
  }

  @override
  Future<List<MangaSummary>> trending() => _listQuery(<String, String>{
        'sort': '-userCount',
        'page[limit]': '20',
      });

  @override
  Future<List<MangaSummary>> popular() => _listQuery(<String, String>{
        'sort': '-userCount',
        'page[limit]': '20',
      });

  @override
  Future<List<MangaSummary>> latest() => _listQuery(<String, String>{
        // Pairing -updatedAt with filter[status] gives Kitsu an empty page;
        // the unfiltered timestamp sort returns recently updated manga.
        'sort': '-updatedAt',
        'page[limit]': '20',
      });

  Future<List<MangaSummary>> _listQuery(Map<String, String> query) async {
    final res = await get(
      '$_base/manga',
      headers: _headers,
      queryParameters: query,
      cacheDuration: const Duration(hours: 1),
    );
    return _list(res.json);
  }

  static List<MangaSummary> _list(dynamic json) {
    if (json is! Map || json['data'] is! List) return const <MangaSummary>[];
    return (json['data'] as List)
        .whereType<Map>()
        .where(KitsuAnimeMetadata._isSafe)
        .map((item) => _summary(Map<String, dynamic>.from(item)))
        .toList();
  }

  static MangaSummary _summary(Map<String, dynamic> item) {
    final attributes = item['attributes'];
    if (attributes is! Map) {
      throw Exception('Kitsu returned a manga without attributes');
    }
    final attrs = Map<String, dynamic>.from(attributes);
    return MangaSummary(
      id: 'kitsu:${item['id']}',
      title: KitsuAnimeMetadata._title(attrs),
      cover: KitsuAnimeMetadata._cover(attrs),
      rating: KitsuAnimeMetadata._rating(attrs['averageRating']),
      format: KitsuAnimeMetadata._format(attrs['subtype']),
      status: _mangaStatus(attrs['status']),
      totalChapters: KitsuAnimeMetadata._int(attrs['chapterCount']),
    );
  }

  @override
  Future<MangaDetails> details(String providerId) async {
    final res = await get(
      '$_base/manga/$providerId',
      headers: _headers,
      queryParameters: <String, String>{'include': 'categories'},
      cacheDuration: const Duration(hours: 12),
    );
    final json = res.json;
    final data = json is Map ? json['data'] : null;
    if (data is! Map) {
      throw Exception('Kitsu returned no manga for id $providerId');
    }
    final item = Map<String, dynamic>.from(data);
    final summary = _summary(item);
    final attrs = Map<String, dynamic>.from(item['attributes'] as Map);
    final included = json is Map && json['included'] is List
        ? (json['included'] as List).whereType<Map>()
        : const <Map>[];

    final genres = <String>[];
    for (final entry in included) {
      if (entry['type'] != 'categories') continue;
      final entryAttrs = entry['attributes'];
      if (entryAttrs is! Map) continue;
      final title = entryAttrs['title']?.toString();
      if (title != null && title.trim().isNotEmpty) genres.add(title);
    }

    final titles = attrs['titles'];
    final native = titles is Map ? titles['ja_jp']?.toString() : null;

    return MangaDetails(
      summary: summary,
      synopsis: KitsuAnimeMetadata._clean(attrs['synopsis']?.toString()),
      banner: KitsuAnimeMetadata._banner(attrs),
      authors: const <String>[],
      characters: const <MangaCharacter>[],
      relations: const <MangaRelation>[],
      volumes: KitsuAnimeMetadata._int(attrs['volumeCount']),
      startDate: attrs['startDate']?.toString(),
      endDate: attrs['endDate']?.toString(),
      alternateTitles: _alternateTitles(attrs, summary.title),
      nativeTitle: native,
    );
  }

  static List<String> _alternateTitles(
    Map<String, dynamic> attrs,
    String primary,
  ) {
    final found = <String>[];
    final abbreviated = attrs['abbreviatedTitles'];
    if (abbreviated is List) {
      found.addAll(
        abbreviated
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty && value != primary),
      );
    }
    final titles = attrs['titles'];
    if (titles is Map) {
      for (final key in const ['en', 'en_jp', 'ja_jp']) {
        final value = titles[key]?.toString();
        if (value != null && value.trim().isNotEmpty && value != primary) {
          found.add(value);
        }
      }
    }
    return found;
  }

  static String? _mangaStatus(Object? value) {
    switch (value?.toString()) {
      case 'current':
        return 'RELEASING';
      case 'finished':
        return 'FINISHED';
      case 'tba':
      case 'unreleased':
      case 'upcoming':
        return 'NOT_YET_RELEASED';
      default:
        return null;
    }
  }
}
