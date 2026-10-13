import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:animestream/ui/models/widgets/header.dart';
import 'package:animestream/ui/pages/mangaDetails.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:flutter/material.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

/// The Manga tab.
///
/// Metadata comes from AniList through [AnilistManga]; this page therefore
/// browses and searches fine with no extension installed. Chapters and pages
/// are not available here -- see [MangaDetailsPage].
///
/// Built to match `home.dart` / `discover.dart` rather than to invent a layout:
/// the same `pagePadding` wrapper, the same `buildHeader`, the same
/// `_titleAndList` sections with the shared accent divider, and the same
/// `Cards.animeCard` tiles (which carry the title and rating under the cover,
/// so the section name is never the only thing on screen).
///
/// The earlier version put the search field above the sections and used a
/// fixed-height horizontal strip, which is why titles were clipped and the
/// section spacing did not match the anime tabs.
class Manga extends StatefulWidget {
  const Manga({super.key});

  @override
  State<Manga> createState() => _MangaState();
}

class _MangaState extends State<Manga> {
  final AnilistManga _source = AnilistManga();
  final RefreshController _refreshController =
      RefreshController(initialRefresh: false);
  final TextEditingController _searchController = TextEditingController();

  /// Ordered so the sections render in a stable, deliberate order.
  static const List<String> _sectionTitles = [
    'Trending Now',
    'Most Popular',
    'Recently Updated',
  ];

  final Map<String, List<MangaSummary>> _sections = {
    for (final title in _sectionTitles) title: <MangaSummary>[],
  };
  final Map<String, LoadingState> _states = {
    for (final title in _sectionTitles) title: LoadingState.loading,
  };

  List<MangaSummary> _searchResults = [];
  LoadingState _searchState = LoadingState.loaded;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    loadSections();
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadSections() async {
    if (mounted) {
      setState(() {
        for (final title in _sectionTitles) {
          _states[title] = LoadingState.loading;
        }
      });
    }

    // Loaded independently so one failing section does not blank the page.
    final results = await Future.wait([
      _load(_source.getTrending),
      _load(_source.getPopular),
      _load(_source.getLatest),
    ]);

    if (!mounted) return;

    setState(() {
      for (var index = 0; index < _sectionTitles.length; index++) {
        final title = _sectionTitles[index];
        final outcome = results[index];
        _sections[title] = outcome.items;
        _states[title] = outcome.failed ? LoadingState.error : LoadingState.loaded;
      }
    });
  }

  Future<_SectionResult> _load(Future<List<MangaSummary>> Function() fetch) async {
    try {
      return _SectionResult(items: await fetch(), failed: false);
    } catch (err) {
      Logs.app.log("Error loading manga section: $err");
      if ((currentUserSettings?.showErrors ?? false) && mounted) {
        floatingSnackBar(err.toString());
      }
      return _SectionResult(items: const <MangaSummary>[], failed: true);
    }
  }

  Future<void> runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _searching = true;
      _searchState = LoadingState.loading;
    });

    try {
      final results = await _source.search(trimmed);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _searchState = LoadingState.loaded;
      });
    } catch (err) {
      Logs.app.log("Manga search failed: $err");
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _searchState = LoadingState.error;
      });
      if (currentUserSettings?.showErrors ?? false) floatingSnackBar(err.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SmartRefresher(
        controller: _refreshController,
        onRefresh: () async {
          if (_searching) {
            await runSearch(_searchController.text);
          } else {
            await loadSections();
          }
          _refreshController.refreshCompleted();
        },
        header: WaterDropMaterialHeader(
          backgroundColor: appTheme.backgroundSubColor,
          color: appTheme.accentColor,
        ),
        child: Container(
          padding: pagePadding(context).copyWith(left: 0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildHeader("Manga", context, afterNavigation: () {
                  if (mounted) setState(() {});
                }),
                _searchField(),
                if (_searching)
                  _searchResultsView()
                else ...{
                  for (var index = 0; index < _sectionTitles.length; index++) ...{
                    _titleAndList(_sectionTitles[index], _sections[_sectionTitles[index]]!,
                        state: _states[_sectionTitles[index]] ?? LoadingState.loaded),
                    if (index != _sectionTitles.length - 1) divider(),
                  },
                  if (_allFailed) _attribution(),
                  footSpace(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _allFailed =>
      _sectionTitles.every((title) => _states[title] == LoadingState.error);

  /// Same shape as the anime search box: one rounded field, no border, in the
  /// page's own padding rather than the section padding.
  Widget _searchField() {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, bottom: 5),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: runSearch,
        style: TextStyle(
          color: appTheme.textMainColor,
          fontFamily: "NotoSans",
          fontSize: 15,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search manga",
          hintStyle: TextStyle(
            color: appTheme.textSubColor,
            fontFamily: "NotoSans",
            fontSize: 15,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: appTheme.textSubColor),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, color: appTheme.textSubColor),
                  onPressed: () {
                    _searchController.clear();
                    runSearch('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  /// Mirrors `home.dart:_titleAndList`: title, then a horizontal list of
  /// anime-style cards, with the same empty/loading/error treatment.
  Widget _titleAndList(
    String title,
    List<MangaSummary> list, {
    LoadingState state = LoadingState.loaded,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 20, top: 20),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: "Rubik",
              fontSize: 22,
              color: appTheme.textMainColor,
            ),
          ),
        ),
        Container(
          height: 260,
          margin: const EdgeInsets.only(top: 10),
          child: switch (state) {
            LoadingState.loading => Center(
                child: CircularProgressIndicator(color: appTheme.accentColor),
              ),
            LoadingState.error => _empty("Aww... Something's wrong!"),
            _ => list.isEmpty
                ? _empty("Boo! Nothing's here!")
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    scrollDirection: Axis.horizontal,
                    itemCount: list.length,
                    itemBuilder: (context, index) => _card(list[index]),
                  ),
          },
        ),
      ],
    );
  }

  Widget _searchResultsView() {
    if (_searchState == LoadingState.loading) {
      return Container(
        height: 260,
        child: Center(child: CircularProgressIndicator(color: appTheme.accentColor)),
      );
    }
    return _grid(
      _searchState == LoadingState.error
          ? const <MangaSummary>[]
          : _searchResults,
      error: _searchState == LoadingState.error,
    );
  }

  /// Search results are a wrap-around grid: a query can return 25 titles, and a
  /// single row would hide most of them.
  Widget _grid(List<MangaSummary> items, {bool error = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.only(left: 20, top: 20),
          child: Text(
            "Results",
            style: TextStyle(
              fontFamily: "Rubik",
              fontSize: 22,
              color: appTheme.textMainColor,
            ),
          ),
        ),
        if (error)
          SizedBox(height: 240, child: _empty("Aww... Something's wrong!"))
        else if (items.isEmpty)
          SizedBox(height: 240, child: _empty("Boo! Nothing's here!"))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 165,
              mainAxisExtent: 250,
              mainAxisSpacing: 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _card(items[index]),
          ),
        footSpace(),
      ],
    );
  }

  /// The app's own anime card, with its built-in navigation replaced by the
  /// manga details route.
  ///
  /// The card owns its `InkWell`, so a caller wrapping it in another one never
  /// sees the tap -- hence `onTap` on `AnimeCard` rather than a wrapper here.
  Widget _card(MangaSummary manga) {
    final preferNative = currentUserSettings?.nativeTitle ?? false;
    return Cards.animeCard(
      int.tryParse(manga.id) ?? 0,
      manga.title,
      manga.cover ?? '',
      rating: manga.rating,
      shouldNavigate: false,
      subText: preferNative ? null : manga.format,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => MangaDetailsPage(id: manga.id)),
      ),
    );
  }

  /// Mirrors home.dart's empty/error treatment.
  Widget _empty(String message, [IconData? icon]) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon == null
              ? Image.asset("lib/assets/images/ghost.png",
                  color: const Color.fromARGB(255, 80, 80, 80))
              : Icon(icon, color: const Color.fromARGB(255, 80, 80, 80), size: 48),
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: "NunitoSans",
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 80, 80, 80),
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attribution() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Text(
          "Couldn't reach AniList. Check your connection and pull to refresh.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: "NotoSans",
            fontSize: 13,
            color: appTheme.textSubColor,
          ),
        ),
      ),
    );
  }

  Center divider() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width / 2,
        margin: const EdgeInsets.only(top: 15, bottom: 15),
        height: 6,
        decoration: BoxDecoration(
          color: appTheme.accentColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  SizedBox footSpace() {
    return SizedBox(height: MediaQuery.of(context).padding.bottom + 60);
  }
}

class _SectionResult {
  final List<MangaSummary> items;
  final bool failed;

  const _SectionResult({required this.items, required this.failed});
}