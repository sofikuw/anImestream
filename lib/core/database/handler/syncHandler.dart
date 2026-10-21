import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/database/anilist/mutations.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/core/database/mal/mutations.dart';
import 'package:animestream/core/database/simkl/mutations.dart';
import 'package:animestream/core/database/types.dart';

class SyncHandler extends DatabaseMutation {
  @override
  Future<DatabaseMutationResult?> mutateAnimeList({
    required int id,
    List<AlternateDatabaseId>? otherIds,
    MediaStatus? status,
    MediaStatus? previousStatus,
    int? progress,
  }) async {
    // Negative ids are app-local metadata fallback ids, not AniList media ids.
    // Refuse them here as a last line of defence so no UI path can write one to
    // a remote list.
    if (id < 0) return null;

    final List<Databases> databases = Databases.values;
    final activedb = getActiveDatabase();
    final activeDbInstance = getDatabaseMutationInstance(activedb);

    //sync with the active database first
    activeDbInstance
        .mutateAnimeList(id: id, status: status, previousStatus: previousStatus, progress: progress)
        .then((val) => print("[SYNC HANDLER]: Synced ${activedb.name}"))
        .catchError((e, st) {
      print(e);
      print(st.toString());
      return null;
    });

    //sync with other databases
    otherIds?.forEach((it) {
      if (it.database != activedb) {
        final altdb = databases.where((db) => db == it.database).firstOrNull;
        if (altdb != null) {
          final mutInstance = getDatabaseMutationInstance(altdb);
          mutInstance
              .mutateAnimeList(id: it.id, status: status, previousStatus: previousStatus, progress: progress)
              .then((val) => print("[SYNC HANDLER]: Synced ${it.database.name}"))
              .catchError((e, st) {
            print(e);
            print(st.toString());
            return null;
          });
        }
      }
    });

    return null;
  }

  /// Manga reading progress, which has exactly one destination: AniList.
  ///
  /// `mutateAnimeList` above cannot be reused for this, and not because of its
  /// shape. It fans out over every database -- `Databases.values` for the active
  /// one, then each of `otherIds` -- so pointed at a manga it would post reading
  /// progress to MAL and Simkl. Neither carries manga entries, so those writes
  /// would either fail or, worse, succeed against a colliding id and corrupt an
  /// unrelated anime entry.
  ///
  /// Nothing AniList-side needs a manga variant: `SaveMediaListEntry` takes a
  /// `mediaId` and no `type`, so a manga media id is accepted as-is. What is
  /// manga-specific is only the routing, which is why this lives here rather
  /// than in `anilist/mutations.dart`.
  ///
  /// Never throws. Reading a chapter must not fail because a sync did -- the
  /// caller has already written the local row by the time this runs, and an
  /// exception escaping here would be reported as a reading error.
  Future<DatabaseMutationResult?> mutateMangaList({
    required int id,
    int? progress,
  }) async {
    final activeDb = getActiveDatabase();
    if (activeDb != Databases.anilist) {
      print(
        "[SYNC HANDLER]: manga progress is AniList-only; active database is ${activeDb.name}, not syncing",
      );
      return null;
    }

    try {
      await AnilistMutations().mutateAnimeList(id: id, progress: progress);
      print("[SYNC HANDLER]: Synced manga $id to AniList");
    } catch (e, st) {
      print("[SYNC HANDLER]: manga sync failed for $id: $e");
      print(st.toString());
    }

    return null;
  }

  @override
  Future<DatabaseMutationResult?> deleteAnimeEntry({required int id, List<AlternateDatabaseId>? otherIds}) async {
    final List<Databases> databases = Databases.values;
    final activedb = getActiveDatabase();
    final activeDbInstance = getDatabaseMutationInstance(activedb);

    //sync with the active database first
    activeDbInstance
        .deleteAnimeEntry(id: id)
        .then((val) => print("[SYNC HANDLER]: Deleted from ${activedb.name}"))
        .catchError((e, st) {
      print(e);
      print(st.toString());
      return null;
    });

    //sync with other databases
    otherIds?.forEach((it) {
      if (it.database != activedb) {
        final altdb = databases.where((db) => db == it.database).firstOrNull;
        if (altdb != null) {
          final mutInstance = getDatabaseMutationInstance(altdb);
          mutInstance
              .deleteAnimeEntry(id: it.id)
              .then((val) => print("[SYNC HANDLER]: Deleted from ${it.database.name}"))
              .catchError((e, st) {
            print(e);
            print(st.toString());
            return null;
          });
        }
      }
    });

    return null;
  }

  DatabaseMutation getDatabaseMutationInstance(Databases db) {
    switch (db) {
      case Databases.anilist:
        return AnilistMutations();
      case Databases.simkl:
        return SimklMutation();
      case Databases.mal:
        return MALMutation();
      // default:
      // throw Exception("NOT_AN_OPTION_LIL_BRO");
    }
  }

  //get the preferred/current database
  Databases getActiveDatabase() {
    return currentUserSettings?.database ?? Databases.anilist;
  }
}
