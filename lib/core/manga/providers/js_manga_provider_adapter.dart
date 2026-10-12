import 'dart:async';
import '../../extensions/manager/extension_manager.dart';
import '../../extensions/models/extension_manifest.dart';
import '../../extensions/models/manga_models.dart';
import 'manga_provider.dart';

/// Adapts a dynamic JavaScript Extension into Animestream's MangaProvider interface.
class JsMangaProviderAdapter implements MangaProvider {
  final ExtensionManifest manifest;
  final ExtensionManager _manager;

  JsMangaProviderAdapter({
    required this.manifest,
    ExtensionManager? manager,
  }) : _manager = manager ?? ExtensionManager();

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get version => manifest.version;

  @override
  String? get iconUrl => manifest.iconUrl;

  @override
  String get lang => manifest.lang;

  @override
  bool get hasSearch => manifest.capabilities.contains(ExtensionCapability.searchManga);

  @override
  bool get hasPopular => manifest.capabilities.contains(ExtensionCapability.popularManga);

  @override
  bool get hasLatest => manifest.capabilities.contains(ExtensionCapability.latestManga);

  @override
  Future<List<MangaDetails>> searchManga(String query, {int page = 1}) async {
    final result = await _manager.invokeExtension(id, 'searchManga', [query, page]);
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Failed to search manga via $name');
    }

    final rawList = result.data as List? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((item) => MangaDetails.fromJson(item, providerId: id))
        .toList();
  }

  @override
  Future<List<MangaDetails>> getPopularManga({int page = 1}) async {
    final result = await _manager.invokeExtension(id, 'getPopularManga', [page]);
    if (!result.isSuccess) {
      // Fallback to default search if popularManga is not explicitly implemented in extension
      return searchManga('', page: page);
    }

    final rawList = result.data as List? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((item) => MangaDetails.fromJson(item, providerId: id))
        .toList();
  }

  @override
  Future<List<MangaDetails>> getLatestManga({int page = 1}) async {
    final result = await _manager.invokeExtension(id, 'getLatestManga', [page]);
    if (!result.isSuccess) {
      return getPopularManga(page: page);
    }

    final rawList = result.data as List? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((item) => MangaDetails.fromJson(item, providerId: id))
        .toList();
  }

  @override
  Future<MangaDetails> getMangaDetails(String mangaId) async {
    final result = await _manager.invokeExtension(id, 'getMangaDetails', [mangaId]);
    if (!result.isSuccess || result.data is! Map) {
      throw StateError(result.errorMessage ?? 'Failed to retrieve manga details for $mangaId');
    }

    return MangaDetails.fromJson(result.data as Map<String, dynamic>, providerId: id);
  }

  @override
  Future<List<MangaChapter>> getChapters(String mangaId) async {
    // Check if separate getChapters function exists
    final result = await _manager.invokeExtension(id, 'getChapters', [mangaId]);
    if (result.isSuccess && result.data is List) {
      return (result.data as List)
          .whereType<Map<String, dynamic>>()
          .map((c) => MangaChapter.fromJson(c, mangaId: mangaId))
          .toList();
    }

    // Fallback: extract chapters from getMangaDetails
    final details = await getMangaDetails(mangaId);
    final detailRes = await _manager.invokeExtension(id, 'getMangaDetails', [mangaId]);
    if (detailRes.isSuccess && detailRes.data is Map) {
      final rawChapters = (detailRes.data as Map)['chapters'] as List? ?? [];
      return rawChapters
          .whereType<Map<String, dynamic>>()
          .map((c) => MangaChapter.fromJson(c, mangaId: mangaId))
          .toList();
    }

    return [];
  }

  @override
  Future<List<MangaPage>> getChapterPages(String chapterId) async {
    final result = await _manager.invokeExtension(id, 'getChapterPages', [chapterId]);
    if (!result.isSuccess || result.data is! List) {
      throw StateError(result.errorMessage ?? 'Failed to load chapter pages for $chapterId');
    }

    final rawList = result.data as List;
    final pages = <MangaPage>[];
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map<String, dynamic>) {
        pages.add(MangaPage.fromJson(item, i));
      } else if (item is String) {
        pages.add(MangaPage(index: i, imageUrl: item));
      }
    }
    return pages;
  }
}
