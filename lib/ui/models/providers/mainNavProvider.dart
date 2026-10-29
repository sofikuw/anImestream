import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/commons/types.dart';
import 'package:animestream/core/data/reading.dart';
import 'package:animestream/core/data/watching.dart';
import 'package:animestream/core/database/anilist/anilist.dart';
import 'package:animestream/core/database/anilist/login.dart';
import 'package:animestream/core/database/anilist/queries.dart';
import 'package:animestream/core/database/anilist/types.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:animestream/ui/models/widgets/cards/animeCard.dart';
import 'package:animestream/ui/pages/mangaDetails.dart';
// material, not widgets: the manga rail card pushes a MaterialPageRoute, and
// MaterialPageRoute is declared in material.dart. widgets.dart does not export
// it, so `flutter/widgets.dart` alone fails to resolve the route.
import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class MainNavProvider extends ChangeNotifier {
  bool _isAndroid = Platform.isAndroid;
  bool get isAndroid => _isAndroid;

  bool _tv = false;
  bool get tv => _tv;
  set tv(bool value) {
    _tv = value;
    notifyListeners();
  }

  /// AniList login state
  bool _loggedIn = false;

  /// AniList login state
  bool get loggedIn => _loggedIn;

  set loggedIn(bool value) {
    _loggedIn = value;
    notifyListeners();
  }

  UserModal? _userProfile;
  UserModal? get userProfile => _userProfile;
  set userProfile(UserModal? user) {
    _userProfile = user;
    notifyListeners();
  }

  //home items

  AnimeListData<HomePageList> _currentlyAiring = AnimeListData(title: "Currently Airing");
  AnimeListData<HomePageList> _recentlyWatched = AnimeListData(title: "Continue Watching");
  AnimeListData<HomePageList> _continueReading = AnimeListData(title: "Continue Reading");
  AnimeListData<HomePageList> _plannedList = AnimeListData(title: "From Your Planned");

  // bool _homePageError = false;
  // bool _homeDataLoaded = false;

  //Discover items

  // lists
  List<TrendingResult> _trendingList = [];
  List<AnimeCard> _recommendedList = [];
  List<AnimeCard> _recentlyUpdatedList = [];
  List<AnimeCard> _thisSeason = [];

  /// Manga rails on Discover.
  ///
  /// Held as built cards, exactly like the anime rails above, because
  /// discover.dart's _scrollList takes a finished List<AnimeCard>.
  List<AnimeCard> _mangaTrendingList = [];
  List<AnimeCard> _mangaPopularList = [];

  // datas
  List<AnilistRecommendations> _recommendedListData = [];
  List<RecentlyUpdatedResult> _recentlyUpdatedListData = [];
  List<CurrentlyAiringResult> _thisSeasonData = [];

  bool _discoverDataLoaded = false;
  bool get discoverDataLoaded => _discoverDataLoaded;

  /// True when every Discover request failed. The page uses this to show an
  /// explanation and a retry action instead of leaving a spinner running
  /// forever when the metadata API is unavailable.
  bool _discoverError = false;
  bool get discoverError => _discoverError;

  // Home items
  AnimeListData<HomePageList> get currentlyAiring => _currentlyAiring;
  set currentlyAiring(AnimeListData<HomePageList> value) {
    _currentlyAiring = value;
    notifyListeners();
  }

  AnimeListData<HomePageList> get recentlyWatched => _recentlyWatched;
  set recentlyWatched(AnimeListData<HomePageList> value) {
    _recentlyWatched = value;
    notifyListeners();
  }

  /// Manga progress. Local rows, newest first.
  ///
  /// Unlike Continue Watching, this never consults AniList: it is written from
  /// the local reading store, so it works signed in or out. See
  /// `core/data/reading.dart` for why that diverges from `watching.dart`.
  AnimeListData<HomePageList> get continueReading => _continueReading;
  set continueReading(AnimeListData<HomePageList> value) {
    _continueReading = value;
    notifyListeners();
  }

  AnimeListData<HomePageList> get plannedList => _plannedList;
  set plannedList(AnimeListData<HomePageList> value) {
    _plannedList = value;
    notifyListeners();
  }

  // bool get homePageError => _homePageError;
  // set homePageError(bool value) {
  //   _homePageError = value;
  //   notifyListeners();
  // }

  // bool get homeDataLoaded => _homeDataLoaded;
  // set homeDataLoaded(bool value) {
  //   _homeDataLoaded = value;
  //   notifyListeners();
  // }

  // Discover items

  List<TrendingResult> get trendingList => _trendingList;

  List<AnimeCard> get recommendedList => _recommendedList;
  set recommendedList(List<AnimeCard> value) {
    _recommendedList = value;
    notifyListeners();
  }

  List<AnilistRecommendations> get recommendedListData => _recommendedListData;

  List<AnimeCard> get recentlyUpdatedList => _recentlyUpdatedList;
  set recentlyUpdatedList(List<AnimeCard> value) {
    _recentlyUpdatedList = value;
    notifyListeners();
  }

  List<RecentlyUpdatedResult> get recentlyUpdatedListData => _recentlyUpdatedListData;

  List<AnimeCard> get thisSeason => _thisSeason;
  set thisSeason(List<AnimeCard> value) {
    _thisSeason = value;
    notifyListeners();
  }

  List<AnimeCard> get mangaTrendingList => _mangaTrendingList;
  set mangaTrendingList(List<AnimeCard> value) {
    _mangaTrendingList = value;
    notifyListeners();
  }

  List<AnimeCard> get mangaPopularList => _mangaPopularList;
  set mangaPopularList(List<AnimeCard> value) {
    _mangaPopularList = value;
    notifyListeners();
  }

  List<CurrentlyAiringResult> get thisSeasonData => _thisSeasonData;

  // Methods

  /// check login status and get userprofile then load lists
  Future<void> init() async {
    if (!(await isConnectedToInternet())) {
      floatingSnackBar("You're offline. Connect to the internet and try again.", waitForPreviousToFinish: true);
      currentlyAiring.state = LoadingState.error;
      recentlyWatched.state = LoadingState.error;
      plannedList.state = LoadingState.error;
      return notifyListeners();
    }
    loggedIn = await AniListLogin().isAnilistLoggedIn();
    if (loggedIn) {
      AniListLogin()
          .getUserProfile()
          .then((user) => {
                _userProfile = user,
                storedUserData = user,
                Logs.app.log("[AUTHENTICATION] ${storedUserData?.name} Login Successful"),
                loadListsForHome(userName: user.name),
                // loadDiscoverItems(),
              })
          .catchError((err) async {
        if (err is AnilistApiException &&
            (err.isUnauthorized || err.message.toLowerCase().contains("invalid token"))) {
          // token is expired, invalid or has its access revoked!
          floatingSnackBar("AniList token is invalid. Login again!");

          await AniListLogin().removeToken();

          loggedIn = false;
          userProfile = null;
        } else {
          floatingSnackBar("couldnt load user profile");
        }
        loadListsForHome();

        // lets let the discover page be lazy loaded
        // loadDiscoverItems();

        //return statement so that linter would shut up!
        return <void>{};
      });
    } else {
      loadListsForHome();
      // loadDiscoverItems(); // lets let the discover page be lazy loaded
    }
  }

  /// Checks if the device is connected to internet
  Future<bool> isConnectedToInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
      return false;
    } on SocketException catch (_) {
      return false;
    }
  }

  /// Fetch the trending list from AniList, or from the configured metadata
  /// fallback when AniList is unavailable.
  Future<void> getTrendingList() async {
    final list = await Anilist().getTrending();
    // take() rather than sublist(0, 20): a fallback provider may return fewer
    // than 20 entries, and sublist would throw instead of showing what it has.
    _trendingList = list.take(20).toList(growable: false);
  }

  /// Fetch the recommended list from Anilist API
  Future<void> getRecommended() async {
    final list = await AnilistQueries().getRecommendedAnimes();
    _recommendedListData = list;
    _recommendedList.clear();
    for (final item in list) {
      final title = item.title['english'] ?? item.title['romaji'] ?? '';
      recommendedList.add(
        Cards.animeCard(
          item.id,
          (currentUserSettings?.nativeTitle ?? false) ? item.title['native'] ?? title : title,
          item.cover,
          rating: item.rating,
          isMobile: !tv && isAndroid,
        ),
      );
    }
    notifyListeners();
  }

  /// Fetch the recently updated list from Anilist API
  Future<void> getRecentlyUpdated() async {
    final list = await Anilist().recentlyUpdated();
    // Refresh replaces the rail rather than appending to it.
    _recentlyUpdatedListData.clear();
    _recentlyUpdatedList.clear();
    //to filter out the dupes
    Set<int> ids = {};
    for (final elem in list) {
      if (!ids.contains(elem.id)) {
        final title = elem.title['english'] ?? elem.title['romaji'] ?? '';
        ids.add(elem.id);
        recentlyUpdatedListData.add(elem);
        recentlyUpdatedList.add(
          Cards.animeCard(
            elem.id,
            (currentUserSettings?.nativeTitle ?? false) ? elem.title['native'] ?? title : title,
            elem.cover,
            rating: (elem.rating ?? 0) / 10,
            isMobile: !tv && isAndroid,
          ),
        );
      }
    }

    notifyListeners();
  }

  void updateWatchedList(List<HomePageList> watchedList) {
    // _recentlyWatched = watchedList;
    _recentlyWatched.items = watchedList;
    notifyListeners();
  }

  /// Reads the local reading history into [continueReading].
  ///
  /// Separate from and not part of `loadListsForHome`'s `Future.wait`, which
  /// indexes its results positionally ([0], [1], [2]); a fourth entry there
  /// would shift every existing cast. This is also the only list on Home that
  /// is read straight from local storage, so it is the only one that cannot
  /// fail on a network call.
  Future<void> loadContinueReading() async {
    try {
      _continueReading.items = await getReadingList();
      _continueReading.state = LoadingState.loaded;
    } catch (e) {
      Logs.app.log("Error loading the reading list. $e");
      // Not an error state: an empty shelf is a normal state for a new user,
      // and the rail renders "Nothing's here!" for it.
      _continueReading.items = const <HomePageList>[];
      _continueReading.state = LoadingState.loaded;
    }
    notifyListeners();
  }

  Future<void> loadListsForHome({String? userName}) async {
    // reset the error state
    currentlyAiring.state = LoadingState.loading;
    recentlyWatched.state = LoadingState.loading;
    continueReading.state = LoadingState.loading;
    plannedList.state = LoadingState.loading;

    // Local reading rows. Loaded here rather than added to the Future.wait
    // below, because that list is indexed positionally ([0], [1], [2]) and
    // inserting a fourth entry would silently shift every cast after it.
    await loadContinueReading();

    //get all of em data
    final futures = await Future.wait([
      // fetches "continue watching" list
      getWatchedList(userName: userName).onError((e, st) {
        recentlyWatched.state = LoadingState.error;
        Logs.app.log("Error fetching watched list. $e");
        return <UserAnimeListItem>[];
      }),

      // fetches "aired this season" list
      Anilist().getCurrentlyAiringAnime().onError((e, st) {
        currentlyAiring.state = LoadingState.error;
        Logs.app.log("Error fetching currently airing list. $e");
        return <CurrentlyAiringResult>[];
      }),

      // fetches "from your planned" list
      if (userName != null)
        AnilistQueries().getUserAnimeList(userName, status: [MediaStatus.PLANNING]).onError((e, st) {
          plannedList.state = LoadingState.error;
          Logs.app.log("Error fetching planned list. $e");
          return <UserAnimeList>[];
        }),
    ]);

    notifyListeners();

    if (currentlyAiring.state.isError || recentlyWatched.state.isError || plannedList.state.isError) {
      if (currentUserSettings?.enableLogging ?? false) await Logs.app.writeLog();
    }

    List<UserAnimeListItem> watched = futures[0] as List<UserAnimeListItem>;
    if (watched.length > 40) watched = watched.sublist(0, 40);
    recentlyWatched.items = [];
    watched.forEach(
      (item) => recentlyWatched.items.add(
        HomePageList(
          coverImage: item.coverImage,
          id: item.id.toString(),
          rating: item.rating,
          title: item.title,
          watchedEpisodeCount: item.watchProgress,
          totalEpisodes: item.episodes,
        ),
      ),
    );
    recentlyWatched.state = LoadingState.loaded;

    final List<CurrentlyAiringResult> currentlyAiringResponse = futures[1] as List<CurrentlyAiringResult>;
    _thisSeason.clear();
    if (currentlyAiringResponse.isEmpty) return;

    currentlyAiring.items = [];
    _thisSeasonData = currentlyAiringResponse;
    currentlyAiringResponse.forEach((item) {
      currentlyAiring.items.add(
        HomePageList(
            coverImage: item.cover,
            id: item.id.toString(),
            rating: item.rating,
            title: item.title,
            totalEpisodes: item.episodes,
            watchedEpisodeCount: item.watchProgress),
      );
      currentlyAiring.state = LoadingState.loaded;

      final title = item.title['english'] ?? item.title['romaji'] ?? '';
      thisSeason.add(
        Cards.animeCard(
          item.id,
          (currentUserSettings?.nativeTitle ?? false) ? item.title['native'] ?? title : title,
          item.cover,
          rating: item.rating,
          isMobile: !tv && isAndroid,
        ),
      );
    });

    if (userName != null) {
      List<UserAnimeList> pl = futures[2] as List<UserAnimeList>;
      if (pl.isEmpty) {
        notifyListeners();
        return;
      }
      plannedList.items = [];
      List<UserAnimeListItem> itemList = pl[0].list;
      if (itemList.length > 25) itemList = itemList.sublist(0, 25);
      itemList.forEach((item) {
        plannedList.items.add(HomePageList(
          coverImage: item.coverImage,
          rating: item.rating,
          title: item.title,
          id: item.id.toString(),
          totalEpisodes: item.episodes,
          watchedEpisodeCount: item.watchProgress,
        ));
      });
      plannedList.state = LoadingState.loaded;
    }

    // I think its safe to assume that if all three lists errored out, then Anilist must be down. Unless... user is offline
    if (recentlyWatched.state.isError &&
        currentlyAiring.state.isError &&
        (userName != null ? plannedList.state.isError : false)) {
      if (currentUserSettings?.showErrors ?? false)
        floatingSnackBar("Couldn't load home data. Is Anilist down?", waitForPreviousToFinish: true);
    }

    notifyListeners();
  }

  /// Fetch the manga rails from AniList.
  ///
  /// Fails quietly: Discover still has three anime rails without these, so a
  /// manga fetch error must not take the whole page down with it. Returns
  /// whether either rail loaded, so the caller can tell a failed refresh from
  /// a successful one.
  Future<bool> getMangaDiscoverItems() async {
    final source = AnilistManga();
    final isMobile = !tv && isAndroid;
    var loadedAny = false;

    try {
      final trending = await source.getTrending();
      _mangaTrendingList = trending.map((manga) => _mangaCard(manga, isMobile)).toList(growable: false);
      loadedAny = true;
    } catch (e) {
      Logs.app.log("Error loading manga trending: $e");
    }
    try {
      final popular = await source.getPopular();
      _mangaPopularList = popular.map((manga) => _mangaCard(manga, isMobile)).toList(growable: false);
      loadedAny = true;
    } catch (e) {
      Logs.app.log("Error loading manga popular: $e");
    }

    return loadedAny;
  }

  /// A manga card for a Discover rail.
  ///
  /// Routes to MangaDetailsPage rather than the anime info page, which is what
  /// `shouldNavigate: false` plus an explicit onTap does. `isAnime` stays true
  /// because AnimeCard gates on it before it consults `onTap` -- see the note
  /// on that field in animeCard.dart.
  AnimeCard _mangaCard(MangaSummary manga, bool isMobile) {
    final preferNative = currentUserSettings?.nativeTitle ?? false;
    return Cards.animeCard(
      int.tryParse(manga.id) ?? 0,
      manga.title,
      manga.cover ?? '',
      rating: manga.rating,
      isMobile: isMobile,
      shouldNavigate: false,
      subText: preferNative ? null : manga.format,
      onTap: () => Navigator.of(_navContext!).push(
        MaterialPageRoute(builder: (context) => MangaDetailsPage(id: manga.id)),
      ),
    );
  }

  /// The context a rail card navigates from.
  ///
  /// `Cards.animeCard` hands back a widget with no context of its own to push
  /// with, and the provider has none either. `discover.dart` seeds this on its
  /// first build; `_mangaCard`'s onTap only ever runs after that.
  BuildContext? _navContext;
  void attachNavigationContext(BuildContext context) {
    _navContext = context;
  }

  /// Load the items list for the Discover page.
  ///
  /// The four rails are loaded independently: one failing must not discard the
  /// other three, and the page needs to know whether *everything* failed so it
  /// can show an error instead of four spinners.
  Future<void> loadDiscoverItems() async {
    final wasShowingError = _discoverError;
    _discoverError = false;
    _discoverDataLoaded = false;
    if (wasShowingError) notifyListeners();

    final loaded = await Future.wait<bool>([
      _runDiscoverPart('trending', getTrendingList),
      _runDiscoverPart('recently updated', getRecentlyUpdated),
      _runDiscoverPart('recommended', getRecommended),
      getMangaDiscoverItems(),
    ]);

    final loadedAny = loaded.any((part) => part);
    _discoverDataLoaded = loadedAny;
    _discoverError = !loadedAny;
    notifyListeners();

    if (!loadedAny && (currentUserSettings?.showErrors ?? false)) {
      floatingSnackBar(
        "Couldn't load Discover. AniList may be unavailable.",
        waitForPreviousToFinish: true,
      );
    }
  }

  Future<bool> _runDiscoverPart(String label, Future<void> Function() part) async {
    try {
      await part();
      return true;
    } catch (e) {
      Logs.app.log("Error loading Discover $label: $e");
      return false;
    }
  }

  RefreshController homeRefreshController = RefreshController(initialRefresh: false);
  RefreshController discoverRefreshController = RefreshController(initialRefresh: false);

  void refreshTree() {
    notifyListeners();
  }

  /// refresh [0 = home, 1 = discover]
  Future<void> refresh({required int refreshPage, bool fromSettings = false}) async {
    if (refreshPage != 0 && refreshPage != 1) return;

    if (!(await isConnectedToInternet())) {
      floatingSnackBar("You're offline. Connect to the internet and try again.", waitForPreviousToFinish: true);
      currentlyAiring.state = LoadingState.error;
      recentlyWatched.state = LoadingState.error;
      plannedList.state = LoadingState.error;
      return refreshPage == 0 ? homeRefreshController.refreshCompleted() : discoverRefreshController.refreshCompleted();
    }

    if (refreshPage == 1) {
      await loadDiscoverItems();
      discoverRefreshController.refreshCompleted();
      notifyListeners();
      return;
    }

    // yes a bit expensive... we could check the userProfile nullability first. but meh
    loggedIn = await AniListLogin().isAnilistLoggedIn();
    if (loggedIn && userProfile == null) {
      //load the userprofile and list if the user just signed in!
      userProfile = await AniListLogin().getUserProfile();
      storedUserData = userProfile;
      Logs.app.log("[AUTHENTICATION] ${storedUserData?.name} Login Successful");
      await loadListsForHome(userName: userProfile!.name);
    } else if (loggedIn && userProfile != null) {
      //just load the list if the user was already signed in.
      //also dont refresh the list if user just visited the settings page and were already logged in
      if (fromSettings) return;

      await loadListsForHome(userName: userProfile!.name);
    } else {
      await loadListsForHome();
      userProfile = null;
    }
    homeRefreshController.refreshCompleted();
    notifyListeners();
  }
}

class AnimeListData<T> {
  String? title;
  List<T> items;
  LoadingState state;

  AnimeListData({
    this.title,
    this.items = const [],
    this.state = LoadingState.loading,
  });
}
