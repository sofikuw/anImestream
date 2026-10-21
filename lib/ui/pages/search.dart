import 'dart:async';
import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/database/handler/handler.dart';
import 'package:animestream/core/database/types.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:animestream/ui/models/widgets/cards/animeCardExtended.dart';
import 'package:animestream/ui/models/widgets/header.dart';
import 'package:animestream/ui/pages/mangaDetails.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:flutter/material.dart';

/// Search across anime *and* manga.
///
/// The two live in different pipelines and there is no shared result type:
/// anime comes from `DatabaseHandler().search()` returning
/// `DatabaseSearchResult` (AniList / MAL / Simkl, whichever is active), and
/// manga comes from `AnilistManga().search()` returning `MangaSummary`.
///
/// Rather than widen `Database`'s interface -- which would force a matching
/// change in all three anime backends -- the two calls are issued in parallel
/// and merged here, into one list of [_SearchHit]. A filter row lets either
/// type be hidden.
///
/// One deliberate behaviour: if the manga lookup fails (AniList down, offline),
/// the anime results still render. A failed half must not blank a working half.
class Search extends StatefulWidget {
  const Search({super.key});

  @override
  State<Search> createState() => _SearchState();
}

/// Which content types the grid is showing.
enum SearchFilter { all, anime, manga }

/// One row in the unified grid.
class _SearchHit {
  /// "anime" or "manga".
  final String contentType;

  /// AniList id, as a String so the same field carries both.
  final String id;

  final Map<String, String?> title;
  final String cover;
  final double? rating;
  final int? totalEpisodes;

  const _SearchHit({
    required this.contentType,
    required this.id,
    required this.title,
    required this.cover,
    this.rating,
    this.totalEpisodes,
  });

  bool get isManga => contentType == 'manga';
}

class _SearchState extends State<Search> {
  List<DatabaseSearchResult> results = [];
  List<DatabaseSearchResult> exactMatches = [];

  /// Manga hits, kept separate from the anime lists above so filtering never
  /// has to re-sort a merged collection.
  List<MangaSummary> mangaResults = [];

  /// Set when a half of the search failed, so the UI can say so without
  /// hiding the half that worked. Both set means the lookup itself is down,
  /// which must not be presented as "no matches".
  bool animeSearchFailed = false;
  bool mangaSearchFailed = false;

  /// True once a non-empty query has been submitted, so the empty state is not
  /// shown before the user has searched for anything.
  bool _hasSearched = false;

  /// Incremented for every search. A slower earlier query must not overwrite
  /// the results of a newer one.
  int _searchGeneration = 0;

  TextEditingController textEditingController = TextEditingController();

  bool _searching = false;

  Timer? debounce;

  final db = DatabaseHandler();
  final mangaSource = AnilistManga();

  SearchFilter filter = SearchFilter.all;

  Future addCards(String query) async {
    final generation = ++_searchGeneration;

    //for cleaning the UI
    results = [];
    exactMatches = [];
    mangaResults = [];
    animeSearchFailed = false;
    mangaSearchFailed = false;
    _hasSearched = true;

    // Both lookups run together. `Future.wait` is deliberately not used: one
    // failing future would fail the whole wait and lose the other's results.
    final animeFuture = db.search(query).catchError((err) {
      if (generation == _searchGeneration) animeSearchFailed = true;
      return <DatabaseSearchResult>[];
    });
    final mangaFuture = mangaSource.search(query).catchError((err) {
      if (generation == _searchGeneration) mangaSearchFailed = true;
      return <MangaSummary>[];
    });

    final animeResults = await animeFuture;
    final mangaHits = await mangaFuture;

    // A newer search has started; its result owns the UI.
    if (generation != _searchGeneration) return;

    //for removing the data from previous search invokation due to debouncing
    results = [];
    exactMatches = [];

    if (animeResults.length == 0 && mangaHits.length == 0) {
      return setState(() {
        _searching = false;
      });
    }

    animeResults.forEach((ele) {
      final String title = ele.title['english'] ?? ele.title['romaji'] ?? '';
      results.add(ele);
      if (query.toLowerCase() == title.toLowerCase()) {
        exactMatches.add(ele);
      }
    });

    mangaResults = mangaHits;

    setState(() {
      _searching = false;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  bool exactMatch = false;
  bool verticalCards = userPreferences?.searchPageListMode ?? false;
  final nativeTitle = currentUserSettings?.nativeTitle ?? false;

  /// The anime half of the grid, before merging.
  List<DatabaseSearchResult> get _visibleAnime =>
      exactMatch ? exactMatches : results;

  List<_SearchHit> get _hits {
    final hits = <_SearchHit>[];

    if (filter != SearchFilter.manga) {
      for (final it in _visibleAnime) {
        hits.add(
          _SearchHit(
            contentType: 'anime',
            id: it.id.toString(),
            title: it.title,
            cover: it.cover,
            rating: it.rating,
            totalEpisodes: it.totalEpisodes,
          ),
        );
      }
    }

    if (filter != SearchFilter.anime) {
      for (final manga in mangaResults) {
        hits.add(
          _SearchHit(
            contentType: 'manga',
            id: manga.id,
            title: {'title': manga.title},
            cover: manga.cover ?? '',
            rating: manga.rating,
          ),
        );
      }
    }

    return hits;
  }

  /// True when the exact-match toggle has narrowed anime away but manga results
  /// remain -- worth saying out loud, because the empty anime half looks like a
  /// bug otherwise.
  bool get _animeHiddenByExactMatch =>
      exactMatch && exactMatches.isEmpty && results.isNotEmpty;

  /// Whether the lookup behind the current filter failed.
  bool get _searchFailedForCurrentFilter {
    switch (filter) {
      case SearchFilter.anime:
        return animeSearchFailed;
      case SearchFilter.manga:
        return mangaSearchFailed;
      case SearchFilter.all:
        return animeSearchFailed && mangaSearchFailed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Padding(
          padding: pagePadding(context).copyWith(left: 0),
          child: Column(
            children: [
              buildHeader("Search", context, afterNavigation: () => setState(() {})),
              Container(
                padding: EdgeInsets.only(top: 15, left: 25, right: 25, bottom: 10),
                child: Column(
                  children: [
                    _searchBar(),
                    _searchOptions(),
                    _filterRow(),
                  ],
                ),
              ),
              Expanded(
                child: _searching
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: appTheme.accentColor,
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Text(
                              "searching...",
                              style: TextStyle(
                                  color: appTheme.accentColor,
                                  fontFamily: "NotoSans",
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          )
                        ],
                      )
                    : _searchResults(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SizedBox footSpace() {
    return SizedBox(
      height: MediaQuery.of(context).padding.bottom + 60,
    );
  }

  /// Anime / Manga / All.
  Container _filterRow() {
    Widget chip(String label, SearchFilter value) {
      final selected = filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => filter = value),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? appTheme.accentColor : appTheme.backgroundSubColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: "NotoSans",
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: selected ? appTheme.onAccent : appTheme.textMainColor,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.only(top: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          chip("All", SearchFilter.all),
          chip("Anime", SearchFilter.anime),
          chip("Manga", SearchFilter.manga),
        ],
      ),
    );
  }

  Container _searchOptions() {
    return Container(
      padding: EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Checkbox(
            value: exactMatch,
            onChanged: (val) => setState(() {
              exactMatch = val!;
            }),
            activeColor: appTheme.accentColor,
            checkColor: Colors.black,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(
            "exact match",
            style: TextStyle(
              color: appTheme.textMainColor,
              fontFamily: "NotoSans",
              fontWeight: FontWeight.bold,
            ),
          ),
          Checkbox(
            value: verticalCards,
            onChanged: (val) => setState(() {
              verticalCards = val!;
              UserPreferences.saveUserPreferences(UserPreferencesModal(searchPageListMode: val));
            }),
            activeColor: appTheme.accentColor,
            checkColor: Colors.black,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Text(
            "list view",
            style: TextStyle(
              color: appTheme.textMainColor,
              fontFamily: "NotoSans",
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Container _searchResults() {
    final hits = _hits;

    return Container(
      padding: EdgeInsets.only(left: 15, right: 15),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_animeHiddenByExactMatch)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  "No exact-match anime. Uncheck \"exact match\" to see ${results.length} close titles.",
                  style: TextStyle(
                    fontFamily: "NotoSans",
                    fontSize: 13,
                    color: appTheme.textSubColor,
                  ),
                ),
              ),
            if (animeSearchFailed && !mangaSearchFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  "Anime results are unavailable right now.",
                  style: TextStyle(
                    fontFamily: "NotoSans",
                    fontSize: 13,
                    color: appTheme.textSubColor,
                  ),
                ),
              ),
            if (mangaSearchFailed && !animeSearchFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  "Manga results are unavailable right now.",
                  style: TextStyle(
                    fontFamily: "NotoSans",
                    fontSize: 13,
                    color: appTheme.textSubColor,
                  ),
                ),
              ),
            if (hits.isEmpty && _hasSearched) _searchEmptyState(),
            GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: verticalCards ? 450 : 180,
                  mainAxisExtent: verticalCards
                      ? 150
                      : Platform.isAndroid
                          ? 220
                          : 265,
                  crossAxisSpacing: verticalCards ? 10 : 0,
                  mainAxisSpacing: 15),
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: hits.length,
              itemBuilder: (context, index) {
                final hit = hits[index];
                final title = hit.title['english'] ?? hit.title['romaji'] ?? hit.title['title'] ?? '';

                if (verticalCards) {
                  return AnimeCardExtended(
                    // Anime ids are ints; a manga id may not be, so the card
                    // takes the real one through routeId and this field is
                    // ignored for manga rows.
                    id: int.tryParse(hit.id) ?? 0,
                    routeId: hit.id,
                    contentType: hit.contentType,
                    title: nativeTitle ? hit.title['native'] ?? title : title,
                    imageUrl: hit.cover,
                    rating: hit.rating ?? 0,
                    customWidth: 450,
                    totalEpisodes: hit.totalEpisodes,
                    surfaceColor: appTheme.backgroundSubColor.withAlpha(100),
                  );
                }

                // The manga variant routes itself, so it needs no wrapper.
                if (hit.isManga) {
                  return Center(
                    child: Cards.animeCard(
                      int.tryParse(hit.id) ?? 0,
                      nativeTitle ? hit.title['native'] ?? title : title,
                      hit.cover,
                      rating: hit.rating,
                      isAnime: true,
                      isMobile: Platform.isAndroid,
                      shouldNavigate: false,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => MangaDetailsPage(id: hit.id),
                        ),
                      ),
                    ),
                  );
                }

                return Center(
                  child: Cards.animeCard(
                    int.tryParse(hit.id) ?? 0,
                    nativeTitle ? hit.title['native'] ?? title : title,
                    hit.cover,
                    rating: hit.rating,
                    isAnime: true,
                    isMobile: Platform.isAndroid,
                  ),
                );
              },
            ),
            footSpace(),
          ],
        ),
      ),
    );
  }

  Widget _searchEmptyState() {
    final failed = _searchFailedForCurrentFilter;
    return Padding(
      padding: const EdgeInsets.only(top: 40, bottom: 20),
      child: Column(
        children: [
          Icon(
            failed ? Icons.cloud_off_rounded : Icons.search_off_rounded,
            color: appTheme.textSubColor,
            size: 42,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              failed ? "Couldn't reach the search service" : "No matches found",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: appTheme.textMainColor,
                fontFamily: "NotoSans",
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "The metadata service may be temporarily unavailable. Your connection is fine.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: appTheme.textSubColor,
                  fontFamily: "NunitoSans",
                  fontSize: 13,
                ),
              ),
            ),
          TextButton(
            onPressed: _retrySearch,
            child: Text(
              "Retry",
              style: TextStyle(
                color: appTheme.accentColor,
                fontFamily: "NotoSans",
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _retrySearch() {
    final query = textEditingController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    addCards(query);
  }

  TextField _searchBar() {
    return TextField(
      controller: textEditingController,
      onChanged: (val) {
        if (debounce?.isActive ?? false) debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 300), () async {
          if (val.length <= 0) {
            return;
          }
          setState(() {
            _searching = true;
          });
          await addCards(val);
        });
      },
      onSubmitted: (val) async {
        if (val.length <= 0) {
          return;
        }
        setState(() {
          _searching = true;
        });
        await addCards(val);
      },
      autocorrect: false,
      cursorColor: appTheme.accentColor,
      decoration: InputDecoration(
        labelText: "search",
        labelStyle:
            TextStyle(color: appTheme.textMainColor, fontFamily: "Rubik", fontWeight: FontWeight.bold, fontSize: 17),
        suffixIcon: Padding(
          padding: EdgeInsets.only(right: 10),
          child: Image.asset(
            'lib/assets/images/search.png',
            color: appTheme.textMainColor,
            scale: 1.75,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50.0),
          borderSide: BorderSide(width: 1.5, color: appTheme.textMainColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50.0),
          borderSide: BorderSide(color: appTheme.accentColor),
        ),
        hintText: "Search anime and manga...",
        hintStyle: TextStyle(fontFamily: "Poppins", color: Color.fromARGB(255, 168, 168, 168)),
        contentPadding: EdgeInsets.only(left: 20, right: 20, top: 15, bottom: 15),
      ),
      style: TextStyle(color: appTheme.textMainColor, fontFamily: "Poppins"),
    );
  }

  @override
  void dispose() {
    textEditingController.dispose();
    debounce?.cancel();
    super.dispose();
  }
}