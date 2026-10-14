import 'package:hive/hive.dart';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/commons/enums/hiveEnums.dart';
import 'package:animestream/core/commons/types.dart';
import 'package:animestream/core/database/anilist/login.dart';
import 'package:animestream/core/database/handler/syncHandler.dart';

final String _boxName = HiveBox.animestream.boxName;

/// Box key holding the local reading history.
///
/// A bare string, mirroring `watching.dart`'s literal `'watching'` key rather
/// than adding a `HiveKey` entry: that enum has a `watching` member the sibling
/// file does not actually use, so following it here would invent a second
/// convention for the same box.
const String _readingKey = 'reading';

/// One row per manga, newest first.
///
/// Also the cap: the rail is a shelf, not a catalogue, which is why
/// `watching.dart` caps at 40 too.
const int _maxRows = 40;

/// Records that a chapter of a manga was opened.
///
/// **Deliberately not shaped like `watching.dart`'s `storeWatching`.** That
/// function writes to exactly one destination: AniList when signed in, Hive
/// when not. The consequence is that a signed-in user has *no* local watch
/// history. Mirrored literally, that would make this rail empty for a
/// signed-in user.
///
/// So the local row is written unconditionally, and the AniList call is
/// something this function *adds to* rather than chooses between. That ordering
/// matters: the Home rail reads the local box, so the Hive write is what makes
/// the rail work for signed-in and signed-out users alike.
///
/// The AniList half is wired: `mutateMangaList` in
/// `core/database/handler/syncHandler.dart`, which is AniList-only on purpose --
/// `mutateAnimeList` cannot be reused because it cross-posts to MAL and Simkl,
/// neither of which should receive manga.
Future<void> storeReading({
  required String id,
  required String title,
  required String? cover,
  required double? rating,
  required int? totalChapters,
  required double chapterNumber,
}) async {
  try {
    final box = await Hive.openBox(_boxName);
    final reading = List<dynamic>.from(box.get(_readingKey) ?? const <dynamic>[]);

    // Re-opening a chapter moves the title to the front rather than adding a
    // second row, which is what keeps this one row per manga.
    reading.removeWhere((item) => item is Map && item['id']?.toString() == id);
    reading.insert(0, <String, dynamic>{
      'id': id,
      'title': title,
      'cover': cover,
      'rating': rating,
      'totalChapters': totalChapters,
      'chapter': chapterNumber,
    });
    while (reading.length > _maxRows) {
      reading.removeLast();
    }

    await box.put(_readingKey, reading);
    await box.close();
    Logs.app.log("Stored reading progress for $title at chapter $chapterNumber");

    // ---------------------------------------------------------------- AniList
    //
    // Additive, and after the local write, so nothing here can cost the user
    // their local shelf.
    //
    // `id` arrives as a String because the manga details page carries it as one,
    // but AniList wants its own manga media id as an int. A provider id --
    // MangaDex's, Ragnarok's -- is not one, so it is refused here rather than
    // sent: a wrong id would write progress against a different title, which is
    // worse than not syncing at all. The refusal is logged, so a mismatch shows
    // up in the app's own log instead of looking like a sync that silently does
    // nothing.
    final mediaId = int.tryParse(id);
    if (mediaId == null) {
      Logs.app.log(
        "Not syncing reading progress to AniList: '$id' is not an AniList media id",
      );
    } else if (await AniListLogin().isAnilistLoggedIn()) {
      // AniList's `progress` is an int, and a chapter number is a double here --
      // half chapters are a real thing in manga -- so floor it. Chapter 1.5 is
      // read as far as AniList is concerned once chapter 1 is done.
      await SyncHandler().mutateMangaList(
        id: mediaId,
        progress: chapterNumber.floor(),
      );
    }
  } catch (err) {
    Logs.app.log("${err.toString()} while storing reading progress");
  }
}

/// The local reading history, as Home rows.
///
/// Built as [HomePageList] with `contentType: 'manga'`, which is the whole
/// reason the Home rail needs no card work: `AnimeCardExtended` already routes
/// a manga row to the manga details page off that field.
///
/// Never throws. A storage failure returns an empty list, so a broken Hive box
/// costs the user this one rail rather than the whole Home page.
Future<List<HomePageList>> getReadingList() async {
  final rows = <HomePageList>[];
  try {
    final box = await Hive.openBox(_boxName);
    final reading = List<dynamic>.from(box.get(_readingKey) ?? const <dynamic>[]);

    for (final item in reading) {
      if (item is! Map) continue;
      final id = item['id']?.toString();
      final title = item['title']?.toString();
      if (id == null || id.isEmpty || title == null || title.isEmpty) continue;

      final chapter = item['chapter'];
      rows.add(
        HomePageList(
          coverImage: item['cover']?.toString() ?? '',
          rating: (item['rating'] as num?)?.toDouble(),
          // One key, the same shape `watching.dart` stores: the rail only ever
          // has one title to show per row.
          title: {'title': title},
          id: id,
          // AniList's chapter *count* and the chapter you are on. Reusing the
          // episode fields is deliberate -- the row card renders them as
          // "n / total", which is exactly right for chapters.
          totalEpisodes: (item['totalChapters'] as num?)?.toInt(),
          watchedEpisodeCount: chapter is num ? chapter.floor() : null,
          contentType: 'manga',
        ),
      );
      if (rows.length >= _maxRows) break;
    }
    await box.close();
  } catch (err) {
    Logs.app.log("${err.toString()} while reading the local reading list");
  }
  return rows;
}

/// Forgets one title. The counterpart to `watching.dart`'s `removeWatching`.
Future<void> removeReading(String id) async {
  try {
    final box = await Hive.openBox(_boxName);
    final reading = List<dynamic>.from(box.get(_readingKey) ?? const <dynamic>[]);
    reading.removeWhere((item) => item is Map && item['id']?.toString() == id);
    await box.put(_readingKey, reading);
    await box.close();
  } catch (err) {
    Logs.app.log("${err.toString()} while removing from the local reading list");
  }
}
