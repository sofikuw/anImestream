import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/commons/utils.dart';
import 'package:animestream/core/data/secureStorage.dart';
import 'package:animestream/core/database/anilist/anilist.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';

/// AniList as the manga *metadata* source.
///
/// Reuses the existing AniList plumbing (`Anilist.fetchQuery`, request types,
/// response caching and the stored auth token) rather than adding a second
/// GraphQL client. It is composed rather than subclassed on purpose:
/// `Anilist.getTrending()` returns `List<TrendingResult>` for anime, which
/// cannot override this interface's `Future<List<MangaSummary>> getTrending()`.
///
/// This source deliberately exposes no chapters or pages. AniList knows a manga
/// has N chapters; it never lists them.
///
/// Shipped as a whole file rather than as a patch. The `alternateTitles` /
/// `nativeTitle` plumbing was attempted as string edits three times and each
/// attempt left duplicated declarations behind, because the anchor text
/// survived its own replacement and the exactly-once guard could not see the
/// second application. A whole file cannot drift.
class AnilistManga implements MangaMetadataSource {
  final Anilist _anilist = Anilist();

  @override
  String get sourceName => 'AniList';

  /// Selected by both the card and detail queries.
  static const String _summaryFields = '''
    id
    title { english romaji native }
    coverImage { large extraLarge }
    averageScore
    format
    status
    chapters
    genres
  ''';

  /// AniList classifies light novels as `type: MANGA` as well, so the format
  /// filter keeps novels out of the manga tab. Widen it to include NOVEL to
  /// show them.
  static const String _mangaOnly =
      'type: MANGA, format_in: [MANGA, ONE_SHOT], isAdult: false';

  @override
  Future<List<MangaSummary>> getTrending() => _list('''
    query {
      Page(perPage: 25) {
        media($_mangaOnly, sort: TRENDING_DESC) { $_summaryFields }
      }
    }
  ''');

  @override
  Future<List<MangaSummary>> getPopular() => _list('''
    query {
      Page(perPage: 25) {
        media($_mangaOnly, sort: POPULARITY_DESC) { $_summaryFields }
      }
    }
  ''');

  @override
  Future<List<MangaSummary>> getLatest() => _list('''
    query {
      Page(perPage: 25) {
        media($_mangaOnly, sort: UPDATED_AT_DESC) { $_summaryFields }
      }
    }
  ''');

  @override
  Future<List<MangaSummary>> search(String query) {
    // AniList takes the search term inside the GraphQL document, so a raw quote
    // or backslash would break the query. Escape before interpolating.
    final escaped = query
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', ' ');
    return _list('''
      query {
        Page(perPage: 25) {
          media(search: "$escaped", $_mangaOnly) { $_summaryFields }
        }
      }
    ''');
  }

  Future<List<MangaSummary>> _list(String query) async {
    final data = await _anilist.fetchQuery(
      query,
      RequestType.media,
      cacheDuration: const Duration(hours: 6),
    );
    if (data is! List) return const <MangaSummary>[];
    return data
        .whereType<Map>()
        .map((item) => _toSummary(Map<String, dynamic>.from(item)))
        .toList();
  }

  static MangaSummary _toSummary(Map<String, dynamic> item) {
    final titles = item['title'];
    final cover = item['coverImage'];
    final score = item['averageScore'];
    final chapters = item['chapters'];
    final genres = item['genres'];

    return MangaSummary(
      id: item['id'].toString(),
      title: _title(titles),
      cover: cover is Map
          ? (cover['extraLarge'] ?? cover['large'])?.toString()
          : null,
      rating: score is int ? score / 10 : null,
      format: item['format']?.toString(),
      status: item['status']?.toString(),
      totalChapters: chapters is int ? chapters : null,
      genres: genres is List ? genres.whereType<String>().toList() : const [],
    );
  }

  /// AniList's title is a triple of nullable strings; english leads.
  static String _title(Object? titles) {
    if (titles is! Map) return 'Unknown';
    for (final key in const ['english', 'romaji', 'native']) {
      final value = titles[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return 'Unknown';
  }

  /// Every non-empty title in AniList's triple, in english/romaji/native order,
  /// skipping the first [skip] entries.
  ///
  /// English leads, so a caller that already has the primary title from
  /// [_title] passes 1 to get the rest. The details page carries these because
  /// a manga extension matches AniList's title against its own catalogue, and
  /// different sources key on different ones -- MangaDex indexes manhwa by
  /// their native title as often as by the English one.
  static List<String> _titleTriple(Object? titles, int skip) {
    if (titles is! Map) return const <String>[];
    final found = <String>[];
    for (final key in const ['english', 'romaji', 'native']) {
      final value = titles[key];
      if (value is String && value.trim().isNotEmpty) found.add(value);
    }
    if (skip <= 0) return List<String>.unmodifiable(found);
    return List<String>.unmodifiable(found.skip(skip));
  }

  static String? _nativeTitle(Object? titles) {
    if (titles is! Map) return null;
    final value = titles['native'];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  @override
  Future<MangaDetails> getDetails(String id) async {
    final mediaId = int.tryParse(id);
    if (mediaId == null) {
      throw AnilistApiException('Not an AniList media id: $id');
    }

    final query = '''
      query {
        Page(perPage: 1) {
          media(id: $mediaId, type: MANGA) {
            $_summaryFields
            description
            bannerImage
            volumes
            startDate { day month year }
            endDate { day month year }
            mediaListEntry { id status progress }
            staff(perPage: 8, sort: [RELEVANCE, ID]) {
              edges { role node { name { full } } }
            }
            characters(perPage: 12, sort: [ROLE, RELEVANCE, ID]) {
              edges { role node { name { full } image { large } } }
            }
            relations {
              edges {
                relationType
                node {
                  id
                  type
                  title { english romaji native }
                  coverImage { large }
                }
              }
            }
          }
        }
      }
    ''';

    final String? token = await getSecureVal(SecureStorageKey.anilistToken);
    final data = await _anilist.fetchQuery(
      query,
      RequestType.media,
      token: token,
      cacheDuration: const Duration(hours: 12),
    );
    if (data is! List || data.isEmpty) {
      throw AnilistApiException('No manga found for AniList id $mediaId');
    }

    final info = Map<String, dynamic>.from(data[0] as Map);

    final authors = <String>[];
    final staff = info['staff'];
    if (staff is Map && staff['edges'] is List) {
      for (final edge in (staff['edges'] as List).whereType<Map>()) {
        final node = edge['node'];
        final name = node is Map ? node['name'] : null;
        final full = name is Map ? name['full'] : null;
        if (full is String && full.isNotEmpty) {
          final role = edge['role']?.toString();
          authors.add(role == null || role.isEmpty ? full : '$full ($role)');
        }
      }
    }

    final characters = <MangaCharacter>[];
    final charData = info['characters'];
    if (charData is Map && charData['edges'] is List) {
      for (final edge in (charData['edges'] as List).whereType<Map>()) {
        final node = edge['node'];
        if (node is! Map) continue;
        final name = node['name'];
        final image = node['image'];
        final full = name is Map ? name['full'] : null;
        if (full is! String) continue;
        characters.add(
          MangaCharacter(
            name: full,
            role: edge['role']?.toString(),
            image: image is Map ? image['large']?.toString() : null,
          ),
        );
      }
    }

    final relations = <MangaRelation>[];
    final relationData = info['relations'];
    if (relationData is Map && relationData['edges'] is List) {
      for (final edge in (relationData['edges'] as List).whereType<Map>()) {
        final node = edge['node'];
        if (node is! Map) continue;
        final cover = node['coverImage'];
        relations.add(
          MangaRelation(
            id: node['id'].toString(),
            title: _title(node['title']),
            cover: cover is Map ? cover['large']?.toString() : null,
            type: node['type']?.toString(),
            relationType: edge['relationType']?.toString(),
          ),
        );
      }
    }

    final mediaListEntry = info['mediaListEntry'];
    final volumes = info['volumes'];
    final description = info['description'];
    final banner = info['bannerImage'];

    return MangaDetails(
      summary: _toSummary(info),
      // Descriptions arrive as HTML; the anime details page strips tags the same
      // way rather than asking AniList for asHtml: false.
      synopsis: description is String
          ? description
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .replaceAll(RegExp(r'\n+'), '\n')
              .trim()
          : null,
      banner: banner is String ? banner : null,
      authors: authors,
      characters: characters,
      relations: relations,
      volumes: volumes is int ? volumes : null,
      startDate: _formatDate(info['startDate']),
      endDate: _formatDate(info['endDate']),
      // The summary keeps one title for card display; the details page needs
      // every title AniList knows, because the manga extension on the other
      // side matches against whichever one its own catalogue uses.
      alternateTitles: _titleTriple(info['title'], 1),
      nativeTitle: _nativeTitle(info['title']),
      mediaListStatus:
          mediaListEntry is Map ? mediaListEntry['status']?.toString() : null,
      listId: mediaListEntry is Map && mediaListEntry['id'] is int
          ? mediaListEntry['id'] as int
          : null,
    );
  }

  /// AniList dates are partial: any of day/month/year can be null.
  static String? _formatDate(Object? raw) {
    if (raw is! Map) return null;
    final day = raw['day'];
    final month = raw['month'];
    final year = raw['year'];
    if (day == null && month == null && year == null) return null;
    // Kept out of the ternary on purpose: `cond ? f()?['k'] : null` does not
    // parse, because the `?[` after the then-branch reads as a second `?`.
    final Map<String, String>? months =
        month is int ? MonthnumberToMonthName(month) : null;
    final monthName = months?['short'];
    return [day ?? '', monthName ?? '', year ?? '']
        .where((part) => part.toString().trim().isNotEmpty)
        .join(' ');
  }
}