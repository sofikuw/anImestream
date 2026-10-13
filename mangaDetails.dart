import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/javascriptMangaProvider.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:animestream/ui/pages/mangaReader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Manga details.
///
/// Laid out as a structural mirror of `info/infoMobile.dart`, the anime details
/// page: the same banner-and-cover stack, the same accent pill button, the same
/// centred title, the same left/right metadata rows and the same
/// `_categoryTitle` headings. The two deliberate differences are the content
/// type and the button, which reads "read" and toggles to the chapter list
/// instead of opening a server picker.
///
/// Everything except the chapters comes from AniList and works with no extension
/// installed -- that is the metadata half of [MangaMetadataSource].
///
/// The chapter list is the one part AniList cannot supply: it reports a chapter
/// *count* and never a list of chapters. With no manga extension installed no
/// chapter rows are synthesised; the section says so instead. An installed
/// extension is discovered on load and supplies both chapters and pages.
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

  List<MangaChapter> _chapters = [];
  LoadingState _chaptersState = LoadingState.loaded;

  /// Mirrors infoMobile's `infoPage`: false shows the chapter list instead of
  /// the metadata, behind the same pill button.
  bool _infoPage = true;

  /// Chapters and pages. Taken from the caller when one is supplied, otherwise
  /// discovered from an installed manga extension during [load].
  MangaChapterProvider? _provider;

  bool get _useNativeTitle => currentUserSettings?.nativeTitle ?? false;

  @override
  void initState() {
    super.initState();
    _provider = widget.chapterProvider;
    load();
  }

  @override
  void dispose() {
    // Only a provider this page discovered itself is this page's to release; one
    // supplied by the caller belongs to the caller.
    if (widget.chapterProvider == null) {
      _provider?.dispose();
    }
    super.dispose();
  }

  /// English leads unless the user prefers native titles, matching how the anime
  /// page resolves AniList's title triple.
  String get _displayTitle {
    final details = _details!;
    if (_useNativeTitle && details.nativeTitle != null) return details.nativeTitle!;
    final titles = <String>[details.title, ...details.alternateTitles];
    return titles.isEmpty ? 'Unknown' : titles.first;
  }

  Future<void> load() async {
    setState(() => _state = LoadingState.loading);

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
      setState(() => _state = LoadingState.error);
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
      body: switch (_state) {
        LoadingState.loading => Center(
            child: CircularProgressIndicator(color: appTheme.accentColor),
          ),
        LoadingState.error => _errorView(),
        _ => _detailsView(_details!),
      },
    );
  }

  // ---------------------------------------------------------------- error

  /// Mirrors the anime page's failure state: broken heart, the same wording and
  /// a "Go Back" button in the accent colour.
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
              style: TextStyle(
                color: appTheme.backgroundColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _detailsView(MangaDetails details) {
    return CustomScrollView(
      slivers: [
        SliverList.list(
          children: [
            _stack(details),
            _readButton(),
            Container(
              margin: const EdgeInsets.only(top: 45),
              padding: const EdgeInsets.only(left: 20, right: 20),
              alignment: Alignment.center,
              child: Text(
                _displayTitle,
                style: TextStyle(
                  color: appTheme.textMainColor,
                  fontFamily: "NunitoSans",
                  fontSize: 25,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _infoPage ? _infoItems(details) : _chaptersSection(details),
            ),
            footSpace(),
          ],
        ),
      ],
    );
  }

  /// The same accent pill the anime page uses for "watch", reading "read" and
  /// switching to the chapter list.
  Widget _readButton() {
    final hasChapters = _provider != null;

    return Container(
      margin: const EdgeInsets.only(top: 30),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () {
              if (!hasChapters) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: appTheme.backgroundSubColor,
                    content: Text(
                      "Install a manga extension from Manage Providers to read chapters.",
                      style: TextStyle(
                        fontFamily: "NotoSans",
                        color: appTheme.textMainColor,
                      ),
                    ),
                  ),
                );
                return;
              }
              setState(() => _infoPage = !_infoPage);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: appTheme.accentColor,
              fixedSize: const Size(135, 55),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _infoPage ? Icons.menu_book_rounded : Icons.info_rounded,
                  color: appTheme.onAccent,
                  size: 28,
                ),
                Text(
                  _infoPage ? " read" : " info",
                  style: TextStyle(
                    color: appTheme.onAccent,
                    fontFamily: "Poppins",
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Banner + centred cover + back button, matching `_stack()` in infoMobile.
  Stack _stack(MangaDetails details) {
    final banner = details.banner ?? details.cover;

    return Stack(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [Colors.transparent, appTheme.backgroundColor],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            stops: const [0.09, 0.23],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: Container(
            height: 270,
            width: double.infinity,
            child: banner == null
                ? Container(color: appTheme.backgroundSubColor)
                : Image.network(
                    banner,
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(0.6),
                    errorBuilder: (context, error, stackTrace) =>
                        Container(height: 270, color: appTheme.backgroundSubColor),
                    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded) return child;
                      return AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: const Duration(milliseconds: 300),
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
            margin: const EdgeInsets.only(top: 100),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: CachedNetworkImage(
                imageUrl: details.cover!,
                height: 220,
                fadeInDuration: const Duration(milliseconds: 200),
                fadeInCurve: Curves.easeIn,
                placeholder: (context, url) => Container(
                  height: 220,
                  width: 150,
                  color: appTheme.backgroundSubColor,
                ),
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
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: const Color.fromARGB(69, 0, 0, 0),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- info items

  /// The anime page's Type / Status / Rating / Episodes rows, in manga terms.
  Widget _infoItems(MangaDetails details) {
    final summary = details.summary;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 50),
          child: Column(
            children: [
              _buildInfoItems(
                _infoLeft('Type'),
                _infoRight((summary.format ?? 'manga').toLowerCase()),
              ),
              _buildInfoItems(
                _infoLeft('Status'),
                _infoRight('${summary.status ?? '??'}'.toLowerCase().replaceAll("_", ' ')),
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
                _buildInfoItems(_infoLeft('Volumes'), _infoRight('${details.volumes}')),
              _buildInfoItems(_infoLeft("Authors"), _infoRight(_authorLine(details))),
              if (details.startDate != null)
                _buildInfoItems(_infoLeft("Start Date"), _infoRight(details.startDate!)),
            ],
          ),
        ),
        if (summary.genres.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 30),
            padding: const EdgeInsets.only(left: 15, right: 15),
            child: Column(
              children: [
                _categoryTitle('Genres'),
                SizedBox(
                  height: 65,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: summary.genres.length,
                    itemBuilder: (context, index) => Container(
                      alignment: Alignment.center,
                      margin: const EdgeInsets.all(5),
                      padding: const EdgeInsets.only(left: 15, right: 15),
                      decoration: BoxDecoration(
                        color: appTheme.backgroundSubColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        summary.genres[index],
                        style: TextStyle(color: appTheme.textMainColor, fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (details.synopsis != null && details.synopsis!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 30),
            padding: const EdgeInsets.only(left: 25, right: 25),
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
        if (details.characters.isNotEmpty) _characters(details.characters),
        if (details.relations.isNotEmpty) _related(details.relations),
      ],
    );
  }

  Widget _characters(List<MangaCharacter> characters) {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      child: Column(
        children: [
          _categoryTitle('Characters'),
          SizedBox(
            height: 260,
            child: ListView.builder(
              itemCount: characters.length,
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final character = characters[index];
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
    );
  }

  Widget _related(List<MangaRelation> relations) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          _categoryTitle('Related'),
          SizedBox(
            height: 260,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: relations.length,
              itemBuilder: (context, index) {
                final item = relations[index];
                // `shouldNavigate: false` -- these can be anime, and this is a
                // manga page, so tapping must not jump into the anime info page.
                // Same reasoning as the anime page, inverted.
                return Container(
                  width: 130,
                  child: Cards.animeCard(
                    int.tryParse(item.id) ?? 0,
                    item.title,
                    item.cover ?? '',
                    shouldNavigate: false,
                    subText: item.relationType,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _authorLine(MangaDetails details) {
    if (details.authors.isEmpty) return '??';
    // AniList appends "(Story & Art)" to staff names; the anime page shows the
    // raw studio name, so the role is stripped to keep the row short.
    final first = details.authors.first;
    final bracket = first.indexOf(' (');
    return bracket == -1 ? first : first.substring(0, bracket);
  }

  Widget _buildInfoItems(Widget itemLeft, Widget itemRight) {
    return Container(
      padding: const EdgeInsets.only(left: 15, right: 15),
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
        style: const TextStyle(
          color: Color.fromARGB(255, 141, 141, 141),
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

  // ------------------------------------------------------------ chapters

  /// The reading gate. Where the anime page lists episodes, this lists chapters
  /// once a manga extension is installed.
  Widget _chaptersSection(MangaDetails details) {
    return Container(
      margin: const EdgeInsets.only(top: 25, left: 20, right: 20),
      padding: const EdgeInsets.only(top: 15, bottom: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: appTheme.backgroundSubColor,
      ),
      child: Column(
        children: [
          Container(
            height: 45,
            margin: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 20),
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
                if (_provider != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Text(
                      _provider!.providerName,
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
          if (_provider == null)
            _noProviderGate(details.totalChapters)
          else
            _chapterList(details),
        ],
      ),
    );
  }

  Widget _noProviderGate(int? totalChapters) {
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 20, top: 4, bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension_off_rounded, color: appTheme.textSubColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "No manga provider installed",
                  style: TextStyle(
                    fontFamily: "Poppins",
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: appTheme.textMainColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            totalChapters == null
                ? "Install a manga extension from Manage Providers to read chapters here."
                : "AniList lists $totalChapters chapters for this title but provides no chapter list "
                    "or pages. Install a manga extension from Manage Providers to read them.",
            style: TextStyle(
              fontFamily: "NotoSans",
              fontSize: 13,
              height: 1.45,
              color: appTheme.textSubColor,
            ),
          ),
        ],
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
          ? _inlineMessage("This provider has no chapters for this title.")
          : ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
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
                  trailing: Icon(Icons.chevron_right_rounded, color: appTheme.textSubColor),
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
      padding: const EdgeInsets.only(left: 20, right: 20, top: 8, bottom: 5),
      child: Text(
        message,
        style: TextStyle(fontFamily: "NotoSans", fontSize: 13, color: appTheme.textSubColor),
      ),
    );
  }

  SizedBox footSpace() {
    return SizedBox(height: MediaQuery.of(context).padding.bottom + 60);
  }
}