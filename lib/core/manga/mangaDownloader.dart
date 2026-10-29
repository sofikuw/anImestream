import 'dart:convert';
import 'dart:io';

import 'package:animestream/core/anime/downloader/downloaderHelper.dart';
import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Per-chapter manga downloads.
///
/// A manga chapter is not one file. It is N images, fetched from a CDN the
/// extension names but the app retrieves itself -- so this is a directory of
/// pages plus a manifest, not a single download the way an episode is.
///
/// ```
/// /storage/emulated/0/Download/animestream/manga/<mangaId>/<chapterId>/
///     manifest.json      title, chapter number, page count, headers
///     000.jpg 001.jpg …  one file per page, index-prefixed so directory
///                        order is reading order
/// ```
///
/// **Why one directory per chapter rather than per manga.** A directory listing
/// is the state: a half-finished chapter is a directory with fewer files than its
/// manifest says, or no manifest at all, and that is detectable without a second
/// bookkeeping store to keep in step. The manifest is written LAST for the same
/// reason -- its presence is the completion marker, so a download killed halfway
/// leaves no manifest and is correctly treated as absent.
///
/// **Why pages are fetched here and not through the extension's `api.request`.**
/// Page images live on CDNs outside the provider's `allowedHosts`, and the
/// sandbox refuses redirects and caps responses at 1 MiB. The provider supplies
/// the URLs (and any headers the host requires); the app does the fetching, the
/// same way the player opens a stream URL the provider handed over.
///
/// **Disk is preferred when present.** The reader asks this class first, so a
/// downloaded chapter is read from disk even when online. That is the requested
/// behaviour and it is worth naming the consequence: a download that goes stale
/// wins over a fresher online copy until the user deletes it.
class MangaDownloader {
  /// Serialised with the library: two taps on the same chapter must not race.
  static final Map<String, ChapterDownload> _inFlight = {};

  /// Every download in this session, keyed by a stable chapter key.
  static final ValueNotifier<Map<String, ChapterDownload>> progress =
      ValueNotifier(const <String, ChapterDownload>{});

  /// Identifies one chapter across restarts.
  ///
  /// Built from the manga id and the *chapter's own id*, not its number: a
  /// numbered chapter can be re-listed by a source with a different id, and two
  /// sources can both call something "chapter 12".
  static String keyFor(String mangaId, MangaChapter chapter) =>
      '$mangaId::${chapter.id}';

  /// Where downloaded manga lives.
  ///
  /// Android writes into the public Download tree using the titles and IDs,
  /// matching where episodes already go, so chapters are visible and human-readable
  /// in any file manager. A user-configured download path wins.
  /// iOS has no shared Downloads tree, so chapters stay in the documents
  /// directory there.
  static Future<Directory> _mangaRoot(
    String mangaId,
    String mangaTitle,
  ) async {
    if (Platform.isAndroid) {
      final configured = currentUserSettings?.downloadPath;
      final base = (configured != null && configured.trim().isNotEmpty)
          ? configured
          : '/storage/emulated/0/Download/animestream';
      // Format: <MangaTitle>_<mangaId>
      final folderName = '${_safe(mangaTitle)}_${_safe(mangaId)}';
      final root = Directory(
        '${base.replaceAll(RegExp(r'[/\\]+$'), '')}${Platform.pathSeparator}manga${Platform.pathSeparator}$folderName',
      );
      if (!await root.exists()) await root.create(recursive: true);
      return root;
    }
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory('${documents.path}/manga');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Where one chapter lives.
  static Future<Directory> chapterDirectory(
    String mangaId,
    String mangaTitle,
    MangaChapter chapter,
  ) async {
    final root = await _mangaRoot(mangaId, mangaTitle);
    // Format: <ChapterTitle>_<chapterId>
    final folderName = '${_safe(chapter.displayTitle)}_${_safe(chapter.id)}';
    return Directory(
      '${root.path}${Platform.pathSeparator}$folderName',
    );
  }

  /// Strips anything that is not safe as a path segment.
  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Whether this chapter is fully downloaded.
  static Future<bool> isDownloaded(
    String mangaId,
    String mangaTitle,
    MangaChapter chapter,
  ) async {
    try {
      final dir = await chapterDirectory(mangaId, mangaTitle, chapter);
      final manifest = File('${dir.path}/$kManifestName');
      return await manifest.exists();
    } catch (err) {
      Logs.app.log('$err while checking whether a chapter is downloaded');
      return false;
    }
  }

  /// Downloads every page of [chapter].
  static Future<bool> download({
    required String mangaId,
    required String mangaTitle,
    required MangaChapter chapter,
    required MangaChapterProvider provider,
  }) async {
    final key = keyFor(mangaId, chapter);

    if (Platform.isAndroid) {
      final granted = await DownloaderHelper().checkAndRequestPermission();
      if (!granted) {
        Logs.app.log(
          'Storage access refused; cannot download "$mangaTitle" '
          '${chapter.displayTitle}',
        );
        _set(key, ChapterDownload(key: key, state: DownloadState.failed));
        return false;
      }
    }

    final existing = _inFlight[key];
    if (existing != null) {
      while (_inFlight.containsKey(key)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return _progressFor(key)?.state == DownloadState.done;
    }

    final client = HttpClient();
    try {
      _set(key, ChapterDownload(key: key, state: DownloadState.fetchingPages));

      final pages = await provider.getPages(chapter);
      if (pages.isEmpty) {
        Logs.app.log('No pages for "$mangaTitle" ${chapter.displayTitle}');
        _set(key, ChapterDownload(key: key, state: DownloadState.failed));
        return false;
      }

      final dir = await chapterDirectory(mangaId, mangaTitle, chapter);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      var completed = 0;
      for (final page in pages) {
        final ok = await _downloadPage(client, page, dir);
        if (!ok) {
          Logs.app.log(
            'Page ${page.index} failed for "$mangaTitle" ${chapter.displayTitle}',
          );
          _set(key, ChapterDownload(key: key, state: DownloadState.failed));
          return false;
        }
        completed++;
        _set(
          key,
          ChapterDownload(
            key: key,
            state: DownloadState.downloading,
            completed: completed,
            total: pages.length,
          ),
        );
      }

      await File('${dir.path}/$kManifestName').writeAsString(
        jsonEncode({
          'mangaId': mangaId,
          'mangaTitle': mangaTitle,
          'chapterId': chapter.id,
          'chapterNumber': chapter.number,
          'chapterTitle': chapter.title,
          'scanlator': chapter.scanlator,
          'pages': pages.length,
          'headers': pages.first.headers ?? const <String, String>{},
        }),
      );

      _set(key, ChapterDownload(key: key, state: DownloadState.done));
      Logs.app.log('Downloaded "$mangaTitle" ${chapter.displayTitle}');
      return true;
    } catch (err) {
      Logs.app.log('$err while downloading a manga chapter');
      _set(key, ChapterDownload(key: key, state: DownloadState.failed));
      return false;
    } finally {
      client.close();
      _inFlight.remove(key);
    }
  }

  /// One page.
  static Future<bool> _downloadPage(
    HttpClient client,
    MangaPage page,
    Directory dir,
  ) async {
    try {
      final request = await client.getUrl(Uri.parse(page.imageUrl));
      page.headers?.forEach((name, value) => request.headers.set(name, value));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) return false;

      final name = page.index.toString().padLeft(3, '0');
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await response.pipe(file.openWrite());
      return true;
    } catch (err) {
      Logs.app.log('$err while downloading a manga page');
      return false;
    }
  }

  /// The pages of a downloaded chapter.
  static Future<List<MangaPage>> localPages(
    String mangaId,
    String mangaTitle,
    MangaChapter chapter,
  ) async {
    try {
      final dir = await chapterDirectory(mangaId, mangaTitle, chapter);
      final manifest = File('${dir.path}${Platform.pathSeparator}$kManifestName');
      if (!await manifest.exists()) return const <MangaPage>[];

      final decoded = jsonDecode(await manifest.readAsString());
      final count = decoded is Map ? decoded['pages'] as int? : null;
      if (count == null) return const <MangaPage>[];

      final headers = <String, String>{};
      final rawHeaders = decoded['headers'];
      if (rawHeaders is Map) {
        rawHeaders.forEach((name, value) {
          if (name is String && value is String) headers[name] = value;
        });
      }

      final pages = <MangaPage>[];
      for (var index = 0; index < count; index++) {
        final name = index.toString().padLeft(3, '0');
        final file = File('${dir.path}${Platform.pathSeparator}$name');
        if (!await file.exists()) {
          Logs.app.log('Downloaded chapter is missing page $index');
          return const <MangaPage>[];
        }
        pages.add(MangaPage(
          index: index,
          imageUrl: Uri.file(file.path).toString(),
          headers: headers.isEmpty ? null : headers,
        ));
      }
      return pages;
    } catch (err) {
      Logs.app.log('$err while reading a downloaded chapter');
      return const <MangaPage>[];
    }
  }

  /// Deletes one downloaded chapter.
  static Future<void> delete(
    String mangaId,
    String mangaTitle,
    MangaChapter chapter,
  ) async {
    try {
      final dir = await chapterDirectory(mangaId, mangaTitle, chapter);
      if (await dir.exists()) await dir.delete(recursive: true);
      final key = keyFor(mangaId, chapter);
      _inFlight.remove(key);
      _set(key, ChapterDownload(key: key, state: DownloadState.absent));
    } catch (err) {
      Logs.app.log('$err while deleting a downloaded chapter');
    }
  }

  /// Bytes on disk for one manga.
  static Future<int> usedBytes(String mangaId, String mangaTitle) async {
    try {
      final root = await _mangaRoot(mangaId, mangaTitle);
      if (!await root.exists()) return 0;

      var total = 0;
      await for (final entity in root.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (err) {
      Logs.app.log('$err while measuring downloaded manga');
      return 0;
    }
  }

  static ChapterDownload? _progressFor(String key) => progress.value[key];

  static void _set(String key, ChapterDownload value) {
    _inFlight[key] = value;
    progress.value = {...progress.value, key: value};
  }
}

const String kManifestName = 'manifest.json';

enum DownloadState { absent, fetchingPages, downloading, done, failed }

/// One chapter's download state. [completed] and [total] are per page, which is
/// what a progress bar needs -- a chapter is many requests, not one.
///
/// **Named `ChapterDownload`, not `DownloadProgress`.** The obvious name
/// collides with `flutter_cache_manager`'s `DownloadProgress`, which reaches
/// `mangaDetails.dart` transitively through `CachedNetworkImage` -- the same
/// import that renders the cover art. A bare `DownloadProgress` in that file is
/// then an ambiguous reference and it does not compile, which is exactly how
/// this was found.
///
/// Renaming this rather than `hide`-ing the other is deliberate: theirs is a
/// real type that file could legitimately need one day, and hiding it would
/// resurface later as a puzzling "undefined name" rather than as a collision.
@immutable
class ChapterDownload {
  final String key;
  final DownloadState state;
  final int completed;
  final int total;

  const ChapterDownload({
    required this.key,
    required this.state,
    this.completed = 0,
    this.total = 0,
  });

  double get fraction => total == 0 ? 0 : completed / total;

  bool get isBusy =>
      state == DownloadState.fetchingPages || state == DownloadState.downloading;

  @override
  bool operator ==(Object other) =>
      other is ChapterDownload &&
      other.key == key &&
      other.state == state &&
      other.completed == completed &&
      other.total == total;

  @override
  int get hashCode => Object.hash(key, state, completed, total);
}