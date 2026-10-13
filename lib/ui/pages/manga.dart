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
/// Styling follows `home.dart` on purpose: same header, section title
/// typography (Rubik 20), accent progress indicators, and the shared ghost
/// artwork for empty/error states.
class Manga extends StatefulWidget {
  const Manga({super.key});

  @override
  State<Manga> createState() => _MangaState();
}

class _MangaState extends State<Manga> {
  final AnilistManga _source = AnilistManga();
  final RefreshController _refreshController = RefreshController(initialRefresh: false);
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Same safe-area padding as Home and Discover, so the title
              // and its download/settings buttons line up with theirs.
              Padding(
                padding: pagePadding(context).copyWith(left: 0),
                child: buildHeader("Manga", context),
              ),
              _searchField(),
              if (_searching)
                _searchResultsView()
              else ...[
                for (var index = 0; index < _sectionTitles.length; index++) ...[
                  _section(_sectionTitles[index]),
                  if (index != _sectionTitles.length - 1) divider(),
                ],
                if (_allFailed) _attribution(),
                footSpace(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _allFailed =>
      _sectionTitles.every((title) => _states[title] == LoadingState.error);

  Widget _searchField() {
    return Container(
      margin: const EdgeInsets.only(left: 15, right: 15, bottom: 10),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: runSearch,
        style: TextStyle(color: appTheme.textMainColor, fontFamily: "NotoSans", fontSize: 15),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: "Search manga",
          hintStyle: TextStyle(color: appTheme.textSubColor, fontFamily: "NotoSans", fontSize: 15),
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

  Widget _searchResultsView() {
    if (_searchState == LoadingState.loading) return _loading();
    if (_searchState == LoadingState.error) return _empty("Aww... Something's wrong!", Icons.error_outline);
    if (_searchResults.isEmpty) return _empty("Boo! Nothing's here!");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Results"),
        _grid(_searchResults),
        footSpace(),
      ],
    );
  }

  Widget _section(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title),
        Container(
          height: 160,
          child: switch (_states[title]) {
            LoadingState.loading => _loading(),
            LoadingState.error => _empty("Aww... Something's wrong!"),
            _ => _sections[title]!.isEmpty
                ? _empty("Boo! Nothing's here!")
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    scrollDirection: Axis.horizontal,
                    itemCount: _sections[title]!.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _card(_sections[title]![index]),
                    ),
                  ),
          },
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 15, right: 15, bottom: 4),
      child: Text(
        title,
        style: TextStyle(fontFamily: "Rubik", fontSize: 20, color: appTheme.textMainColor),
      ),
    );
  }

  Widget _grid(List<MangaSummary> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 230,
        childAspectRatio: 120 / 220,
        mainAxisSpacing: 10,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => Center(child: _card(items[index])),
    );
  }

  /// Reuses the app's own anime card for visual parity, with its built-in
  /// navigation disabled so the tap can open the manga details page instead.
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

  Widget _loading() {
    return Center(
      child: CircularProgressIndicator(color: appTheme.accentColor),
    );
  }

  /// Mirrors home.dart's empty/error treatment.
  Widget _empty(String message, [IconData? icon]) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon == null
              ? Image.asset("lib/assets/images/ghost.png", color: const Color.fromARGB(255, 80, 80, 80))
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
          style: TextStyle(fontFamily: "NotoSans", fontSize: 13, color: appTheme.textSubColor),
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
