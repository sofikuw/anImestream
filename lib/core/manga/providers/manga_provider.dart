import '../../extensions/models/manga_models.dart';

/// Abstract contract for any Manga Source in Animestream,
/// whether implemented as a JavaScript Extension or built-in provider.
abstract class MangaProvider {
  String get id;
  String get name;
  String get version;
  String? get iconUrl;
  String get lang;

  /// Capabilities supported by this provider
  bool get hasSearch;
  bool get hasPopular;
  bool get hasLatest;

  /// Searches manga by query and optional page number.
  Future<List<MangaDetails>> searchManga(String query, {int page = 1});

  /// Fetches popular or trending manga.
  Future<List<MangaDetails>> getPopularManga({int page = 1});

  /// Fetches latest updated manga.
  Future<List<MangaDetails>> getLatestManga({int page = 1});

  /// Fetches full details for a manga title (including chapters).
  Future<MangaDetails> getMangaDetails(String mangaId);

  /// Fetches chapter list for a manga title.
  Future<List<MangaChapter>> getChapters(String mangaId);

  /// Fetches pages (images) for a specific chapter.
  Future<List<MangaPage>> getChapterPages(String chapterId);
}
