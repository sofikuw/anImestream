// MangaPill as an inbuilt (Dart) manga chapter source.
//
// Ported from `providers/mangapill.js` in anImestream-extensions:
//
//   1. Search   -- GET /search?q=<title>; hits link to /manga/<id>/<slug> and
//      the slug is the title slugified, so candidates are scored on the slug.
//   2. Chapters -- the manga page links to /chapters/<mangaId>-<n>/<slug> with
//      labels like "Chapter 364.2".
//   3. Pages    -- the chapter page lazy-loads images into `data-src` on a CDN
//      that wants the chapter page as Referer.

import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/providers/inbuiltMangaCommon.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/network/network.dart';
import 'package:html/parser.dart';

class MangaPillMangaProvider implements MangaChapterProvider {
  static const String _base = 'https://mangapill.com';

  @override
  String get providerName => 'MangaPill';

  @override
  String get providerId => 'mangapill_inbuilt';

  @override
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    final title = manga.title.trim();
    if (title.isEmpty) return const <MangaChapter>[];

    final searchUrl = Uri.parse('$_base/search').replace(
      queryParameters: <String, String>{'q': title},
    );
    final candidate = pickBestMangaMatch<_MangaPillSeries>(
      _seriesFromHtml(await _body(searchUrl.toString())),
      title,
      slugOf: (series) => series.slug,
      nameOf: (series) => series.slug,
    );
    if (candidate == null) return const <MangaChapter>[];

    final chapters = _chaptersFromHtml(await _body(candidate.url));
    sortChaptersByNumber(chapters, (chapter) => chapter.number);
    return chapters;
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final raw = chapter.id.trim();
    if (raw.isEmpty) return const <MangaPage>[];
    final chapterUrl = raw.startsWith('http') ? raw : '$_base$raw';

    return _pagesFromHtml(await _body(chapterUrl, referer: chapterUrl), chapterUrl);
  }

  @override
  Future<void> dispose() async {}

  Future<String> _body(String url, {String? referer}) async {
    final res = await get(
      Uri.parse(url),
      headers: <String, String>{
        if (referer != null) 'Referer': referer,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
      },
      cacheDuration: const Duration(minutes: 10),
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('MangaPill: HTTP ${res.statusCode} for $url');
    }
    return res.body;
  }

  List<_MangaPillSeries> _seriesFromHtml(String html) {
    final document = parse(html);
    final series = <_MangaPillSeries>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = resolvedHref(anchor, _base);
      if (href == null) continue;
      final segments = pathSegments(Uri.parse(href).path);
      if (segments.length < 3 || segments.first != 'manga') continue;
      if (!RegExp(r'^[0-9]+$').hasMatch(segments[1])) continue;
      if (!seen.add(href)) continue;

      series.add(_MangaPillSeries(url: href, slug: segments.last));
    }
    return series;
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

      final label = collapseWhitespace(anchor.text);
      if (label.isEmpty) continue;
      if (!seen.add(href)) continue;

      chapters.add(
        MangaChapter(
          id: href,
          title: _chapterTitle(label),
          number: chapterNumberFromLabel(label) ??
              chapterNumberFromPath(Uri.parse(href).path),
          scanlator: providerName,
        ),
      );
    }
    return chapters;
  }

  static String? _chapterTitle(String label) {
    final cleaned = collapseWhitespace(
      label.replaceFirst(RegExp(r'^chapter\s*[0-9.\-]*\s*[:\-\u2013]?\s*', caseSensitive: false), ''),
    );
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
      if (!RegExp(r'\.(?:jpg|jpeg|png|webp|gif)(?:\?|$)', caseSensitive: false).hasMatch(url)) {
        continue;
      }
      if (!seen.add(url)) continue;

      pages.add(MangaPage(index: pages.length, imageUrl: url, headers: headers));
    }
    return pages;
  }
}

class _MangaPillSeries {
  final String url;
  final String slug;

  _MangaPillSeries({required this.url, required this.slug});
}
