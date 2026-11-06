import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/metadata/malMetadata.dart';
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

  static AnimeMetadataSummary _summary(
    Map<String, dynamic> item, {
    String? relationType,
    String? format,
  }) {
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
      format: format ?? _format(attrs['subtype']),
      status: _animeStatus(attrs['status']),
      relationType: relationType,
      genres: genres,
    );
  }

  @override
  Future<AnimeMetadataDetails> details(String providerId) async {
    final res = await get(
      '$_base/anime/$providerId',
      headers: _headers,
      queryParameters: <String, String>{
        'include':
            'categories,animeProductions.producer,characters.character,'
                'mediaRelationships.destination,mappings',
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
    final includedById = <String, Map<String, dynamic>>{};
    final included = json is Map && json['included'] is List
        ? (json['included'] as List).whereType<Map>()
        : const <Map>[];
    for (final entry in included) {
      final type = entry['type']?.toString();
      final id = entry['id']?.toString();
      if (type != null && id != null) {
        includedById['$type:$id'] = Map<String, dynamic>.from(entry);
      }
    }

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

    var recommended = const <AnimeMetadataSummary>[];
    final malId = _malId(includedById.values);
    final disabledMetadata =
        currentUserSettings?.disabledMetadataProviders ?? const <String>[];
    if (malId != null && !disabledMetadata.contains('mal')) {
      try {
        recommended = await MalAnimeMetadata().recommendationsFor(malId);
      } catch (_) {}
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
      related: _mediaRelations(item, includedById),
      recommended: recommended,
      characters: _characters(item, includedById),
      synonyms: attrs['abbreviatedTitles'] is List
          ? (attrs['abbreviatedTitles'] as List)
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .toList()
          : const <String>[],
    );
  }

  /// MAL's own `related_manga` / `related_anime` fields are documented as
  /// broken (they always come back empty). Kitsu has a mapping for most MAL
  /// entries, so it can supply the cross-media half of the relation rail.
  Future<List<AnimeMetadataSummary>> mangaRelationsForMal(String malId) async {
    final kitsuId = await _kitsuIdForMapping('myanimelist/anime', malId);
    if (kitsuId == null) return const <AnimeMetadataSummary>[];
    final res = await get(
      '$_base/anime/$kitsuId',
      headers: _headers,
      queryParameters: <String, String>{
        'include': 'mediaRelationships.destination',
      },
      cacheDuration: const Duration(hours: 12),
    );
    final json = res.json;
    final data = json is Map ? json['data'] : null;
    if (data is! Map) return const <AnimeMetadataSummary>[];
    final item = Map<String, dynamic>.from(data);
    final includedById = _includedById(json);
    return _mediaRelations(item, includedById)
        .where((summary) => (summary.format ?? '').toUpperCase() == 'MANGA')
        .toList(growable: false);
  }

  static Map<String, Map<String, dynamic>> _includedById(dynamic json) {
    final included = json is Map && json['included'] is List
        ? (json['included'] as List).whereType<Map>()
        : const <Map>[];
    final found = <String, Map<String, dynamic>>{};
    for (final entry in included) {
      final type = entry['type']?.toString();
      final id = entry['id']?.toString();
      if (type != null && id != null) {
        found['$type:$id'] = Map<String, dynamic>.from(entry);
      }
    }
    return found;
  }

  static final Map<String, String> _kitsuIds = <String, String>{};

  static Future<String?> _kitsuIdForMapping(
    String site,
    String externalId,
  ) async {
    final key = '$site:$externalId';
    final cached = _kitsuIds[key];
    if (cached != null) return cached;
    final res = await get(
      '$_base/mappings',
      headers: _headers,
      queryParameters: <String, String>{
        'filter[externalSite]': site,
        'filter[externalId]': externalId,
        'page[limit]': '1',
        'include': 'item',
      },
      cacheDuration: const Duration(days: 1),
    );
    final json = res.json;
    if (json is! Map || json['data'] is! List) return null;
    for (final row in (json['data'] as List).whereType<Map>()) {
      final relationships = row['relationships'];
      if (relationships is! Map) continue;
      final mapping = relationships['item'];
      if (mapping is! Map) continue;
      final item = mapping['data'];
      if (item is! Map) continue;
      final id = item['id']?.toString();
      if (id != null && id.isNotEmpty) {
        _kitsuIds[key] = id;
        return id;
      }
    }
    return null;
  }

  static List<AnimeMetadataSummary> _mediaRelations(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> includedById,
  ) {
    final relationships = item['relationships'];
    if (relationships is! Map) return const <AnimeMetadataSummary>[];
    final refs = relationships['mediaRelationships'];
    if (refs is! Map || refs['data'] is! List) {
      return const <AnimeMetadataSummary>[];
    }

    final found = <AnimeMetadataSummary>[];
    final seen = <String>{};
    for (final ref in (refs['data'] as List).whereType<Map>()) {
      final mediaRelation = includedById['${ref['type']}:${ref['id']}'];
      if (mediaRelation == null) continue;
      final destination = mediaRelation['relationships'];
      if (destination is! Map) continue;
      final target = destination['destination'];
      if (target is! Map) continue;
      final destinationRef = target['data'];
      if (destinationRef is! Map) continue;
      final key = '${destinationRef['type']}:${destinationRef['id']}';
      final media = includedById[key];
      if (media == null || !seen.add(key)) continue;
      final role = mediaRelation['attributes'];
      final relationType =
          role is Map ? role['role']?.toString().toUpperCase() : null;
      final isManga = destinationRef['type']?.toString() == 'manga';
      found.add(_summary(
        media,
        relationType: relationType,
        format: isManga ? 'MANGA' : null,
      ));
    }
    return found;
  }

  static List<Map<String, dynamic>> _characters(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> includedById,
  ) {
    final relationships = item['relationships'];
    if (relationships is! Map) return const <Map<String, dynamic>>[];
    final refs = relationships['characters'];
    if (refs is! Map || refs['data'] is! List) {
      return const <Map<String, dynamic>>[];
    }

    final found = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final ref in (refs['data'] as List).whereType<Map>()) {
      final mediaCharacter = includedById['${ref['type']}:${ref['id']}'];
      if (mediaCharacter == null) continue;
      final rel = mediaCharacter['relationships'];
      if (rel is! Map) continue;
      final characterRef = rel['character'];
      if (characterRef is! Map) continue;
      final characterData = characterRef['data'];
      if (characterData is! Map) continue;
      final key = '${characterData['type']}:${characterData['id']}';
      if (!seen.add(key)) continue;
      final character = includedById[key];
      if (character == null) continue;
      final attrs = character['attributes'];
      if (attrs is! Map) continue;
      final image = attrs['image'];
      final role = mediaCharacter['attributes'];
      found.add({
        'name': attrs['name']?.toString() ??
            attrs['canonicalName']?.toString() ??
            'Unknown',
        'role': (role is Map ? role['role']?.toString() : null)?.toUpperCase() ??
            'SUPPORTING',
        'image': (image is Map ? (image['original'] ?? image['large']) : null)
                ?.toString() ??
            '',
      });
    }
    return found;
  }

  static String? _malId(Iterable<Map<String, dynamic>> included) {
    for (final entry in included) {
      if (entry['type'] != 'mappings') continue;
      final attrs = entry['attributes'];
      if (attrs is! Map) continue;
      if (attrs['externalSite']?.toString() != 'myanimelist/anime') continue;
      final id = attrs['externalId']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
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
    if (currentUserSettings?.nsfwMode ?? false) return true;
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
      queryParameters: <String, String>{
        'include': 'categories,mediaRelationships.destination,mappings',
      },
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
    final includedById = <String, Map<String, dynamic>>{};
    for (final entry in included) {
      final type = entry['type']?.toString();
      final id = entry['id']?.toString();
      if (type != null && id != null) {
        includedById['$type:$id'] = Map<String, dynamic>.from(entry);
      }
    }

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

    var recommendations = const <MangaRelation>[];
    final malId = _malMangaId(includedById.values);
    final disabledMetadata =
        currentUserSettings?.disabledMetadataProviders ?? const <String>[];
    if (malId != null && !disabledMetadata.contains('mal')) {
      try {
        recommendations = await MalMangaMetadata().recommendationsFor(malId);
      } catch (_) {}
    }

    return MangaDetails(
      summary: summary,
      synopsis: KitsuAnimeMetadata._clean(attrs['synopsis']?.toString()),
      banner: KitsuAnimeMetadata._banner(attrs),
      authors: const <String>[],
      characters: const <MangaCharacter>[],
      relations: _mediaRelations(item, includedById),
      recommendations: recommendations,
      volumes: KitsuAnimeMetadata._int(attrs['volumeCount']),
      startDate: attrs['startDate']?.toString(),
      endDate: attrs['endDate']?.toString(),
      alternateTitles: _alternateTitles(attrs, summary.title),
      nativeTitle: native,
    );
  }

  /// MAL's `related_anime` field on manga is broken the same way as the anime
  /// side; Kitsu's manga mapping fills it in.
  Future<List<MangaRelation>> animeRelationsForMal(String malId) async {
    final kitsuId =
        await KitsuAnimeMetadata._kitsuIdForMapping('myanimelist/manga', malId);
    if (kitsuId == null) return const <MangaRelation>[];
    final res = await get(
      '$_base/manga/$kitsuId',
      headers: _headers,
      queryParameters: <String, String>{
        'include': 'mediaRelationships.destination',
      },
      cacheDuration: const Duration(hours: 12),
    );
    final json = res.json;
    final data = json is Map ? json['data'] : null;
    if (data is! Map) return const <MangaRelation>[];
    final item = Map<String, dynamic>.from(data);
    return _mediaRelations(item, KitsuAnimeMetadata._includedById(json))
        .where((relation) => relation.type == 'ANIME')
        .toList(growable: false);
  }

  /// Kitsu splits relations by destination type: an adaptation points at an
  /// anime, other editions point at manga. Both belong on the manga page, but
  /// only the manga links stay inside the manga reader.
  static List<MangaRelation> _mediaRelations(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> includedById,
  ) {
    final relationships = item['relationships'];
    if (relationships is! Map) return const <MangaRelation>[];
    final refs = relationships['mediaRelationships'];
    if (refs is! Map || refs['data'] is! List) {
      return const <MangaRelation>[];
    }

    final found = <MangaRelation>[];
    final seen = <String>{};
    for (final ref in (refs['data'] as List).whereType<Map>()) {
      final mediaRelation = includedById['${ref['type']}:${ref['id']}'];
      if (mediaRelation == null) continue;
      final destination = mediaRelation['relationships'];
      if (destination is! Map) continue;
      final target = destination['destination'];
      if (target is! Map) continue;
      final destinationRef = target['data'];
      if (destinationRef is! Map) continue;
      final type = destinationRef['type']?.toString();
      final id = destinationRef['id']?.toString();
      if (type == null || id == null) continue;
      final media = includedById['$type:$id'];
      if (media == null) continue;
      final role = mediaRelation['attributes'];
      final relation = _relation(
        media,
        type: type,
        relationType: role is Map
            ? role['role']?.toString().toUpperCase()
            : null,
      );
      if (relation == null || !seen.add(relation.id)) continue;
      found.add(relation);
    }
    return found;
  }

  static MangaRelation? _relation(
    Map<String, dynamic> media, {
    required String type,
    String? relationType,
  }) {
    final id = media['id']?.toString();
    final attributes = media['attributes'];
    if (id == null || attributes is! Map) return null;
    final attrs = Map<String, dynamic>.from(attributes);
    final title = KitsuAnimeMetadata._title(attrs);
    final cover = KitsuAnimeMetadata._cover(attrs);
    final rating = KitsuAnimeMetadata._rating(attrs['averageRating']);
    if (type == 'anime') {
      final animeId = animeFallbackId('kitsu', id);
      if (animeId == null) return null;
      return MangaRelation(
        id: animeId.toString(),
        title: title,
        cover: cover,
        type: 'ANIME',
        relationType: relationType,
        rating: rating,
      );
    }
    return MangaRelation(
      id: 'kitsu:$id',
      title: title,
      cover: cover,
      type: 'MANGA',
      relationType: relationType,
      rating: rating,
    );
  }

  static String? _malMangaId(Iterable<Map<String, dynamic>> included) {
    for (final entry in included) {
      if (entry['type'] != 'mappings') continue;
      final attrs = entry['attributes'];
      if (attrs is! Map) continue;
      if (attrs['externalSite']?.toString() != 'myanimelist/manga') continue;
      final id = attrs['externalId']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
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
