import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums/loadingState.dart';
import 'package:animestream/core/manga/anilistManga.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:animestream/ui/models/widgets/cards.dart';
import 'package:flutter/material.dart';

/// Manga details.
///
/// Everything on this page except the chapter list comes from AniList and works
/// with no extension installed.
///
/// The chapter list is gated on [chapterProvider]. AniList reports a chapter
/// *count* (`chapters: 120`) but never a list of chapters and never page
/// images, so with no provider there is nothing honest to render -- no chapter
/// rows are synthesised from the count. Wiring an installed manga extension in
/// here is the next increment.
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _state = LoadingState.loading;
      _error = null;
    });

    try {
      final details = await _source.getDetails(widget.id);
      if (!mounted) return;
      setState(() {
        _details = details;
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
    final provider = widget.chapterProvider;
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
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: appTheme.textMainColor),
      ),
      body: switch (_state) {
        LoadingState.loading => Center(child: CircularProgressIndicator(color: appTheme.accentColor)),
        LoadingState.error => _errorView(),
        _ => _detailsView(_details!),
      },
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset("lib/assets/images/ghost.png", color: const Color.fromARGB(255, 80, 80, 80)),
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: Text(
                "Aww... Something's wrong!",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: "NunitoSans",
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(255, 80, 80, 80),
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: load,
              child: Text("Try again", style: TextStyle(color: appTheme.accentColor, fontFamily: "NotoSans")),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailsView(MangaDetails details) {
    final summary = details.summary;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(details),
          _titles(details),
          _metaChips(summary, details),
          if (details.synopsis != null && details.synopsis!.isNotEmpty) _synopsis(details.synopsis!),
          if (details.authors.isNotEmpty) _authors(details.authors),
          if (details.characters.isNotEmpty) _characters(details.characters),
          if (details.relations.isNotEmpty) _relations(details.relations),
          divider(),
          _chaptersSection(details),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
        ],
      ),
    );
  }

  Widget _cover(MangaDetails details) {
    final banner = details.banner ?? details.cover;
    return Stack(
      children: [
        if (banner != null)
          Container(
            height: 200,
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: Image.network(
              banner,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                height: 200,
                color: appTheme.backgroundSubColor,
                child: Image.asset('lib/assets/images/broken_heart.png'),
              ),
            ),
          )
        else
          Container(height: 200, color: appTheme.backgroundSubColor),
        // Scrim so the cover art and title stay readable over any banner.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  appTheme.backgroundColor.withValues(alpha: 0.25),
                  appTheme.backgroundColor,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 15,
          bottom: 0,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (details.cover != null)
                Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                  height: 130,
                  width: 90,
                  child: Image.network(
                    details.cover!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        Image.asset('lib/assets/images/broken_heart.png'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _titles(MangaDetails details) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            details.title,
            style: TextStyle(fontFamily: "Rubik", fontSize: 22, color: appTheme.textMainColor),
          ),
          if (details.authors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                details.authors.first,
                style: TextStyle(fontFamily: "NotoSans", fontSize: 13, color: appTheme.textSubColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaChips(MangaSummary summary, MangaDetails details) {
    final chips = <String>[
      if (summary.format != null) summary.format!,
      if (summary.status != null) _prettyStatus(summary.status!),
      if (summary.totalChapters != null) '${summary.totalChapters} chapters',
      if (details.volumes != null) '${details.volumes} volumes',
      if (summary.rating != null) '★ ${summary.rating!.toStringAsFixed(1)}',
      if (details.startDate != null) details.startDate!,
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final chip in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: appTheme.backgroundSubColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                chip,
                style: TextStyle(fontFamily: "NotoSans", fontSize: 12, color: appTheme.textSubColor),
              ),
            ),
        ],
      ),
    );
  }

  /// AniList returns SCREAMING_SNAKE enums; show them as words.
  static String _prettyStatus(String status) {
    final lower = status.toLowerCase().replaceAll('_', ' ');
    if (lower.isEmpty) return status;
    return lower[0].toUpperCase() + lower.substring(1);
  }

  Widget _synopsis(String synopsis) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 16),
      child: Text(
        synopsis,
        style: TextStyle(fontFamily: "NotoSans", fontSize: 14, height: 1.5, color: appTheme.textMainColor),
      ),
    );
  }

  Widget _authors(List<String> authors) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final author in authors)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: appTheme.backgroundSubColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                author,
                style: TextStyle(fontFamily: "NotoSans", fontSize: 12, color: appTheme.textMainColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _characters(List<MangaCharacter> characters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Characters"),
        SizedBox(
          height: 240,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            scrollDirection: Axis.horizontal,
            itemCount: characters.length,
            itemBuilder: (context, index) {
              final character = characters[index];
              return Padding(
                padding: const EdgeInsets.all(8.0),
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
    );
  }

  Widget _relations(List<MangaRelation> relations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Related"),
        SizedBox(
          height: 160,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            scrollDirection: Axis.horizontal,
            itemCount: relations.length,
            itemBuilder: (context, index) {
              final relation = relations[index];
              // `shouldNavigate: false` -- these can be anime, and this is a
              // manga page, so tapping must not jump into the anime info page.
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
        ),
      ],
    );
  }

  /// The reading gate. This is where an installed manga extension's chapters
  /// will be listed once [chapterProvider] is wired up.
  Widget _chaptersSection(MangaDetails details) {
    final provider = widget.chapterProvider;
    final totalChapters = details.totalChapters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle("Chapters"),
        if (provider == null) _noProviderGate(totalChapters) else _chapterList(),
      ],
    );
  }

  Widget _noProviderGate(int? totalChapters) {
    return Container(
      margin: const EdgeInsets.only(left: 15, right: 15, top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(12),
      ),
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
            style: TextStyle(fontFamily: "NotoSans", fontSize: 13, height: 1.45, color: appTheme.textSubColor),
          ),
        ],
      ),
    );
  }

  Widget _chapterList() {
    return switch (_chaptersState) {
      LoadingState.loading => Padding(
          padding: const EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: appTheme.accentColor)),
        ),
      LoadingState.error => _inlineMessage("Couldn't load chapters from ${widget.chapterProvider!.providerName}."),
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
                    style: TextStyle(fontFamily: "NotoSans", fontSize: 15, color: appTheme.textMainColor),
                  ),
                  subtitle: chapter.scanlator == null
                      ? null
                      : Text(
                          chapter.scanlator!,
                          style: TextStyle(fontFamily: "NotoSans", fontSize: 12, color: appTheme.textSubColor),
                        ),
                  trailing: Icon(Icons.chevron_right_rounded, color: appTheme.textSubColor),
                  // The reader lands in the next increment.
                  onTap: () => floatingSnackBar("Reader lands in the next stage."),
                );
              },
            ),
    };
  }

  Widget _inlineMessage(String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 15, right: 15, top: 8),
      child: Text(
        message,
        style: TextStyle(fontFamily: "NotoSans", fontSize: 13, color: appTheme.textSubColor),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 15, right: 15, top: 20, bottom: 4),
      child: Text(
        title,
        style: TextStyle(fontFamily: "Rubik", fontSize: 20, color: appTheme.textMainColor),
      ),
    );
  }

  Center divider() {
    return Center(
      child: Container(
        width: MediaQuery.of(context).size.width / 2,
        margin: const EdgeInsets.only(top: 25, bottom: 5),
        height: 6,
        decoration: BoxDecoration(
          color: appTheme.accentColor.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
