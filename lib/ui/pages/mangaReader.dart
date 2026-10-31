import 'dart:async';
import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/data/reading.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/manga/mangaDownloader.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reader for one chapter.
///
/// Pages come from the installed manga extension. The images themselves are
/// fetched by the app (`Image.network`), not through the sandbox -- the same way
/// the player fetches a stream URL -- so a page host never has to appear in a
/// provider's `allowedHosts`.
///
/// Two layouts, chosen in the settings sheet in the app bar:
///
///   * **scroll** (default) -- one continuous vertical strip. This is what the
///     reader did before the settings existed, so a stored preference written
///     by an older build, or no preference at all, lands here.
///   * **pages** -- one page at a time, swiped. Direction and zoom apply here.
///
/// Either way the chapter is steered from the bar along the bottom: a scrubber
/// over its pages, the position in the chapter, and an arrow to each neighbouring
/// chapter (see [_bottomBar] and [_chapterButton]).
///
/// The page is steered from a Material slider plus two chapter arrows, and the
/// settings live in a Material 3 sheet. Reading starts immersive on a phone;
/// the button in the app bar (or the floating one while immersive) toggles the
/// chrome. Everything that is *not* configurable stays deliberately plain: no
/// preloading, no page-turn animation.
class MangaReaderPage extends StatefulWidget {
  final MangaDetails manga;
  final MangaChapter chapter;
  final MangaChapterProvider provider;

  /// The other chapters of [manga], in **reading order** (oldest first), so the
  /// two arrows in the bottom bar step through the story: index + 1 is always
  /// the chapter after this one, whatever order the details page is displaying
  /// its own list in.
  ///
  /// May be empty when the reader is opened without a list. The arrows are then
  /// drawn disabled rather than dropped, so the bar keeps its shape and the
  /// scrubber does not shift sideways.
  final List<MangaChapter> chapters;

  const MangaReaderPage({
    super.key,
    required this.manga,
    required this.chapter,
    required this.provider,
    this.chapters = const <MangaChapter>[],
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

/// Where the reader is in the chapter.
///
/// One value carrying both readings of "where", because both are wanted in the
/// same rebuild: [page] is the nearest page index, which is what a counter
/// prints and what the slider sits over, and [fraction] is how far through the
/// chapter that is, which is the only honest readout for a continuous strip.
/// A strip has no discrete current page, and pretending it does is how a counter
/// ends up disagreeing with the screen.
class _ReaderProgress {
  final int page;
  final double fraction;

  const _ReaderProgress(this.page, this.fraction);
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  List<MangaPage> _pages = const <MangaPage>[];
  LoadingState _state = LoadingState.loading;

  /// The chapter on screen. Starts as [MangaReaderPage.chapter] and changes when
  /// an arrow is tapped, which is why it is state and not `widget.chapter`.
  late MangaChapter _chapter;

  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();

  /// Only the bottom bar listens to this. Scrolling a chapter must not rebuild
  /// the strip the user is scrolling: `setState` here would rebuild every visible
  /// page once per frame, and the images in them are the one thing on this screen
  /// expensive enough for that to show.
  final ValueNotifier<_ReaderProgress> _progress =
      ValueNotifier<_ReaderProgress>(const _ReaderProgress(0, 0));

  /// Whether the system bars are hidden. Reading starts immersive on a phone
  /// and the dedicated button in the app bar / the floating one toggles it.
  bool _fullscreen = false;

  /// Immersive mode is an Android/iOS concept. Desktops keep their chrome so
  /// the window controls stay reachable.
  bool get _immersiveSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  // Read straight from the global rather than cached in a field: the settings
  // sheet writes through UserPreferences.saveUserPreferences, which replaces
  // that global, and a cached copy would go stale the moment it did.
  bool get _paged => userPreferences?.mangaReaderPaged ?? false;
  bool get _rightToLeft => userPreferences?.mangaReaderRightToLeft ?? false;
  bool get _zoom => userPreferences?.mangaReaderZoom ?? false;

  /// Where the chapter on screen sits in [MangaReaderPage.chapters], or -1 when
  /// that list does not contain it.
  int get _chapterIndex =>
      widget.chapters.indexWhere((chapter) => chapter.id == _chapter.id);

  MangaChapter? get _previousChapter {
    final index = _chapterIndex;
    return index > 0 ? widget.chapters[index - 1] : null;
  }

  MangaChapter? get _nextChapter {
    final index = _chapterIndex;
    return index >= 0 && index < widget.chapters.length - 1
        ? widget.chapters[index + 1]
        : null;
  }

  @override
  void initState() {
    super.initState();
    _chapter = widget.chapter;
    _scrollController.addListener(_onScroll);
    if (_immersiveSupported) {
      _fullscreen = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    _progress.dispose();
    if (_immersiveSupported) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  /// Shows or hides the system bars and this page's own app bar / bottom bar.
  Future<void> _setFullscreen(bool value) async {
    if (_fullscreen == value) return;
    setState(() => _fullscreen = value);
    if (_immersiveSupported) {
      await SystemChrome.setEnabledSystemUIMode(
        value ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  Future<void> load() async {
    setState(() => _state = LoadingState.loading);
    try {
      final pages = await _chapterPages();
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _state = LoadingState.loaded;
      });
      // Reset after the pages land: both controllers are positioned against a
      // populated list, and the bar needs a page count before it can render.
      _progress.value = const _ReaderProgress(0, 0);
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    } catch (err) {
      Logs.app.log("Error loading manga pages: $err");
      if (!mounted) return;
      setState(() => _state = LoadingState.error);
    }
  }

  /// The chapter's pages, preferring the ones already saved to disk.
  ///
  /// A downloaded chapter is read from its download directory rather than
  /// re-fetched: the download is what created those files, and going back over
  /// the network would leave the saved chapter unread. Nothing on disk means
  /// the online provider is consulted as before.
  Future<List<MangaPage>> _chapterPages() async {
    final saved = await MangaDownloader.isDownloaded(
      widget.manga.summary.id,
      widget.manga.title,
      _chapter,
    );
    if (saved) {
      final local = await MangaDownloader.localPages(
        widget.manga.summary.id,
        widget.manga.title,
        _chapter,
      );
      if (local.isNotEmpty) return local;
    }
    return widget.provider.getPages(_chapter);
  }

  /// Steers the bar from the strip.
  ///
  /// A fraction of the scroll extent, not a page index: a webtoon chapter is one
  /// tall image after another, so no scroll offset means "page 7". The page
  /// number derived from this is therefore approximate in scroll mode, which is
  /// why scroll mode prints a percentage instead.
  void _onScroll() {
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    final fraction =
        max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0).toDouble();
    _progress.value = _ReaderProgress(_pageForFraction(fraction), fraction);
  }

  int _pageForFraction(double fraction) {
    if (_pages.isEmpty) return 0;
    return (fraction * (_pages.length - 1))
        .round()
        .clamp(0, _pages.length - 1)
        .toInt();
  }

  /// Scrubbing the bar: go to a page.
  ///
  /// Paged mode jumps rather than animates. A drag produces a run of these, and
  /// an animated page turn per step would still be in flight when the next step
  /// arrives -- which is how a scrubber ends up lagging the finger on it.
  void _jumpToPage(int index) {
    if (_pages.isEmpty) return;
    final last = _pages.length - 1;
    final target = index.clamp(0, last).toInt();

    if (_paged) {
      if (_pageController.hasClients) _pageController.jumpToPage(target);
      return;
    }
    if (last <= 0 || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    _scrollController.jumpTo(max * (target / last));
  }

  /// Steps to a chapter and loads it in place.
  ///
  /// In place, not by pushing another reader: a stack of readers would make one
  /// back tap walk the chapters one at a time, and the page controllers, the
  /// progress notifier and the settings sheet would each exist once per chapter
  /// visited.
  Future<void> _goToChapter(MangaChapter chapter) async {
    setState(() {
      _chapter = chapter;
      _pages = const <MangaPage>[];
    });

    // Recorded before the pages load, for the same reason the details page
    // records on tap: the user asked to read this chapter, and the Continue
    // Reading rail should not depend on the fetch succeeding to know that.
    unawaited(
      storeReading(
        id: widget.manga.summary.id,
        title: widget.manga.title,
        cover: widget.manga.cover,
        rating: widget.manga.summary.rating,
        totalChapters: widget.manga.totalChapters,
        // A chapter with no number is a one-shot; 1 stands in so the rail still
        // renders "1 / n" rather than "~ / n".
        chapterNumber: chapter.number ?? 1,
      ),
    );

    await load();
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_state) {
      LoadingState.loading => Center(
          child: CircularProgressIndicator(color: appTheme.accentColor),
        ),
      LoadingState.error => _message(
          "Couldn't load pages from ${widget.provider.providerName}.",
          retry: true,
        ),
      _ => _pages.isEmpty
          ? _message(
              "${widget.provider.providerName} returned no pages for this chapter.",
            )
          : (_paged ? _pagedView() : _scrollView()),
    };

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      // Immersive reading hides the chrome; the floating button below brings it
      // back without leaving the page. Everything else stays a normal Material
      // app bar so back navigation and settings are where they are everywhere.
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: appTheme.backgroundColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              iconTheme: IconThemeData(color: appTheme.textMainColor),
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chapter.displayTitle,
                    style: TextStyle(
                      fontFamily: "Rubik",
                      fontSize: 17,
                      color: appTheme.textMainColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.manga.title,
                    style: TextStyle(
                      fontFamily: "NotoSans",
                      fontSize: 12,
                      color: appTheme.textSubColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: "Fullscreen",
                  onPressed: _immersiveSupported ? () => _setFullscreen(true) : null,
                  icon: Icon(
                    Icons.fullscreen_rounded,
                    color: _immersiveSupported
                        ? appTheme.textMainColor
                        : appTheme.textSubColor.withValues(alpha: 0.4),
                  ),
                ),
                IconButton(
                  tooltip: "Reader settings",
                  onPressed: _openReaderSettings,
                  icon: Icon(
                    Icons.settings_outlined,
                    color: appTheme.textMainColor,
                  ),
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: body),
                if (_fullscreen)
                  Positioned(top: 8, right: 8, child: _immersiveToggle()),
              ],
            ),
          ),
          // Not while loading or failed: there is nothing to scrub yet, and a bar
          // over an error message is two ways to do nothing.
          if (!_fullscreen && _state == LoadingState.loaded && _pages.isNotEmpty) _bottomBar(),
        ],
      ),
    );
  }

  /// The only control visible while reading immersive: tapping it restores the
  /// app bar and the bottom bar.
  Widget _immersiveToggle() {
    return SafeArea(
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: "Show controls",
          onPressed: () => _setFullscreen(false),
          icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white),
        ),
      ),
    );
  }

  /// One page image.
  ///
  /// A downloaded page is a `file://` URI the app wrote itself; an online page
  /// is an http(s) URL. `Image.network` cannot fetch a `file://` URL, so local
  /// pages have to go through `Image.file`.
  Widget _pageImage(MangaPage page, {BoxFit fit = BoxFit.fitWidth}) {
    final uri = Uri.tryParse(page.imageUrl);
    if (uri != null && uri.isScheme('file')) {
      return Image.file(
        File.fromUri(uri),
        fit: fit,
        width: double.infinity,
      );
    }
    return Image.network(
      page.imageUrl,
      headers: page.headers,
      fit: fit,
      width: double.infinity,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(),
      errorBuilder: (context, error, stackTrace) =>
          _pageError(page.index + 1),
    );
  }

  /// One continuous vertical strip. The original reader.
  Widget _scrollView() {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: _pages.length + 1,
      itemBuilder: (context, position) {
        if (position == _pages.length) return _footer();
        final page = _pages[position];
        return _pageImage(page);
      },
    );
  }

  /// One page at a time, swiped sideways. Zoom belongs here (see the note on
  /// [UserPreferencesModal.mangaReaderZoom]) and so does page order.
  ///
  /// `PageView.reverse` carries right-to-left, rather than the page list being
  /// reversed before it is handed to the pager. A reversed list puts the last
  /// page of the chapter at index 0, so the reader would open on the last page
  /// and every counter would count from the wrong end; reversing the axis leaves
  /// index 0 meaning page 1 in both directions.
  Widget _pagedView() {
    return PageView.builder(
      controller: _pageController,
      reverse: _rightToLeft,
      itemCount: _pages.length + 1,
      onPageChanged: (index) {
        final last = _pages.length - 1;
        if (index >= _pages.length) {
          // The trailing footer, not a page: keep the readout and the slider on
          // the last real page rather than a page that does not exist.
          _progress.value = _ReaderProgress(last, 1);
          return;
        }
        _progress.value = _ReaderProgress(
          index,
          last <= 0 ? 0 : index / last,
        );
      },
      itemBuilder: (context, position) {
        if (position == _pages.length) {
          return SingleChildScrollView(child: _footer());
        }
        final page = _pages[position];
        final image = _pageImage(page, fit: BoxFit.contain);
        // Only wrapped when zoom is on. InteractiveViewer claims scale and pan
        // gestures, and paying that cost in the common case buys nothing.
        return _zoom
            ? _ZoomablePage(
                // A key per page gives every page its own transformation
                // controller, so a zoomed-in page never leaks its scale onto
                // the next one.
                key: ValueKey<int>(page.index),
                child: Center(child: image),
              )
            : Center(child: image);
      },
    );
  }

  /// The bar the chapter is steered from: a Material slider over its pages,
  /// where you are in the chapter, and an arrow to each neighbouring chapter.
  ///
  /// A slider rather than the custom dot track this reader used to paint: the
  /// reader is meant to feel like the rest of the app (and like Kotatsu-style
  /// readers), and a Material slider already handles dragging, keyboard input
  /// and accessibility.
  Widget _bottomBar() {
    return Material(
      color: appTheme.backgroundSubColor,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _chapterButton(
                icon: Icons.skip_previous_rounded,
                chapter: _previousChapter,
                tooltip: "Previous chapter",
              ),
              Expanded(
                child: ValueListenableBuilder<_ReaderProgress>(
                  valueListenable: _progress,
                  builder: (context, value, child) {
                    final last = _pages.length - 1;
                    final fraction =
                        value.fraction.clamp(0.0, 1.0).toDouble();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: appTheme.accentColor,
                            inactiveTrackColor:
                                appTheme.textSubColor.withValues(alpha: 0.25),
                            thumbColor: appTheme.accentColor,
                            overlayColor:
                                appTheme.accentColor.withValues(alpha: 0.12),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7,
                            ),
                          ),
                          child: Slider(
                            value: fraction,
                            // In a strip the fraction is continuous, so the
                            // slider is the honest readout there; in paged mode
                            // the same value is derived from the page index.
                            onChanged: last <= 0
                                ? null
                                : (scaled) => _jumpToPage(
                                      (scaled * last).round(),
                                    ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            _paged
                                ? "${value.page + 1} / ${_pages.length}"
                                : "${(value.fraction * 100).round()}%  ·  "
                                    "${_pages.length} pages",
                            style: TextStyle(
                              fontFamily: "NotoSans",
                              fontSize: 12,
                              color: appTheme.textSubColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              _chapterButton(
                icon: Icons.skip_next_rounded,
                chapter: _nextChapter,
                tooltip: "Next chapter",
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One chapter arrow. Disabled at the ends of the list rather than hidden, so
  /// the scrubber does not jump sideways when a reader reaches the last chapter
  /// of a series.
  Widget _chapterButton({
    required IconData icon,
    required MangaChapter? chapter,
    required String tooltip,
  }) {
    return IconButton(
      tooltip: chapter == null ? null : tooltip,
      onPressed: chapter == null ? null : () => _goToChapter(chapter),
      iconSize: 30,
      color: appTheme.textMainColor,
      disabledColor: appTheme.textSubColor.withValues(alpha: 0.3),
      icon: Icon(icon),
    );
  }

  Future<void> _openReaderSettings() async {
    // Leave immersive mode for the sheet: a modal over hidden system bars puts
    // the drag handle under the gesture bar on gesture-navigation phones.
    await _setFullscreen(false);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: appTheme.modalSheetBackgroundColor,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        // The sheet has to repaint on its own, or a tap would only take effect
        // once it was closed and reopened.
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return _settingsSheet(() => setSheetState(() {}));
          },
        );
      },
    );
  }

  /// Reader settings, built from Material controls.
  ///
  /// Layout and direction are mutually exclusive choices, so they are
  /// [SegmentedButton]s rather than rows of tappable text; zoom is a boolean,
  /// so it is a [SwitchListTile]. Options that do not apply to the current
  /// layout stay visible but disabled, so the sheet does not reflow under the
  /// user's finger when the layout changes.
  Widget _settingsSheet(VoidCallback refreshSheet) {
    final paged = _paged;

    Future<void> apply(UserPreferencesModal prefs) async {
      await UserPreferences.saveUserPreferences(prefs);
      refreshSheet();
      if (mounted) setState(() {});
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: appTheme.accentColor),
              const SizedBox(width: 10),
              Text(
                "Reader",
                style: TextStyle(
                  fontFamily: "Rubik",
                  fontSize: 20,
                  color: appTheme.textMainColor,
                ),
              ),
            ],
          ),
          _groupLabel("Layout"),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: _segmentedStyle(),
            segments: const [
              ButtonSegment<String>(
                value: mangaReaderLayoutScroll,
                icon: Icon(Icons.view_agenda_outlined),
                label: Text("Scroll"),
              ),
              ButtonSegment<String>(
                value: mangaReaderLayoutPaged,
                icon: Icon(Icons.auto_stories_outlined),
                label: Text("Pages"),
              ),
            ],
            selected: {paged ? mangaReaderLayoutPaged : mangaReaderLayoutScroll},
            onSelectionChanged: (selection) => apply(
              UserPreferencesModal(mangaReaderLayout: selection.first),
            ),
          ),
          _groupLabel("Reading direction"),
          Opacity(
            opacity: paged ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !paged,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: _segmentedStyle(),
                segments: const [
                  ButtonSegment<String>(
                    value: 'ltr',
                    icon: Icon(Icons.format_textdirection_l_to_r),
                    label: Text("Left to right"),
                  ),
                  ButtonSegment<String>(
                    value: 'rtl',
                    icon: Icon(Icons.format_textdirection_r_to_l),
                    label: Text("Right to left"),
                  ),
                ],
                selected: {_rightToLeft ? 'rtl' : 'ltr'},
                onSelectionChanged: (selection) => apply(
                  UserPreferencesModal(mangaReaderDirection: selection.first),
                ),
              ),
            ),
          ),
          if (!paged) _hint("Applies to Pages."),
          _groupLabel("Zoom"),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: appTheme.accentColor,
            title: Text(
              "Pinch to zoom",
              style: TextStyle(
                fontFamily: "NotoSans",
                fontSize: 15,
                color: appTheme.textMainColor,
              ),
            ),
            subtitle: Text(
              paged
                  ? "Double tap to zoom in, pinch to pan, double tap again to reset."
                  : "Applies to Pages.",
              style: TextStyle(
                fontFamily: "NotoSans",
                fontSize: 12,
                color: appTheme.textSubColor,
              ),
            ),
            value: _zoom,
            onChanged: paged
                ? (value) => apply(UserPreferencesModal(mangaReaderZoom: value))
                : null,
          ),
        ],
      ),
    );
  }

  /// Material 3 segmented-control styling, keyed to the app's own palette so
  /// the sheet matches the reader instead of the seed colour scheme.
  ButtonStyle _segmentedStyle() {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? appTheme.accentColor
            : Colors.transparent,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? appTheme.onAccent
            : appTheme.textMainColor,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: appTheme.textSubColor.withValues(alpha: 0.35)),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _groupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: "NotoSans",
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: appTheme.textSubColor,
        ),
      ),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: "NotoSans",
          fontSize: 12,
          color: appTheme.textSubColor,
        ),
      ),
    );
  }

  Widget _footer() {
    return Padding(
      padding: EdgeInsets.only(
        top: 25,
        bottom: MediaQuery.of(context).padding.bottom + 32,
      ),
      child: Column(
        children: [
          divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Text(
              "End of ${_chapter.displayTitle} — ${_pages.length} pages "
              "from ${widget.provider.providerName}",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: "NotoSans",
                fontSize: 13,
                color: appTheme.textSubColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: 420,
      color: appTheme.backgroundSubColor,
      child: Center(
        child: CircularProgressIndicator(color: appTheme.accentColor),
      ),
    );
  }

  Widget _pageError(int pageNumber) {
    return Container(
      height: 220,
      color: appTheme.backgroundSubColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('lib/assets/images/broken_heart.png', height: 60),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                "Page $pageNumber couldn't load",
                style: TextStyle(
                  fontFamily: "NotoSans",
                  fontSize: 13,
                  color: appTheme.textSubColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String message, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              "lib/assets/images/ghost.png",
              color: const Color.fromARGB(255, 80, 80, 80),
            ),
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
            if (retry) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: load,
                child: Text(
                  "Try again",
                  style: TextStyle(
                    color: appTheme.accentColor,
                    fontFamily: "NotoSans",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Center divider() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width / 2,
        margin: const EdgeInsets.only(top: 20, bottom: 15),
        height: 6,
        decoration: BoxDecoration(
          color: appTheme.accentColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// A single page that can be pinched and double-tapped to zoom.
///
/// Each page owns its [TransformationController], so moving to another page
/// starts unzoomed instead of inheriting the previous page's matrix. At 1x the
/// viewer lets horizontal drags through to the surrounding [PageView]; once
/// zoomed in, the same drags pan the image, which is what a reader expects.
class _ZoomablePage extends StatefulWidget {
  final Widget child;

  const _ZoomablePage({super.key, required this.child});

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  static const double _doubleTapScale = 2.5;
  static const double _maxScale = 5;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    // Zoom around the tap point rather than the centre, so the detail the user
    // tapped is the detail they end up looking at.
    _controller.value = Matrix4.identity()
      ..translate(
        -position.dx * (_doubleTapScale - 1),
        -position.dy * (_doubleTapScale - 1),
      )
      ..scale(_doubleTapScale);
  }

  void _settle() {
    // Pinching below 1x would otherwise leave the page floating in a margin.
    if (_controller.value.getMaxScaleOnAxis() < 1.05) {
      _controller.value = Matrix4.identity();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1,
        maxScale: _maxScale,
        clipBehavior: Clip.hardEdge,
        boundaryMargin: const EdgeInsets.all(60),
        onInteractionEnd: (_) => _settle(),
        child: widget.child,
      ),
    );
  }
}
