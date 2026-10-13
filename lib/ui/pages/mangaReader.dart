import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:flutter/material.dart';

/// Vertical-scroll reader for one chapter.
///
/// Pages come from the installed manga extension. The images themselves are
/// fetched by the app (`Image.network`), not through the sandbox -- the same way
/// the player fetches a stream URL -- so a page host never has to appear in a
/// provider's `allowedHosts`.
///
/// Deliberately plain: no zoom, no preloading, no page-turn animation. A reader
/// that gets the pages right is worth more than one that gets the gestures right.
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => _state = LoadingState.loading);
    try {
      final pages = await widget.provider.getPages(widget.chapter);
      if (!mounted) return;
      setState(() {
        _pages = pages;
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
            : _pagesView(),
      },
    );
  }

  Widget _pagesView() {
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
