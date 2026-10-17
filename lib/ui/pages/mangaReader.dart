import 'dart:async';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/data/reading.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:flutter/material.dart';

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
/// chapter (see [_ReaderProgressBar] and [_chapterButton]).
///
/// Everything that is *not* configurable stays deliberately plain: no
/// preloading, no page-turn animation. A reader that gets the pages right is
/// worth more than one that gets the gestures right.
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
/// prints and what the dots highlight, and [fraction] is how far through the
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
    load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pageController.dispose();
    _progress.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => _state = LoadingState.loading);
    try {
      final pages = await widget.provider.getPages(_chapter);
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

  /// Steers the bar from the strip.
  ///
  /// A fraction of the scroll extent, not a page index: a webtoon chapter is one
  /// tall image after another, so no scroll offset means "page 7". The page
  /// number derived from this is therefore approximate in scroll mode, which is
  /// why scroll mode prints a percentage instead.
  void _onScroll() {
    final position = _scrollController.position;
    final max = position.maxScrollExtent;
    final fraction = max <= 0 ? 0.0 : (position.pixels / max).clamp(0.0, 1.0);
    _progress.value = _ReaderProgress(_pageForFraction(fraction), fraction);
  }

  int _pageForFraction(double fraction) {
    if (_pages.isEmpty) return 0;
    return (fraction * (_pages.length - 1))
        .round()
        .clamp(0, _pages.length - 1);
  }

  /// Scrubbing the bar: go to a page.
  ///
  /// Paged mode jumps rather than animates. A drag produces a run of these, and
  /// an animated page turn per step would still be in flight when the next step
  /// arrives -- which is how a scrubber ends up lagging the finger on it.
  void _jumpToPage(int index) {
    if (_pages.isEmpty) return;
    final last = _pages.length - 1;
    final target = index.clamp(0, last);

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
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: appTheme.textMainColor),
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
          Expanded(child: body),
          // Not while loading or failed: there is nothing to scrub yet, and a bar
          // over an error message is two ways to do nothing.
          if (_state == LoadingState.loaded && _pages.isNotEmpty) _bottomBar(),
        ],
      ),
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
        return Image.network(
          page.imageUrl,
          headers: page.headers,
          fit: BoxFit.fitWidth,
          width: double.infinity,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(),
          errorBuilder: (context, error, stackTrace) =>
              _pageError(page.index + 1),
        );
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
          // The trailing footer, not a page: keep the readout and the dots on the
          // last real page rather than a page that does not exist.
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
        final image = Image.network(
          page.imageUrl,
          headers: page.headers,
          fit: BoxFit.contain,
          width: double.infinity,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(),
          errorBuilder: (context, error, stackTrace) =>
              _pageError(page.index + 1),
        );
        // Only wrapped when zoom is on. InteractiveViewer claims scale gestures,
        // and paying that cost in the common case buys nothing.
        return _zoom
            ? InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(child: image),
              )
            : Center(child: image);
      },
    );
  }

  /// The bar the chapter is steered from: a scrubber over its pages, where you
  /// are in the chapter, and an arrow to each neighbouring chapter.
  Widget _bottomBar() {
    return Container(
      color: appTheme.backgroundSubColor,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: Row(
        children: [
          _chapterButton(
            icon: Icons.skip_previous_rounded,
            chapter: _previousChapter,
            tooltip: "Previous chapter",
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReaderProgressBar(
                  pageCount: _pages.length,
                  progress: _progress,
                  onChanged: _jumpToPage,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: ValueListenableBuilder<_ReaderProgress>(
                    valueListenable: _progress,
                    builder: (context, value, child) => Text(
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
                ),
              ],
            ),
          ),
          _chapterButton(
            icon: Icons.skip_next_rounded,
            chapter: _nextChapter,
            tooltip: "Next chapter",
          ),
        ],
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
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: appTheme.backgroundColor,
      showDragHandle: true,
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

  /// A plain settings view: three choices, one per line.
  Widget _settingsSheet(VoidCallback refreshSheet) {
    final paged = _paged;

    Future<void> apply(UserPreferencesModal prefs) async {
      await UserPreferences.saveUserPreferences(prefs);
      refreshSheet();
      if (mounted) setState(() {});
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Reader",
              style: TextStyle(
                fontFamily: "Rubik",
                fontSize: 20,
                color: appTheme.textMainColor,
              ),
            ),
            _groupLabel("Layout"),
            _option(
              label: "Scroll",
              hint: "Continuous vertical strip.",
              selected: !paged,
              enabled: true,
              onTap: () => apply(
                UserPreferencesModal(mangaReaderLayout: mangaReaderLayoutScroll),
              ),
            ),
            _option(
              label: "Pages",
              hint: "One page at a time, swiped.",
              selected: paged,
              enabled: true,
              onTap: () => apply(
                UserPreferencesModal(mangaReaderLayout: mangaReaderLayoutPaged),
              ),
            ),
            _groupLabel("Reading direction"),
            _option(
              label: "Left to right",
              hint: paged ? null : "Applies to Pages.",
              selected: !_rightToLeft,
              enabled: paged,
              onTap: () => apply(UserPreferencesModal(mangaReaderDirection: 'ltr')),
            ),
            _option(
              label: "Right to left",
              hint: paged ? null : "Applies to Pages.",
              selected: _rightToLeft,
              enabled: paged,
              onTap: () => apply(UserPreferencesModal(mangaReaderDirection: 'rtl')),
            ),
            _groupLabel("Zoom"),
            _option(
              label: "Off",
              hint: paged ? null : "Applies to Pages.",
              selected: !_zoom,
              enabled: paged,
              onTap: () => apply(UserPreferencesModal(mangaReaderZoom: false)),
            ),
            _option(
              label: "On",
              hint: paged ? null : "Applies to Pages.",
              selected: _zoom,
              enabled: paged,
              onTap: () => apply(UserPreferencesModal(mangaReaderZoom: true)),
            ),
          ],
        ),
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

  /// One selectable line. Disabled rather than hidden, so the sheet does not
  /// reflow under the user's finger when the layout changes.
  Widget _option({
    required String label,
    required String? hint,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: "NotoSans",
                        fontSize: 15,
                        color: appTheme.textMainColor,
                      ),
                    ),
                    if (hint != null)
                      Text(
                        hint,
                        style: TextStyle(
                          fontFamily: "NotoSans",
                          fontSize: 12,
                          color: appTheme.textSubColor,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_rounded,
                  color: appTheme.accentColor,
                ),
            ],
          ),
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

/// The scrubber: a track with one dot per page, draggable and tappable.
///
/// A dot per page rather than a Material [Slider] because a slider's thumb is a
/// single position, and this control's whole point is to show how many pages
/// there are and which of them are behind you. Past [_maxDots] pages dots stop
/// being readable -- at sixty pages on a phone they are a dotted line, not a
/// count -- so they collapse into a plain progress track and the line below the
/// bar carries the numbers instead.
///
/// Painted rather than composed from widgets: at up to [_maxDots] dots, a Row of
/// containers would be sixty layout nodes rebuilt on every scroll frame, and a
/// canvas is one.
class _ReaderProgressBar extends StatelessWidget {
  final int pageCount;
  final ValueListenable<_ReaderProgress> progress;
  final ValueChanged<int> onChanged;

  const _ReaderProgressBar({
    required this.pageCount,
    required this.progress,
    required this.onChanged,
  });

  /// Above this, one dot per page is denser than the eye can count.
  static const int _maxDots = 24;

  /// Horizontal room the end dots need so they are not clipped -- and so the
  /// position under the finger maps to the dot under the finger.
  static const double _edgeInset = 6;

  /// Taller than the ink on purpose: a 6px dot is not a touch target, and a
  /// scrubber you cannot reliably land on is worse than no scrubber.
  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    final count = pageCount < 1 ? 1 : pageCount;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final usable = (width - _edgeInset * 2).clamp(1.0, width);

          void report(Offset local) {
            final t = ((local.dx - _edgeInset) / usable).clamp(0.0, 1.0);
            onChanged((t * (count - 1)).round());
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => report(details.localPosition),
            onHorizontalDragStart: (details) => report(details.localPosition),
            onHorizontalDragUpdate: (details) => report(details.localPosition),
            child: ValueListenableBuilder<_ReaderProgress>(
              valueListenable: progress,
              builder: (context, value, child) => CustomPaint(
                size: Size(width, _height),
                painter: _ReaderProgressPainter(
                  pageCount: count,
                  current: value.page.clamp(0, count - 1),
                  fraction: value.fraction.clamp(0.0, 1.0),
                  showDots: count <= _maxDots,
                  edgeInset: _edgeInset,
                  accent: appTheme.accentColor,
                  track: appTheme.textSubColor.withValues(alpha: 0.25),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReaderProgressPainter extends CustomPainter {
  final int pageCount;
  final int current;
  final double fraction;
  final bool showDots;
  final double edgeInset;
  final Color accent;
  final Color track;

  const _ReaderProgressPainter({
    required this.pageCount,
    required this.current,
    required this.fraction,
    required this.showDots,
    required this.edgeInset,
    required this.accent,
    required this.track,
  });

  static const double _trackHeight = 6;
  static const double _dotRadius = 3.5;
  static const double _currentDotRadius = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final usable = (size.width - edgeInset * 2).clamp(1.0, size.width);
    final last = pageCount - 1;

    if (!showDots) {
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          edgeInset,
          centerY - _trackHeight / 2,
          usable,
          _trackHeight,
        ),
        const Radius.circular(_trackHeight / 2),
      );
      canvas.drawRRect(rrect, Paint()..color = track);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            edgeInset,
            centerY - _trackHeight / 2,
            usable * fraction,
            _trackHeight,
          ),
          const Radius.circular(_trackHeight / 2),
        ),
        Paint()..color = accent,
      );
      return;
    }

    double dx(int index) =>
        edgeInset + (last <= 0 ? usable / 2 : usable * index / last);

    // The connecting line goes down first, so every dot sits on top of it: the
    // part behind you in the accent colour, the part ahead of you in the track
    // colour. That, plus the dot weights, is what makes the bar readable at a
    // glance without a number.
    if (last > 0) {
      final line = Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(dx(0), centerY),
        Offset(dx(current), centerY),
        line..color = accent,
      );
      canvas.drawLine(
        Offset(dx(current), centerY),
        Offset(dx(last), centerY),
        line..color = track,
      );
    }

    for (var i = 0; i < pageCount; i++) {
      final isCurrent = i == current;
      canvas.drawCircle(
        Offset(dx(i), centerY),
        isCurrent ? _currentDotRadius : _dotRadius,
        Paint()
          ..color = isCurrent
              ? accent
              : (i < current ? accent.withValues(alpha: 0.5) : track),
      );
    }
  }

  @override
  bool shouldRepaint(_ReaderProgressPainter old) =>
      old.pageCount != pageCount ||
      old.current != current ||
      old.fraction != fraction ||
      old.showDots != showDots ||
      old.accent != accent ||
      old.track != track;
}
