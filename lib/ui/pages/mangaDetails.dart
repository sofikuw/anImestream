import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/javascriptMangaProvider.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:animestream/ui/models/widgets/loader.dart';
import 'package:animestream/ui/pages/mangaReader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Manga details.
///
/// Deliberately mirrors `infoMobile.dart` -- the anime details page -- so the
/// two read as the same screen: banner with a faded cover card and a back
/// button on top, an action button (read instead of watch), the title centred
/// beneath it, then label/value rows, then Characters and Related.
///
/// AniList supplies all the metadata. Chapters and pages come from an installed
/// manga extension, or from [chapterProvider] when a caller supplies one.
class MangaDetailsPage extends StatefulWidget {
  final String id;

  /// Chapters and pages. Null until a manga extension is installed, which is
  /// what keeps the reader unavailable.
  final MangaChapterProvider? chapterProvider;

  const MangaDetailsPage({super.key, required this.id, this.chapterProvider});

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends State<MangaDetailsPage> {
  final AnilistManga _source = AnilistManga();

  MangaDetails? _details;
  LoadingState _state = LoadingState.loading;
  String? _error;

  List<MangaChapter> _chapters = [];
  LoadingState _chaptersState = LoadingState.loaded;

  /// Chapters and pages. Taken from the caller when one is supplied, otherwise
  /// discovered from an installed manga extension during [load].
  MangaChapterProvider? _provider;

  /// Which half of the page is showing. The anime page toggles between its
  /// info rows and its episode list; this toggles between the info rows and
  /// the chapter list, so "read" reveals the chapters to pick from.
  bool infoPage = true;

  @override
  void initState() {
    super.initState();
    _provider = widget.chapterProvider;
    load();
  }

  @override
  void dispose() {
    // Only a provider this page discovered itself is this page's to release;
    // one supplied by the caller belongs to the caller.
    if (widget.chapterProvider == null) {
      _provider?.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      _state = LoadingState.loading;
      _error = null;
    });

    try {
      final details = await _source.getDetails(widget.id);
      // An installed manga extension supplies the chapters and pages. Resolved
      // once per page, not once per chapter.
      final provider = _provider ?? await JavaScriptMangaProvider.firstInstalled();
      if (!mounted) return;
      setState(() {
        _details = details;
        _provider = provider;
        _state = LoadingState.loaded;
      });
      await loadChapters(details);
    } catch (err) {
      Logs.app.log("Error loading manga details: $err");
      if (!mounted) return;
      setState(() {
        _state = LoadingState.error;
        _error = err.toString();
      });
    }
  }

  Future<void> loadChapters(MangaDetails details) async {
    final provider = _provider;
    if (provider == null) return;

    setState(() => _chaptersState = LoadingState.loading);
    try {
      final chapters = await provider.getChapters(details);
      if (!mounted) return;
      setState(() {
        _chapters = chapters;
        _chaptersState = LoadingState.loaded;
      });
    } catch (err) {
      Logs.app.log("Error loading chapters: $err");
      if (!mounted) return;
      setState(() => _chaptersState = LoadingState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      // No AppBar: the anime page puts its own back button over the banner.
      body: switch (_state) {
        LoadingState.loading => Center(
            child: AnimeStreamLoading(color: appTheme.accentColor),
          ),
        LoadingState.error => _errorView(),
        _ => _detailsView(_details!),
      },
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('lib/assets/images/broken_heart.png', scale: 7.5),
          Padding(
            padding: const EdgeInsets.only(top: 15, left: 30, right: 30, bottom: 15),
            child: const Text(
              'oops! something went wrong',
              style: TextStyle(
                color: Colors.white,
                fontFamily: "NunitoSans",
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: appTheme.accentColor),
            child: Text(
              "Go Back",
              style: TextStyle(color: appTheme.backgroundColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsView(MangaDetails details) {
    return CustomScrollView(
      slivers: [
        SliverList.list(
          children: [
            _stack(details),
            Container(
              margin: EdgeInsets.only(top: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: appTheme.accentColor,
                        fixedSize: Size(135, 55),
                      ),
                      onPressed: () {
                        setState(() {
                          infoPage = !infoPage;
                        });
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            infoPage ? Icons.menu_book_rounded : Icons.info_rounded,
                            color: appTheme.onAccent,
                            size: 28,
                          ),
                          Text(
                            infoPage ? "read" : " info",
                            style: TextStyle(
                              color: appTheme.onAccent,
                              fontFamily: "Poppins",
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: EdgeInsets.only(top: 45),
              padding: EdgeInsets.only(left: 20, right: 20),
              alignment: Alignment.center,
              child: Text(
                details.title,
                style: TextStyle(
                  color: appTheme.textMainColor,
                  fontFamily: "NunitoSans",
                  fontSize: 25,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            AnimatedSwitcher(
              duration: Duration(milliseconds: 200),
              child: infoPage ? _infoItems(details) : _readItems(details),
            ),
          ],
        ),
      ],
    );
  }

  /// Banner, faded cover card, and the back button -- the same arrangement as
  /// `infoMobile._stack()`.
  Stack _stack(MangaDetails details) {
    final banner = details.banner ?? details.cover;
    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [Colors.transparent, appTheme.backgroundColor],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: [0.09, 0.23],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: Container(
            height: 270,
            width: double.infinity,
            child: Image.network(
              banner ?? '',
              fit: BoxFit.cover,
              opacity: AlwaysStoppedAnimation(0.6),
              errorBuilder: (context, error, stackTrace) => Container(
                color: appTheme.backgroundSubColor,
                child: Image.asset('lib/assets/images/broken_heart.png'),
              ),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: Duration(milliseconds: 300),
                  child: child,
                  curve: Curves.easeIn,
                );
              },
            ),
          ),
        ),
        if (details.cover != null)
          Container(
            alignment: Alignment.center,
            margin: EdgeInsets.only(top: 100),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: CachedNetworkImage(
                imageUrl: details.cover!,
                height: 220,
                fadeInDuration: Duration(milliseconds: 200),
                fadeInCurve: Curves.easeIn,
                errorWidget: (context, url, error) =>
                    Image.asset('lib/assets/images/broken_heart.png'),
              ),
            ),
          ),
        Container(
          margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                iconSize: 27,
                icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Color.fromARGB(69, 0, 0, 0),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Chapters" in place of the anime page's "Episodes" panel.
  Column _readItems(MangaDetails details) {
    final provider = _provider;

    return Column(
      children: [
        _searchStatus(provider, details),
        if (provider != null)
          Container(
            margin: EdgeInsets.only(
              top: 25,
              left: 20 + MediaQuery.of(context).padding.left,
              right: 20 + MediaQuery.of(context).padding.right,
            ),
            padding: EdgeInsets.only(top: 15, bottom: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: appTheme.backgroundSubColor,
            ),
            child: Column(
              children: [
                Container(
                  height: 45,
                  margin: EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.only(left: 20),
                        child: Text(
                          "Chapters",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            fontFamily: "Rubik",
                            color: appTheme.textMainColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _chapterList(details),
              ],
            ),
          ),
      ],
    );
  }

  /// The anime page shows its matched source here; this shows the extension
  /// the chapters came from, or why there are none.
  Widget _searchStatus(MangaChapterProvider? provider, MangaDetails details) {
    return Container(
      margin: EdgeInsets.only(top: 30),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 30),
      child: Text(
        provider == null
            ? "No manga provider installed — install one from Manage Providers."
            : "source: ${provider.providerName}",
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: "NotoSans",
          fontSize: 15,
          color: provider == null ? appTheme.textSubColor : appTheme.textMainColor,
        ),
      ),
    );
  }

  Widget _chapterList(MangaDetails details) {
    return switch (_chaptersState) {
      LoadingState.loading => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: appTheme.accentColor)),
        ),
      LoadingState.error => _inlineMessage(
          "Couldn't load chapters from ${_provider!.providerName}.",
        ),
      _ => _chapters.isEmpty
          ? _inlineMessage(
              "No chapters found for \"${details.title}\" on ${_provider!.providerName}.",
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: Text(
                    chapter.displayTitle,
                    style: TextStyle(
                      fontFamily: "NotoSans",
                      fontSize: 15,
                      color: appTheme.textMainColor,
                    ),
                  ),
                  subtitle: chapter.scanlator == null
                      ? null
                      : Text(
                          chapter.scanlator!,
                          style: TextStyle(
                            fontFamily: "NotoSans",
                            fontSize: 12,
                            color: appTheme.textSubColor,
                          ),
                        ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: appTheme.textSubColor,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => MangaReaderPage(
                        manga: details,
                        chapter: chapter,
                        provider: _provider!,
                      ),
                    ),
                  ),
                );
              },
            ),
    };
  }

  Widget _inlineMessage(String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 10),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: "NotoSans",
          fontSize: 13,
          height: 1.45,
          color: appTheme.textSubColor,
        ),
      ),
    );
  }

  /// The label/value rows, matching `infoMobile._buildInfoItems`.
  Container _infoItems(MangaDetails details) {
    final summary = details.summary;
    return Container(
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.only(top: 50),
            child: Column(
              children: [
                if (summary.format != null)
                  _buildInfoItems(
                    _infoLeft('Type'),
                    _infoRight(summary.format!.toLowerCase()),
                  ),
                if (summary.status != null)
                  _buildInfoItems(
                    _infoLeft('Status'),
                    _infoRight(
                      summary.status!.toLowerCase().replaceAll("_", ' '),
                    ),
                  ),
                _buildInfoItems(
                  _infoLeft('Rating'),
                  _infoRight('${summary.rating ?? '??'}/10'),
                ),
                _buildInfoItems(
                  _infoLeft('Chapters'),
                  _infoRight('${summary.totalChapters ?? '??'}'),
                ),
                if (details.volumes != null)
                  _buildInfoItems(
                    _infoLeft('Volumes'),
                    _infoRight('${details.volumes}'),
                  ),
                if (details.startDate != null)
                  _buildInfoItems(
                    _infoLeft('Start Date'),
                    _infoRight(details.startDate!),
                  ),
                if (details.authors.isNotEmpty)
                  _buildInfoItems(
                    _infoLeft('Authors'),
                    _infoRight(details.authors.first),
                  ),
              ],
            ),
          ),
          if (summary.genres.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 30),
              padding: EdgeInsets.only(left: 15, right: 15),
              child: Column(
                children: [
                  _categoryTitle('Genres'),
                  SizedBox(
                    height: 65,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: summary.genres.length,
                      itemBuilder: (context, index) {
                        return Container(
                          alignment: Alignment.center,
                          margin: EdgeInsets.all(5),
                          padding: EdgeInsets.only(left: 15, right: 15),
                          decoration: BoxDecoration(
                            color: appTheme.backgroundSubColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            summary.genres[index],
                            style: TextStyle(
                              color: appTheme.textMainColor,
                              fontSize: 20,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (details.synopsis != null && details.synopsis!.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 30),
              padding: EdgeInsets.only(left: 25, right: 25),
              child: Column(
                children: [
                  _categoryTitle('Description'),
                  Text(
                    details.synopsis!,
                    style: TextStyle(
                      color: appTheme.textMainColor,
                      fontFamily: "NunitoSans",
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          if (details.characters.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  _categoryTitle('Characters'),
                  SizedBox(
                    height: 260,
                    child: ListView.builder(
                      itemCount: details.characters.length,
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      itemBuilder: (context, index) {
                        final character = details.characters[index];
                        return Container(
                          width: 130,
                          child: Cards.characterCard(
                            character.name,
                            character.role ?? '',
                            character.image ?? '',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Container(
            margin: EdgeInsets.only(top: 20),
            child: Column(
              children: [
                _categoryTitle('Related'),
                _related(details.relations, context),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
        ],
      ),
    );
  }

  /// Related titles. `shouldNavigate: false` -- these can be anime, and this is
  /// a manga page, so tapping must not jump into the anime info page.
  SizedBox _related(List<MangaRelation> relations, BuildContext context) {
    if (relations.isEmpty) {
      return SizedBox(
        height: 240,
        child: Center(
          child: const Text(
            'Nothing to see here!',
            style: TextStyle(
              fontFamily: "NunitoSans",
              fontSize: 18,
              color: const Color.fromARGB(255, 255, 255, 255),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 8),
        itemCount: relations.length,
        itemBuilder: (context, index) {
          final relation = relations[index];
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: Cards.animeCard(
              int.tryParse(relation.id) ?? 0,
              relation.title,
              relation.cover ?? '',
              shouldNavigate: false,
              subText: relation.relationType,
            ),
          );
        },
      ),
    );
  }

  Container _buildInfoItems(Widget itemLeft, Widget itemRight) {
    return Container(
      padding: EdgeInsets.only(left: 15, right: 15),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          itemLeft,
          Container(width: 150, child: itemRight),
        ],
      ),
    );
  }

  Padding _categoryTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: appTheme.textMainColor,
          fontFamily: "NatoSans",
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Padding _infoLeft(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          color: const Color.fromARGB(255, 141, 141, 141),
          fontSize: 17,
          fontFamily: "NatoSans",
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Padding _infoRight(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        text,
        style: TextStyle(
          color: appTheme.textMainColor,
          fontSize: 17,
          fontFamily: "NotoSans",
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.end,
      ),
    );
  }
}