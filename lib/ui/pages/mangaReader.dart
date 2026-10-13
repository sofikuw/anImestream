import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/data/preferences.dart';
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
/// Everything that is *not* configurable stays deliberately plain: no
/// preloading, no page-turn animation. A reader that gets the pages right is
/// worth more than one that gets the gestures right.
class MangaReaderPage extends StatefulWidget {
  final MangaDetails manga;
  final MangaChapter chapter;
  final MangaChapterProvider provider;

  const MangaReaderPage({
    super.key,
    required this.manga,
    required this.chapter,
    required this.provider,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  List<MangaPage> _pages = const <MangaPage>[];
  LoadingState _state = LoadingState.loading;

  final PageController _pageController = PageController();
  int _pageIndex = 0;

  // Read straight from the global rather than cached in a field: the settings
  // sheet writes through UserPreferences.saveUserPreferences, which replaces
  // that global, and a cached copy would go stale the moment it did.
  bool get _paged => userPreferences?.mangaReaderPaged ?? false;
  bool get _rightToLeft => userPreferences?.mangaReaderRightToLeft ?? false;
  bool get _zoom => userPreferences?.mangaReaderZoom ?? false;

  /// Pages in the order they are shown.
  ///
  /// Right-to-left only reverses paged mode. A vertical strip is read top to
  /// bottom in every language, so reversing it would be wrong rather than
  /// unhelpful.
  List<MangaPage> get _orderedPages =>
      _rightToLeft && _paged ? _pages.reversed.toList(growable: false) : _pages;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => _state = LoadingState.loading);
    try {
      final pages = await widget.provider.getPages(widget.chapter);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _pageIndex = 0;
        _state = LoadingState.loaded;
      });
    } catch (err) {
      Logs.app.log("Error loading manga pages: $err");
      if (!mounted) return;
      setState(() => _state = LoadingState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              widget.chapter.displayTitle,
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
      body: switch (_state) {
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
      },
    );
  }

  /// One continuous vertical strip. The original reader.
  Widget _scrollView() {
    return ListView.builder(
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
          errorBuilder: (context, error, stackTrace) => _pageError(page.index + 1),
        );
      },
    );
  }

  /// One page at a time, swiped sideways. Zoom belongs here (see the note on
  /// [UserPreferencesModal.mangaReaderZoom]) and so does page order.
  Widget _pagedView() {
    final pages = _orderedPages;
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: pages.length + 1,
          onPageChanged: (index) => setState(() => _pageIndex = index),
          itemBuilder: (context, position) {
            if (position == pages.length) {
              return SingleChildScrollView(child: _footer());
            }
            final page = pages[position];
            final image = Image.network(
              page.imageUrl,
              headers: page.headers,
              fit: BoxFit.contain,
              width: double.infinity,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _placeholder(),
              errorBuilder: (context, error, stackTrace) => _pageError(page.index + 1),
            );
            // Only wrapped when zoom is on. InteractiveViewer claims scale
            // gestures, and paying that cost in the common case buys nothing.
            return _zoom
                ? InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(child: image),
                  )
                : Center(child: image);
          },
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              padding: EdgeInsets.only(
                top: 6,
                bottom: MediaQuery.of(context).padding.bottom + 6,
              ),
              alignment: Alignment.center,
              color: appTheme.backgroundColor.withValues(alpha: 0.75),
              child: Text(
                _pageIndex >= pages.length
                    ? "End of chapter"
                    : "${_pageIndex + 1} / ${pages.length}",
                style: TextStyle(
                  fontFamily: "NotoSans",
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: appTheme.textMainColor,
                ),
              ),
            ),
          ),
        ),
      ],
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
              onTap: () => apply(UserPreferencesModal(mangaReaderLayout: mangaReaderLayoutScroll)),
            ),
            _option(
              label: "Pages",
              hint: "One page at a time, swiped.",
              selected: paged,
              enabled: true,
              onTap: () => apply(UserPreferencesModal(mangaReaderLayout: mangaReaderLayoutPaged)),
            ),
            _groupLabel("Reading direction"),
            _option(
              label: "Left to right",
              hint: paged ? null : "Applies to Pages.",
              selected: !_rightToLeft,
              enabled: paged,
              onTap: () => apply(const UserPreferencesModal(mangaReaderDirection: 'ltr')),
            ),
            _option(
              label: "Right to left",
              hint: paged ? null : "Applies to Pages.",
              selected: _rightToLeft,
              enabled: paged,
              onTap: () => apply(const UserPreferencesModal(mangaReaderDirection: 'rtl')),
            ),
            _groupLabel("Zoom"),
            _option(
              label: "Off",
              hint: paged ? null : "Applies to Pages.",
              selected: !_zoom,
              enabled: paged,
              onTap: () => apply(const UserPreferencesModal(mangaReaderZoom: false)),
            ),
            _option(
              label: "On",
              hint: paged ? null : "Applies to Pages.",
              selected: _zoom,
              enabled: paged,
              onTap: () => apply(const UserPreferencesModal(mangaReaderZoom: true)),
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
              "End of ${widget.chapter.displayTitle} — ${_pages.length} pages "
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
      child: Center(child: CircularProgressIndicator(color: appTheme.accentColor)),
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
