// WeebCentral as an inbuilt (Dart) manga chapter source.
//
// Ported from `providers/weebcentral.js` in anImestream-extensions, so the
// installed JavaScript extension and this build-in behave the same:
//
//   1. Search   -- GET /search/data?text=<title> returns HTMX result cards;
//      each links to /series/<ULID>/<Slug>.
//   2. Chapters -- GET /series/<ULID>/full-chapter-list returns every chapter
//      as an anchor to /chapters/<ULID>.
//   3. Pages    -- GET /chapters/<ULID>/images?reading_style=long_strip
//      returns one <img> per page, on a CDN that wants the chapter as Referer.

import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/providers/inbuiltMangaCommon.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/network/network.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';

class WeebCentralMangaProvider implements MangaChapterProvider {
  static const String _base = 'https://weebcentral.com';

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
    'Accept': 'text/html, */*',
    'HX-Request': 'true',
  };

  @override
  String get providerName => 'WeebCentral';

  @override
  String get providerId => 'weebcentral_inbuilt';

  @override
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    final title = manga.title.trim();
    if (title.isEmpty) return const <MangaChapter>[];

    final searchUrl = Uri.parse('$_base/search/data').replace(
      queryParameters: <String, String>{
        'limit': '32',
        'offset': '0',
        'text': title,
        'sort': 'Best Match',
        'order': 'Descending',
        'official': 'Any',
        'anime': 'Any',
        'adult': 'Any',
        'display_mode': 'Minimal Display',
      },
    );
    final series = pickBestMangaMatch<_WeebCentralSeries>(
      _seriesFromHtml(await _body(searchUrl.toString())),
      title,
      slugOf: (series) => series.slug,
      nameOf: (series) => series.name,
    );
    if (series == null) return const <MangaChapter>[];

    final chapterHtml = await _body('$_base/series/${series.id}/full-chapter-list');
    final chapters = _chaptersFromHtml(chapterHtml);
    sortChaptersByNumber(chapters, (chapter) => chapter.number);
    return chapters;
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final raw = chapter.id.trim();
    if (raw.isEmpty) return const <MangaPage>[];
    final chapterUrl = raw.startsWith('http') ? raw : '$_base$raw';

    final html = await _body(
      '$chapterUrl/images?is_prev=False&current_page=1&reading_style=long_strip',
      referer: chapterUrl,
    );
    return _pagesFromHtml(html, chapterUrl);
  }

  @override
  Future<void> dispose() async {}

  Future<String> _body(String url, {String? referer}) async {
    final res = await get(
      Uri.parse(url),
      headers: <String, String>{
        ..._headers,
        'Referer': referer ?? '$_base/',
      },
      cacheDuration: const Duration(minutes: 10),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('WeebCentral: HTTP ${res.statusCode} for $url');
    }
    return res.body;
  }

  List<_WeebCentralSeries> _seriesFromHtml(String html) {
    final document = parse(html);
    final order = <String>[];
    final byId = <String, _WeebCentralSeries>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = resolvedHref(anchor, _base);
      if (href == null) continue;
      final segments = pathSegments(Uri.parse(href).path);
      if (segments.length < 3 || segments.first != 'series') continue;

      final id = segments[1];
      if (!RegExp(r'^[0-9A-Za-z]{20,32}$').hasMatch(id)) continue;

      final slug = Uri.decodeComponent(segments[2]).replaceAll('-', ' ');
      final label = collapseWhitespace(anchor.text);

      final existing = byId[id];
      if (existing == null) {
        byId[id] = _WeebCentralSeries(
          id: id,
          slug: slug,
          name: label.isEmpty ? slug : label,
        );
        order.add(id);
      } else if (label.isNotEmpty && existing.name == existing.slug) {
        byId[id] = _WeebCentralSeries(id: existing.id, slug: existing.slug, name: label);
      }
    }

    return order.map((id) => byId[id]!).toList(growable: false);
  }

  List<MangaChapter> _chaptersFromHtml(String html) {
    final document = parse(html);
    final chapters = <MangaChapter>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = resolvedHref(anchor, _base);
      if (href == null) continue;
      final segments = pathSegments(Uri.parse(href).path);
      if (segments.length < 2 || segments.first != 'chapters') continue;
      if (!seen.add(href)) continue;

      final label = collapseWhitespace(anchor.text);
      final number = chapterNumberFromLabel(label);
      chapters.add(
        MangaChapter(
          id: href,
          // "Chapter 12" already renders through [MangaChapter.displayTitle];
          // a title here would repeat it.
          title: number == null ? _cleanChapterTitle(label) : null,
          number: number,
          scanlator: providerName,
        ),
      );
    }
    return chapters;
  }

  static String? _cleanChapterTitle(String label) {
    // Trailing release dates ("2024-01-02 ...") are metadata, not the name.
    final cleaned = collapseWhitespace(label.replaceAll(RegExp(r'\d{4}-\d{2}-\d{2}.*$'), ''));
    return cleaned.isEmpty ? null : cleaned;
  }

  List<MangaPage> _pagesFromHtml(String html, String chapterUrl) {
    final document = parse(html);
    final pages = <MangaPage>[];
    final seen = <String>{};
    final headers = <String, String>{'Referer': chapterUrl};

    for (final image in document.querySelectorAll('img')) {
      final raw = (image.attributes['data-src'] ?? image.attributes['src'])?.trim();
      if (raw == null || raw.isEmpty) continue;

      var url = raw.startsWith('//') ? 'https:$raw' : raw;
      if (!url.startsWith('http')) continue;
      if (!RegExp(r'\.(?:jpg|jpeg|png|webp|avif|gif)(?:\?|$)', caseSensitive: false).hasMatch(url)) {
        continue;
      }
      // Brand and layout assets live on the same host as page images.
      if (RegExp(r'/static/|brand|logo|avatar', caseSensitive: false).hasMatch(url)) continue;
      if (!seen.add(url)) continue;

      pages.add(MangaPage(index: pages.length, imageUrl: url, headers: headers));
    }
    return pages;
  }
}

class _WeebCentralSeries {
  final String id;
  final String slug;
  final String name;

  _WeebCentralSeries({required this.id, required this.slug, required this.name});
}
