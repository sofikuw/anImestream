import 'package:hive/hive.dart';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/commons/enums/hiveEnums.dart';
import 'package:animestream/core/commons/types.dart';

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
/// signed-in user -- and since the AniList manga path does not exist yet (see
/// below), it would make it empty for everyone.
///
/// So the local row is written unconditionally, and an AniList call is
/// something this function would *add* to, not choose between.
///
/// The AniList half is not wired yet. It needs a `mutateMangaList` beside
/// `mutateAnimeList` in `core/database/handler/syncHandler.dart`, and
/// `mutateAnimeList` cannot be reused: it is anime-shaped (`id: int`) and
/// cross-posts to MAL and Simkl, neither of which should receive manga. A new
/// query is needed in `core/database/anilist/queries.dart` too, because
/// `getUserAnimeList` hard-codes `type: ANIME`.
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
  } catch (err) {
    Logs.app.log("${err.toString()} while storing reading progress");
  }
}

/// The local reading history, as Home rows.
///
/// Built as [HomePageList] with `contentType: 'manga'`, which is the whole
/// reason the Home rail needs no card work: `AnimeCardExtended` already routes
/// a mango row to the manga details page off that field.
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
