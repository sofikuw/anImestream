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
  /// Android writes into the public Download tree, matching where episodes
  /// already go, so chapters are visible in any file manager instead of being
  /// buried in private app storage nobody can browse. A user-configured
  /// download path wins, the same preference the anime downloader honours.
  /// iOS has no shared Downloads tree, so chapters stay in the documents
  /// directory there.
  static Future<Directory> _mangaRoot() async {
    if (Platform.isAndroid) {
      final configured = currentUserSettings?.downloadPath;
      final base = (configured != null && configured.trim().isNotEmpty)
          ? configured
          : '/storage/emulated/0/Download/animestream';
      final root = Directory(
        '${base.replaceAll(RegExp(r'[/\\]+$'), '')}/manga',
      );
      if (!await root.exists()) await root.create(recursive: true);
      return root;
    }
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory('${documents.path}/manga');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  /// Where one chapter lives. Ids are sanitised: they come from an extension and
  /// a `/` in one would escape the tree this class owns.
  static Future<Directory> chapterDirectory(
    String mangaId,
    MangaChapter chapter,
  ) async {
    final root = await _mangaRoot();
    return Directory(
      '${root.path}/${_safe(mangaId)}/${_safe(chapter.id)}',
    );
  }

  /// Strips anything that is not safe as a path segment.
  static String _safe(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Whether this chapter is fully downloaded.
  ///
  /// The manifest is the completion marker: it is written only after every page
  /// has landed, so its presence means complete and its absence means "not
  /// usable", whatever files are lying around.
  static Future<bool> isDownloaded(String mangaId, MangaChapter chapter) async {
    try {
      final dir = await chapterDirectory(mangaId, chapter);
      final manifest = File('${dir.path}/$kManifestName');
      return await manifest.exists();
    } catch (err) {
      Logs.app.log('$err while checking whether a chapter is downloaded');
      return false;
    }
  }

  /// Downloads every page of [chapter], reporting progress as it goes.
  ///
  /// Returns true when the chapter is complete on disk. Never throws: a failed
  /// download leaves no manifest, so the chapter simply stays not-downloaded and
  /// the UI can offer it again.
  static Future<bool> download({
    required String mangaId,
    required String mangaTitle,
    required MangaChapter chapter,
    required MangaChapterProvider provider,
  }) async {
    final key = keyFor(mangaId, chapter);

    // The public Download tree needs storage access on Android; the same gate
    // the episode downloader uses, so both features ask exactly once and share
    // one grant. A refusal fails cleanly: no manifest gets written, so the
    // chapter just stays not-downloaded and is safe to retry.
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

    // Idempotent under concurrency rather than racing: the second caller waits
    // on the first rather than starting a parallel fetch of the same pages.
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

      final dir = await chapterDirectory(mangaId, chapter);
      // A retry starts clean: leftovers from a failed attempt would otherwise be
      // counted as progress and could collide with a different page order.
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

      // Last, and only now: this file IS the completion marker.
      await File('${dir.path}/$kManifestName').writeAsString(
        jsonEncode({
          'mangaId': mangaId,
          'mangaTitle': mangaTitle,
          'chapterId': chapter.id,
          'chapterNumber': chapter.number,
          'chapterTitle': chapter.title,
          'scanlator': chapter.scanlator,
          'pages': pages.length,
          // The host may require a Referer to serve its images. Kept so an
          // offline read sends the same headers the download did.
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
      // Cleared here, in `finally`, so the in-flight guard cannot be left set by
      // an early return and wedge this chapter forever.
      _inFlight.remove(key);
    }
  }

  /// One page. `followRedirects` is left on, unlike in the extension sandbox:
  /// CDNs routinely answer with a redirect to a signed URL, and this client is
  /// the app's own, so there is no sandbox rule to respect.
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

      // Index-prefixed and zero-padded, so a directory listing is reading order
      // even before the manifest is parsed.
      final name = page.index.toString().padLeft(3, '0');
      final file = File('${dir.path}/$name');
      await response.pipe(file.openWrite());
      return true;
    } catch (err) {
      Logs.app.log('$err while downloading a manga page');
      return false;
    }
  }

  /// The pages of a downloaded chapter, as [MangaPage]s the reader already
  /// understands -- so the reader needs no second code path, only a different
  /// source for its list.
  ///
  /// Returns an empty list when the chapter is not downloaded or unreadable.
  static Future<List<MangaPage>> localPages(
    String mangaId,
    MangaChapter chapter,
  ) async {
    try {
      final dir = await chapterDirectory(mangaId, chapter);
      final manifest = File('${dir.path}/$kManifestName');
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
        final file = File('${dir.path}/$name');
        if (!await file.exists()) {
          // A manifest with a missing page means a partly-deleted download.
          // Reported rather than silently served short: a chapter that renders
          // half its pages looks like a reader bug.
          Logs.app.log('Downloaded chapter is missing page $index');
          return const <MangaPage>[];
        }
        // `file://` so the same Image path works for disk and network.
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
  static Future<void> delete(String mangaId, MangaChapter chapter) async {
    try {
      final dir = await chapterDirectory(mangaId, chapter);
      if (await dir.exists()) await dir.delete(recursive: true);
      final key = keyFor(mangaId, chapter);
      _inFlight.remove(key);
      _set(key, ChapterDownload(key: key, state: DownloadState.absent));
    } catch (err) {
      Logs.app.log('$err while deleting a downloaded chapter');
    }
  }

  /// Bytes on disk for one manga, for a storage line in the UI. Sums what is
  /// there rather than tracking a running total, so it cannot drift from the
  /// filesystem.
  static Future<int> usedBytes(String mangaId) async {
    try {
      final root = await _mangaRoot();
      final dir = Directory('${root.path}/${_safe(mangaId)}');
      if (!await dir.exists()) return 0;

      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
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