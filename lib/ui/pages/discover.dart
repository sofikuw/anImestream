import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:animestream/ui/models/providers/mainNavProvider.dart';
import 'package:animestream/ui/models/widgets/cards/animeCard.dart';
import 'package:animestream/ui/models/widgets/infoPageWidgets/scrollingList.dart';
import 'package:flutter/material.dart';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/ui/models/widgets/header.dart';
import 'package:animestream/ui/pages/genres.dart';
import 'package:animestream/ui/pages/info.dart';
import 'package:animestream/ui/pages/news.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class Discover extends StatefulWidget {
  final MainNavProvider mainNavProvider;

  const Discover({
    super.key,
    required this.mainNavProvider,
  });

  @override
  State<Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<Discover> {
  @override
  void initState() {
    super.initState();
    // Do not retry a load that already failed just because the tab was
    // reopened: that is what made a failed API look like a page stuck
    // reloading. The error banner's Retry (or pull-to-refresh) starts a new
    // attempt explicitly.
    if (!widget.mainNavProvider.discoverDataLoaded && !widget.mainNavProvider.discoverError) {
      widget.mainNavProvider.loadDiscoverItems();
    }
    // Manga rail cards are built by the provider and navigate on tap, so it
    // needs a context to push from before any of them can be built.
    widget.mainNavProvider.attachNavigationContext(context);
    _pageController.addListener(onScroll);
  }

  final recentlyUpdatedScrollController = ScrollController(),
      thisSeasonScrollController = ScrollController(),
      recommendedScrollController = ScrollController(),
      mangaTrendingScrollController = ScrollController(),
      mangaPopularScrollController = ScrollController();

  int currentPage = 0;
  final PageController _pageController = PageController();
  Timer? timer;
  // bool trendingLoaded = false, recentlyUpdatedLoaded = false, recommendedLoaded = false;
  double page = 0;

  void onScroll() {
    setState(() {
      page = _pageController.page ?? 0;
    });
  }

  Future<void> pageTimeout() async {
    if (timer != null && timer!.isActive) timer!.cancel();
    timer = Timer(Duration(seconds: 5), () {
      if (currentPage < widget.mainNavProvider.trendingList.length - 1) {
        currentPage++;
      } else
        currentPage = 0;
      if (mounted)
        setState(() {
          _pageController.animateToPage(currentPage, duration: Duration(milliseconds: 400), curve: Curves.easeOut);
        });
    });
  }

  bool initialTimeOutCalled = false;

  bool isHoveredOverScrollList = false;

  @override
  Widget build(BuildContext context) {
    if (!initialTimeOutCalled && widget.mainNavProvider.trendingList.length > 0) {
      pageTimeout();
      initialTimeOutCalled = true;
    }
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SmartRefresher(
        // reset the controller on build, preventing it from causing error: "Dont use one controller for multiple SmartRefresher"
        controller: widget.mainNavProvider.discoverRefreshController = RefreshController(initialRefresh: false),
        onRefresh: () async {
          await widget.mainNavProvider.refresh(refreshPage: 1, fromSettings: false);
        },
        header: WaterDropMaterialHeader(
          backgroundColor: appTheme.backgroundSubColor,
          color: appTheme.accentColor,
        ),
        child: SingleChildScrollView(
          physics: isHoveredOverScrollList ? NeverScrollableScrollPhysics() : null,
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    // margin: EdgeInsets.only(top: 30),
                    height: (Platform.isWindows || Platform.isLinux) ? 450 : 370,
                    // width: double.infinity,
                    child: widget.mainNavProvider.trendingList.length > 0
                        ? _trendingAnimesPageView()
                        : Container(
                            child: Center(
                              child: widget.mainNavProvider.discoverDataLoaded ||
                                      widget.mainNavProvider.discoverError
                                  ? _unavailableLabel("Trending is unavailable right now")
                                  : CircularProgressIndicator(
                                      color: appTheme.accentColor,
                                    ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: pagePadding(context).copyWith(left: 0),
                    child: buildHeader("Discover", context, afterNavigation: () => setState(() {})),
                  )
                ],
              ),
              if (widget.mainNavProvider.discoverError) _discoverErrorBanner(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 30, right: 25),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => News()));
                      },
                      child: Container(
                        height: 75,
                        width: 150,
                        decoration: BoxDecoration(
                          // color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          image: DecorationImage(
                              image: AssetImage(
                                'lib/assets/images/chisato.jpeg',
                              ),
                              fit: BoxFit.cover,
                              opacity: 0.4),
                          border: Border.all(color: appTheme.accentColor),
                        ),
                        child: Center(
                          child: Text(
                            "News",
                            style: TextStyle(
                              color: appTheme.textMainColor,
                              fontFamily: "NotoSans",
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(top: 30),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => GenresPage()));
                      },
                      child: Container(
                        height: 75,
                        width: 150,
                        decoration: BoxDecoration(
                          // color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                          image: DecorationImage(
                              image: AssetImage(
                                'lib/assets/images/mitsuha.jpg',
                              ),
                              fit: BoxFit.cover,
                              opacity: 0.4),
                          border: Border.all(color: appTheme.accentColor),
                        ),
                        child: Center(
                          child: Text(
                            "Genres",
                            style: TextStyle(
                              color: appTheme.textMainColor,
                              fontFamily: "NotoSans",
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _itemTitle("Recently updated", recentlyUpdatedScrollController),
              _scrollList(widget.mainNavProvider.recentlyUpdatedList, recentlyUpdatedScrollController),
              _itemTitle("This season", thisSeasonScrollController),
              _scrollList(widget.mainNavProvider.thisSeason, thisSeasonScrollController),
              _itemTitle("Recommended", recommendedScrollController),
              _scrollList(widget.mainNavProvider.recommendedList, recommendedScrollController),
              // Manga rails. Same _itemTitle/_scrollList pair as the anime
              // rails above. Their cards add a format line under the title, so
              // _scrollList gives those rails the extra height that line needs.
              _itemTitle("Manga trending", mangaTrendingScrollController),
              _scrollList(widget.mainNavProvider.mangaTrendingList, mangaTrendingScrollController),
              _itemTitle("Manga popular", mangaPopularScrollController),
              _scrollList(widget.mainNavProvider.mangaPopularList, mangaPopularScrollController),
              footSpace(),
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

  Widget _unavailableLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: appTheme.textSubColor,
          fontFamily: "NunitoSans",
          fontSize: 14,
        ),
      ),
    );
  }

  /// Shown when every Discover request failed.
  ///
  /// The rails are all empty in that case, so without this the page is just
  /// spinners that never resolve. A failed fetch is not the same as a slow one,
  /// and the difference is worth saying out loud.
  Widget _discoverErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(top: 25, left: 20, right: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: appTheme.accentColor.withAlpha(120)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: appTheme.accentColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Couldn't reach AniList",
                  style: TextStyle(
                    color: appTheme.textMainColor,
                    fontFamily: "NotoSans",
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  "The metadata service may be temporarily unavailable. Your connection is fine.",
                  style: TextStyle(
                    color: appTheme.textSubColor,
                    fontFamily: "NunitoSans",
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => widget.mainNavProvider.loadDiscoverItems(),
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

  PageView _trendingAnimesPageView() {
    return PageView.builder(
        pageSnapping: true,
        controller: _pageController,
        allowImplicitScrolling: true,
        onPageChanged: (page) async {
          currentPage = page;
          await pageTimeout();
        },
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final trendingList = widget.mainNavProvider.trendingList;
          final moddedIndex = index % trendingList.length;
          final titles = trendingList[moddedIndex].title;
          final title = titles['english'] ?? titles['romaji'] ?? '';
          final preferNative = currentUserSettings?.nativeTitle ?? false;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => Info(
                    id: trendingList[moddedIndex].id,
                  ),
                ),
              );
            },
            child: Container(
              child: Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  Container(
                    width: double.infinity,
                    child: ClipRRect(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Image.network(
                          trendingList[moddedIndex].banner ?? trendingList[moddedIndex].cover,
                          alignment: Alignment((index - page).clamp(-1, 1).toDouble(), 1),
                          opacity: AlwaysStoppedAnimation(0.5),
                          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                            if (wasSynchronouslyLoaded) return child;
                            return AnimatedOpacity(
                              opacity: frame == null ? 0 : 1,
                              duration: Duration(milliseconds: 150),
                              child: child,
                            );
                          },
                          height: 360,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    // ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(left: 20.0, top: MediaQuery.of(context).padding.top + 50),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            trendingList[moddedIndex].cover,
                            height: 170,
                            width: 120,
                          ),
                        ),
                        // The text block keeps its 250px width where there is
                        // room but shrinks on narrow phones instead of
                        // overflowing the row.
                        Flexible(
                          child: Container(
                            padding: EdgeInsets.only(left: 10, right: 10),
                            width: 250,
                            child: Column(
                              // mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: Text(
                                    preferNative ? titles['native'] ?? title : title,
                                    style: TextStyle(
                                      color: appTheme.textMainColor,
                                      fontFamily: 'NunitoSans',
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    maxLines: 2,
                                  ),
                                ),
                                Text(
                                  trendingList[moddedIndex].genres.join(', '),
                                  style: TextStyle(
                                      color: appTheme.textMainColor.withAlpha(145),
                                      fontFamily: 'NunitoSans',
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        color: appTheme.textMainColor,
                                        size: 20,
                                      ),
                                      Text(
                                        "${trendingList[moddedIndex].rating != null ? trendingList[moddedIndex].rating! / 10 : '??'}",
                                        style:
                                            TextStyle(color: appTheme.textMainColor, fontFamily: "Rubik", fontSize: 17),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
  }

  Container _scrollList(List<AnimeCard> list, ScrollController controller) {
    final firstCard = list.firstOrNull;
    final isMobile = firstCard?.isMobile ?? true;
    final hasSubText = list.any((card) => card.subText != null);

    // A mobile card is a 160px cover, its 10px bottom margin and a two-line
    // title, which the 220 rail is sized for. Cards that carry a subText (the
    // manga rails' format label) need one more line. Without it the label is
    // clipped on Android, where the rail is 220; the non-mobile 265 rail has
    // room for it already.
    final double height = isMobile ? (hasSubText ? 245.0 : 220.0) : 265.0;

    return Container(
      height: height,
      padding: EdgeInsets.only(left: 10, right: 10),
      child: list.length > 0
          ? ListView.builder(
              controller: controller,
              padding: EdgeInsets.zero,
              itemCount: list.length,
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) => list[index],
            )
          : Center(
              child: widget.mainNavProvider.discoverDataLoaded || widget.mainNavProvider.discoverError
                  ? _unavailableLabel("Nothing to show here right now")
                  : CircularProgressIndicator(
                      color: appTheme.accentColor,
                    ),
            ),
    );
  }

  Container _itemTitle(String title, ScrollController controller) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(top: 25, left: 25, right: 25, bottom: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: basicTextStyle("Rubik", 20),
          ),
          if (Platform.isWindows || Platform.isLinux) ScrollingList.scrollButtons(controller) else SizedBox.shrink()
        ],
      ),
    );
  }

  TextStyle basicTextStyle(String? family, double? size) {
    return TextStyle(
      color: appTheme.textMainColor,
      fontFamily: family ?? 'NotoSans',
      fontSize: size ?? 15,
    );
  }

  @override
  void dispose() {
    super.dispose();
    _pageController.dispose();
    if (timer != null && timer!.isActive) timer?.cancel();
  }
}
