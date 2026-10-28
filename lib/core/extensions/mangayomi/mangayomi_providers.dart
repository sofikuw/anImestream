import 'package:animestream/core/anime/providers/animeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/types.dart';
import 'package:animestream/core/extensions/mangayomi/mangayomi_runtime.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';

/// Adapts a MangaYomi *anime* extension to [AnimeProvider].
///
/// MangaYomi sources are URL-driven: `search(query, page, filters)` returns
/// `{list: [{name, link, imageUrl}], hasNextPage}`, `getDetail(url)` returns
/// episodes, and `getVideoList(url)` returns playable URLs. Those map directly
/// onto the app's provider contract.
class MangayomiAnimeProvider implements AnimeProvider {
  MangayomiAnimeProvider(this.details);

  final ProviderDetails details;
  MangayomiRuntime? _runtime;
  Future<void>? _loadFuture;
  bool _failed = false;

  @override
  String get providerName => details.name;

  bool get isUsable => !_failed && (_runtime?.isUsable ?? true);

  Future<MangayomiRuntime> _ensure() async {
    _loadFuture ??= () async {
      try {
        _runtime = await MangayomiRuntime.create(details);
      } catch (_) {
        _failed = true;
        rethrow;
      }
    }();
    await _loadFuture;
    return _runtime!;
  }

  @override
  Future<List<Map<String, String?>>> search(String query) async {
    final runtime = await _ensure();
    final result = await runtime.invoke(
      'search',
      <Object?>[query, 1, const <Object?>[]],
    );
    final items = _resultList(result);
    return items
        .map((item) {
          final name = '${item['name'] ?? ''}'.trim();
          final link = '${item['link'] ?? ''}'.trim();
          if (name.isEmpty || link.isEmpty) return null;
          return <String, String?>{
            'name': name,
            'alias': link,
            'imageUrl': _stringOrNull(item['imageUrl']),
          };
        })
        .whereType<Map<String, String?>>()
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getAnimeEpisodeLink(
    String aliasId, {
    bool dub = false,
  }) async {
    final runtime = await _ensure();
    final detail = await runtime.invoke('getDetail', <Object?>[aliasId]);
    final episodes = _episodeList(detail);
    final results = <Map<String, dynamic>>[];
    for (var index = 0; index < episodes.length; index++) {
      final episode = episodes[index];
      final link = '${episode['url'] ?? ''}'.trim();
      if (link.isEmpty) continue;
      final title = _stringOrNull(episode['name']);
      results.add(
        EpisodeDetails(
          episodeLink: link,
          episodeNumber: _episodeNumber(title, index),
          episodeTitle: title,
          description: _stringOrNull(episode['description']),
          thumbnail: _stringOrNull(episode['thumbnailUrl']),
          hasDub: false,
          isFiller: episode['isFiller'] == true,
          metadata: aliasId,
        ).toMap(),
      );
    }
    return results;
  }

  @override
  Future<void> getStreams(
    String episodeId,
    Function(List<VideoStream>, bool) update, {
    bool dub = false,
    String? metadata,
  }) async {
    update(await _streams(episodeId), true);
  }

  @override
  Future<void> getDownloadSources(
    String episodeUrl,
    Function(List<VideoStream>, bool) update, {
    bool dub = false,
    String? metadata,
  }) async {
    update(await _streams(episodeUrl), true);
  }

  Future<List<VideoStream>> _streams(String url) async {
    final runtime = await _ensure();
    final result = await runtime.invoke('getVideoList', <Object?>[url]);
    final videos = result is List ? result : const <dynamic>[];
    final streams = <VideoStream>[];
    for (final raw in videos) {
      if (raw is! Map) continue;
      final videoUrl = '${raw['url'] ?? ''}'.trim();
      if (videoUrl.isEmpty) continue;
      final headers = raw['headers'] is Map
          ? (raw['headers'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            )
          : null;
      streams.add(
        VideoStream(
          quality: _stringOrNull(raw['quality']) ?? 'auto',
          url: videoUrl,
          server: 'MangaYomi',
          backup: false,
          customHeaders: headers,
        ),
      );
    }
    if (streams.any((stream) => stream.customHeaders == null)) {
      final defaults = await _headersFor(url);
      if (defaults != null) {
        return streams
            .map(
              (stream) => stream.customHeaders != null
                  ? stream
                  : VideoStream(
                      quality: stream.quality,
                      url: stream.url,
                      server: stream.server,
                      backup: stream.backup,
                      subtitle: stream.subtitle,
                      subtitleFormat: stream.subtitleFormat,
                      customHeaders: defaults,
                    ),
            )
            .toList(growable: false);
      }
    }
    return streams;
  }

  /// Sources that need a Referer/UA for playback override `getHeaders`; the
  /// base class throws "not implemented", which is not an error here.
  Future<Map<String, String>?> _headersFor(String url) async {
    try {
      final runtime = await _ensure();
      final result = await runtime.invoke('getHeaders', <Object?>[url]);
      if (result is Map && result.isNotEmpty) {
        return result.map((key, value) => MapEntry('$key', '$value'));
      }
    } catch (_) {}
    return null;
  }

  static List<Map<dynamic, dynamic>> _resultList(Object? value) {
    if (value is Map) {
      final list = value['list'];
      if (list is List) return list.whereType<Map>().toList(growable: false);
    }
    if (value is List) return value.whereType<Map>().toList(growable: false);
    return const <Map<dynamic, dynamic>>[];
  }

  static List<Map<dynamic, dynamic>> _episodeList(Object? detail) {
    if (detail is! Map) return const <Map<dynamic, dynamic>>[];
    final episodes = detail['episodes'] ?? detail['chapters'];
    if (episodes is! List) return const <Map<dynamic, dynamic>>[];
    return episodes.whereType<Map>().toList(growable: false);
  }

  static int _episodeNumber(String? title, int index) {
    if (title != null) {
      final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
      if (match != null) {
        final parsed = double.tryParse(match.group(1)!);
        if (parsed != null) return parsed.round();
      }
    }
    return index + 1;
  }

  static String? _stringOrNull(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> dispose() async {
    await _runtime?.dispose();
    _runtime = null;
    _loadFuture = null;
  }
}

/// Adapts a MangaYomi *manga* extension to [MangaChapterProvider].
///
/// AniList supplies the title and details; this provider resolves that title
/// against the source's own catalogue, then returns chapters and page images.
/// The resolved source URL is cached per manga so opening chapters does not
/// repeat the search.
class MangayomiMangaProvider implements MangaChapterProvider {
  MangayomiMangaProvider(this.details);

  final ProviderDetails details;
  MangayomiRuntime? _runtime;
  Future<void>? _loadFuture;

  String? _resolvedMangaId;
  Map<String, dynamic>? _resolvedDetail;

  @override
  String get providerName => details.name;

  @override
  String get providerId => details.identifier;

  Future<MangayomiRuntime> _ensure() async {
    _loadFuture ??= () async {
      _runtime = await MangayomiRuntime.create(details);
    }();
    await _loadFuture;
    return _runtime!;
  }

  @override
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    final detail = await _resolve(manga);
    final rawChapters = detail['chapters'] ?? detail['episodes'];
    if (rawChapters is! List) return const <MangaChapter>[];

    final chapters = <MangaChapter>[];
    for (final raw in rawChapters) {
      if (raw is! Map) continue;
      final url = '${raw['url'] ?? ''}'.trim();
      if (url.isEmpty) continue;
      final title = _stringOrNull(raw['name']);
      chapters.add(
        MangaChapter(
          id: url,
          title: title,
          number: _chapterNumber(title),
          scanlator: _stringOrNull(raw['scanlator']),
        ),
      );
    }
    return chapters;
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final runtime = await _ensure();
    final result = await runtime.invoke('getPageList', <Object?>[chapter.id]);
    if (result is! List) return const <MangaPage>[];

    final pages = <MangaPage>[];
    for (final raw in result) {
      final url = raw is String
          ? raw.trim()
          : raw is Map
              ? '${raw['url'] ?? ''}'.trim()
              : '';
      if (url.isEmpty) continue;
      final headers = raw is Map && raw['headers'] is Map
          ? (raw['headers'] as Map).map(
              (key, value) => MapEntry('$key', '$value'),
            )
          : null;
      pages.add(
        MangaPage(index: pages.length, imageUrl: url, headers: headers),
      );
    }
    if (pages.any((page) => page.headers == null) && pages.isNotEmpty) {
      final defaults = await _headersFor(chapter.id);
      if (defaults != null) {
        return pages
            .map(
              (page) => page.headers != null
                  ? page
                  : MangaPage(
                      index: page.index,
                      imageUrl: page.imageUrl,
                      headers: defaults,
                    ),
            )
            .toList(growable: false);
      }
    }
    return pages;
  }

  Future<Map<String, String>?> _headersFor(String url) async {
    try {
      final runtime = await _ensure();
      final result = await runtime.invoke('getHeaders', <Object?>[url]);
      if (result is Map && result.isNotEmpty) {
        return result.map((key, value) => MapEntry('$key', '$value'));
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _resolve(MangaDetails manga) async {
    if (_resolvedMangaId == manga.summary.id && _resolvedDetail != null) {
      return _resolvedDetail!;
    }
    final runtime = await _ensure();
    final titles = <String>{
      manga.summary.title,
      ...manga.alternateTitles,
      if (manga.nativeTitle != null) manga.nativeTitle!,
    }.where((title) => title.trim().isNotEmpty).toList(growable: false);

    for (final title in titles) {
      final search = await runtime.invoke(
        'search',
        <Object?>[title, 1, const <Object?>[]],
      );
      final link = _bestLink(search, title);
      if (link == null) continue;
      final detail = await runtime.invoke('getDetail', <Object?>[link]);
      if (detail is! Map) continue;
      _resolvedMangaId = manga.summary.id;
      _resolvedDetail = Map<String, dynamic>.from(detail);
      return _resolvedDetail!;
    }
    _resolvedMangaId = manga.summary.id;
    _resolvedDetail = <String, dynamic>{};
    return _resolvedDetail!;
  }

  static String? _bestLink(Object? search, String wanted) {
    final list = search is Map ? search['list'] : search;
    if (list is! List) return null;
    String? first;
    for (final raw in list) {
      if (raw is! Map) continue;
      final link = '${raw['link'] ?? ''}'.trim();
      if (link.isEmpty) continue;
      first ??= link;
      final name = '${raw['name'] ?? ''}'.trim().toLowerCase();
      if (name == wanted.trim().toLowerCase()) return link;
    }
    return first;
  }

  static double? _chapterNumber(String? title) {
    if (title == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(title);
    return match == null ? null : double.tryParse(match.group(1)!);
  }

  static String? _stringOrNull(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Future<void> dispose() async {
    await _runtime?.dispose();
    _runtime = null;
    _loadFuture = null;
    _resolvedMangaId = null;
    _resolvedDetail = null;
  }
}
