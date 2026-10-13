import 'package:animestream/core/manga/types.dart';

/// Manga is split across two capabilities on purpose.
///
/// AniList can browse, search and describe manga, but it cannot hand over
/// readable chapters -- it only knows how many exist. Chapters and page images
/// can only come from an installed manga extension.
///
/// Modelling those as two separate interfaces means the UI degrades honestly:
/// the Manga tab can browse and show details from AniList alone, and the
/// chapter list / reader stay unavailable until a [MangaChapterProvider] is
/// installed. It also keeps an anime-only extension from ever being treated as
/// a manga source, and vice versa.

/// Browsing, search and details. Implemented by AniList.
abstract class MangaMetadataSource {
  /// Display name, e.g. "AniList".
  String get sourceName;

  /// Trending manga, for the home screen's first section.
  Future<List<MangaSummary>> getTrending();

  /// Most popular manga, for the home screen.
  Future<List<MangaSummary>> getPopular();

  /// Recently updated manga, for the home screen.
  Future<List<MangaSummary>> getLatest();

  Future<List<MangaSummary>> search(String query);

  /// [id] is the id carried by [MangaSummary.id].
  Future<MangaDetails> getDetails(String id);
}

/// Chapters and page images. Only an installed manga extension implements this.
///
/// Implementations are untrusted: they run in the JavaScript runtime behind the
/// existing allowlisted HTTP bridge, and must not be given access to app
/// secrets, cookies or the filesystem.
abstract class MangaChapterProvider {
  /// Extension name shown in the chapter list's source selector.
  String get providerName;

  /// Provider identifier, matching the installed extension's identifier.
  String get providerId;

  /// The chapters this source has for [manga].
  ///
  /// Takes the whole [MangaDetails] rather than an opaque id because sources
  /// match on title / alternative titles against their own catalogue.
  Future<List<MangaChapter>> getChapters(MangaDetails manga);

  /// Ordered page images for [chapter]. Returned in reading order.
  Future<List<MangaPage>> getPages(MangaChapter chapter);

  /// Release any runtime resources held by this provider.
  Future<void> dispose();
}
