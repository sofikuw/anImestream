import "package:hive/hive.dart";

import "package:animestream/core/app/logging.dart";
import "package:animestream/core/app/runtimeDatas.dart";
import "package:animestream/core/commons/enums/hiveEnums.dart";
import "package:animestream/core/database/anilist/login.dart";
import "package:animestream/core/database/anilist/queries.dart";
import "package:animestream/core/database/anilist/types.dart";
import "package:animestream/core/database/handler/syncHandler.dart";
import "package:animestream/core/database/types.dart";
import "package:animestream/core/commons/enums.dart";

final String _boxName = HiveBox.animestream.boxName;

Future<void> storeWatching(
  String title,
  String imageUrl,
  int id,
  int watched, {
  int? totalEpisodes,
  List<AlternateDatabaseId>? alternateDatabases,
  double? rating,
}) async {
  try {
    //add to anilist if the user is logged in
    Logs.app.log("SETTING WATCHED TO $watched");
    // Negative ids are app-local metadata fallback ids, not AniList media ids.
    // Writing one to AniList would touch the wrong entry, so keep those local.
    if (id >= 0 && await AniListLogin().isAnilistLoggedIn()) {
      SyncHandler()
          .mutateAnimeList(id: id, status: MediaStatus.CURRENT, progress: watched, otherIds: alternateDatabases);
    } else {
      var box = await Hive.openBox(_boxName);
      if (!box.isOpen) {
        box = await Hive.openBox(_boxName);
      }
      final List<dynamic> watchingList = List.castFrom(box.get('watching') ?? []);
      // final currList = watchingList.where((item) => item['id'] == id).toList();
      // if (currList.length != 0 && currList[0]['watched'] <= watched) {
      watchingList.removeWhere((item) => item['id'] == id);
      // }
      watchingList.add({
        'title': title,
        'imageUrl': imageUrl,
        'id': id,
        'watched': watched,
        'rating': rating,
        'totalEpisodes': totalEpisodes,
      });
      // print(watchingList);
      box.put('watching', watchingList);
      box.close();
    }
  } catch (err) {
    Logs.app.log(err.toString());
  }
}

Future<void> updateWatching(int? id, String title, int watched, List<AlternateDatabaseId> otherIds) async {
  try {
    Logs.app.log("UPDATING WATCHED TO $watched");
    if ((id ?? 0) >= 0 && await AniListLogin().isAnilistLoggedIn()) {
      if (id == null) throw Exception("ERR_NO_ID_PROVIDED");
      SyncHandler().mutateAnimeList(
        id: id,
        status: MediaStatus.CURRENT,
        previousStatus: MediaStatus.CURRENT,
        progress: watched,
        otherIds: otherIds,
      );
    } else {
      var box = await Hive.openBox(_boxName);
      if (!box.isOpen) {
        box = await Hive.openBox(_boxName);
      }
      final List<dynamic> watchingList = List.castFrom(box.get('watching') ?? []);
      final index = watchingList.indexWhere((item) => item['title'] == title);
      if (index != -1) {
        watchingList[index]['watched'] = watched;
      } else {
        Logs.app.log("Anime entry doesn't exists to make progress update");
      }
      box.put('watching', watchingList);
      box.close();
    }
  } catch (err) {
    Logs.app.log(err.toString());
  }
}

Future<List<UserAnimeListItem>> getWatchedList({String? userName}) async {
  final List<UserAnimeListItem> recentlyWatched = [];
  final loggedIn = await AniListLogin().isAnilistLoggedIn();
  if (loggedIn) {
    if (userName == null) throw Exception("ERR_USERNAME_IS_NULL");
    List<UserAnimeList> watchedList = await AnilistQueries().getUserAnimeList(userName, status: [MediaStatus.CURRENT]);
    if (watchedList.isNotEmpty) {
      // reversing it to get the last updated item first :)
      recentlyWatched.addAll(watchedList[0].list.reversed);
    }
  }

  // Fallback titles are never written to AniList, so their local rows must be
  // merged in even when the user is signed in. When signed out this is the
  // only list, which preserves the previous behaviour.
  final box = await Hive.openBox(_boxName);
  final List<dynamic> watching = List.castFrom(box.get('watching') ?? []);
  for (final e in watching.reversed) {
    final id = e['id'];
    if (id is! int) continue;
    if (loggedIn && id >= 0) continue;
    if (recentlyWatched.any((item) => item.id == id)) continue;
    recentlyWatched.add(UserAnimeListItem(
        id: id,
        //just give the key as title since its just one
        title: {'title': e['title']},
        coverImage: e['imageUrl'],
        watchProgress: e['watched'],
        rating: e['rating'],
        episodes: e['totalEpisodes']));
  }
  box.close();
  return recentlyWatched;
}

/// Returns the watch progress. -1 is returned if entry doesnt exist
Future<int> getAnimeWatchProgress(int id, MediaStatus? status) async {
  if (await AniListLogin().isAnilistLoggedIn() && status != null) {
    if (storedUserData == null) throw Exception("ERR_NO_USERDATA");
    final list = await AnilistQueries().getUserAnimeList(storedUserData!.name, status: [status]);
    if (list.isEmpty) {
      throw Exception("ERR_${status.name.toUpperCase()}_LIST_IS_EMPTY");
    } else {
      final item = list[0].list.where((item) => item.id == id).firstOrNull;
      return item?.watchProgress ?? -1;
    }
  } else {
    final box = await Hive.openBox(_boxName);
    final List<dynamic> watching = List.castFrom(box.get('watching') ?? []);
    final item = watching.where((item) => item['id'] == id).firstOrNull;
    await box.close();
    if (item != null) {
      return item['watched'];
    }
  }
  return -1;
}

Future<void> removeWatching(int id) async {
  try {
  final box = await Hive.openBox(_boxName);
  final List<dynamic> watching = List.castFrom(box.get('watching') ?? []);
  watching.removeWhere((i) => i['id'] == id);
  await box.put("watching", watching);
  await box.close();
  } catch(err) {
    Logs.app.log("${err.toString()} while removing from local watching list");
  }
}
