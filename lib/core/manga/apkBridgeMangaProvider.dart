import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/network/network.dart';
import 'package:http/http.dart' as http;

/// A [MangaChapterProvider] backed by a remote ApkBridge instance.
///
/// ApkBridge (https://github.com/Schnitzel5/ApkBridge) runs Aniyomi/Tachiyomi
/// extensions on an Android device and exposes them over HTTP on port 8080.
/// Every request carries the extension APK (base64) plus the method to invoke,
/// so this provider keeps the APK bytes in memory and re-sends them per call.
class ApkBridgeMangaProvider implements MangaChapterProvider {
  ApkBridgeMangaProvider({
    required this.bridgeUrl,
    required this.sourceName,
    required this.apkBytes,
    this.sourceId,
  });

  final String bridgeUrl;
  final String sourceName;
  final Uint8List apkBytes;
  final String? sourceId;

  String get _apkBase64 => base64Encode(apkBytes);

  @override
  String get providerName => sourceName;

  @override
  String get providerId => sourceId ?? 'apkbridge_${sourceName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';

  Future<Map<String, dynamic>> _call(
    String method, {
    int page = 1,
    String? search,
    Map<String, dynamic>? mangaData,
    Map<String, dynamic>? chapterData,
  }) async {
    final uri = Uri.parse(bridgeUrl).resolve('/');
    final body = <String, dynamic>{
      'data': _apkBase64,
      'method': method,
      'page': page,
    };
    if (search != null) body['search'] = search;
    if (mangaData != null) body['mangaData'] = mangaData;
    if (chapterData != null) body['chapterData'] = chapterData;

    final res = await http.post(
      uri,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 60));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('ApkBridge: HTTP ${res.statusCode} for $method');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List) return <String, dynamic>{'items': decoded};
    return <String, dynamic>{'result': decoded};
  }

  Map<String, dynamic> _mangaToBridge(MangaDetails manga) => <String, dynamic>{
        'url': manga.summary.id,
        'title': manga.title,
        'thumbnail_url': manga.cover,
        'description': manga.synopsis,
        'author': null,
        'artist': null,
        'genre': manga.summary.genres.join(', '),
        'status': 0,
        'initialized': true,
      };

  Map<String, dynamic> _chapterToBridge(MangaChapter chapter) => <String, dynamic>{
        'url': chapter.id,
        'name': chapter.title ?? '',
        'chapter_number': chapter.number ?? 0,
        'scanlator': chapter.scanlator,
        'date_upload': 0,
      };

  @override
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    // Resolve the title against the extension first.
    final searchRes = await _call('getSearchManga', page: 1, search: manga.title);
    final mangas = _extractMangas(searchRes);
    if (mangas.isEmpty) return const <MangaChapter>[];

    // Pick the best match by normalised title.
    final wanted = _normalise(manga.title);
    Map<String, dynamic>? best;
    for (final m in mangas) {
      if (_normalise(m['title']?.toString() ?? '') == wanted) {
        best = m;
        break;
      }
    }
    best ??= mangas.first;

    final bridgeManga = Map<String, dynamic>.from(best);
    final chapRes = await _call('getChapterList', mangaData: bridgeManga);
    final chapters = _extractChapters(chapRes);
    final result = <MangaChapter>[];
    for (final c in chapters) {
      result.add(MangaChapter(
        id: (c['url'] ?? c['id'] ?? '').toString(),
        title: c['name']?.toString(),
        number: (c['chapter_number'] is num)
            ? (c['chapter_number'] as num).toDouble()
            : double.tryParse(c['chapter_number']?.toString() ?? ''),
        scanlator: c['scanlator']?.toString(),
      ));
    }
    return result;
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final bridgeChapter = _chapterToBridge(chapter);
    final res = await _call('getPageList', chapterData: bridgeChapter);
    final pages = _extractPages(res);
    final result = <MangaPage>[];
    for (var i = 0; i < pages.length; i++) {
      final p = pages[i];
      final url = (p['imageUrl'] ?? p['image_url'] ?? p['url'] ?? '').toString();
      if (url.isEmpty) continue;
      Map<String, String>? headers;
      final rawHeaders = p['headers'];
      if (rawHeaders is Map) {
        headers = <String, String>{};
        for (final e in rawHeaders.entries) {
          headers[e.key.toString()] = e.value.toString();
        }
      }
      result.add(MangaPage(
        index: p['index'] is int ? p['index'] as int : i,
        imageUrl: url,
        headers: headers,
      ));
    }
    return result;
  }

  @override
  Future<void> dispose() async {}

  List<Map<String, dynamic>> _extractMangas(Map<String, dynamic> res) {
    final out = <Map<String, dynamic>>[];
    for (final key in const ['mangas', 'items', 'results', 'data']) {
      final v = res[key];
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
        if (out.isNotEmpty) return out;
      }
    }
    // MangasPage may be nested under 'result'.
    final r = res['result'];
    if (r is Map) return _extractMangas(Map<String, dynamic>.from(r));
    if (r is List) {
      for (final e in r) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _extractChapters(Map<String, dynamic> res) {
    final out = <Map<String, dynamic>>[];
    for (final key in const ['chapters', 'items', 'results', 'data']) {
      final v = res[key];
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
        if (out.isNotEmpty) return out;
      }
    }
    final r = res['result'];
    if (r is Map) return _extractChapters(Map<String, dynamic>.from(r));
    if (r is List) {
      for (final e in r) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _extractPages(Map<String, dynamic> res) {
    final out = <Map<String, dynamic>>[];
    for (final key in const ['pages', 'images', 'items', 'results', 'data']) {
      final v = res[key];
      if (v is List) {
        for (final e in v) {
          if (e is Map) out.add(Map<String, dynamic>.from(e));
        }
        if (out.isNotEmpty) return out;
      }
    }
    final r = res['result'];
    if (r is Map) return _extractPages(Map<String, dynamic>.from(r));
    if (r is List) {
      for (final e in r) {
        if (e is Map) out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  String _normalise(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
