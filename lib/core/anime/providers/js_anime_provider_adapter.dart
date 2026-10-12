import 'dart:async';
import '../../extensions/manager/extension_manager.dart';
import '../../extensions/models/extension_manifest.dart';
import '../../extensions/models/anime_extension_models.dart';

/// Adapts an anime JavaScript extension into Animestream's anime playback architecture.
class JsAnimeProviderAdapter {
  final ExtensionManifest manifest;
  final ExtensionManager _manager;

  JsAnimeProviderAdapter({
    required this.manifest,
    ExtensionManager? manager,
  }) : _manager = manager ?? ExtensionManager();

  String get id => manifest.id;
  String get name => manifest.name;
  String? get iconUrl => manifest.iconUrl;

  /// Searches anime titles using the extension's `searchAnime(query, page)` function.
  Future<List<ExtensionAnimeItem>> search(String query, {int page = 1}) async {
    final result = await _manager.invokeExtension(id, 'searchAnime', [query, page]);
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Search failed in extension $name');
    }

    final rawList = result.data as List? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((item) => ExtensionAnimeItem.fromJson(item))
        .toList();
  }

  /// Retrieves anime details and episode list using `getAnimeDetails(animeId)`.
  Future<Map<String, dynamic>> getDetails(String animeId) async {
    final result = await _manager.invokeExtension(id, 'getAnimeDetails', [animeId]);
    if (!result.isSuccess || result.data is! Map) {
      throw StateError(result.errorMessage ?? 'Failed to get details for $animeId');
    }

    return Map<String, dynamic>.from(result.data as Map);
  }

  /// Retrieves playable video sources using `getVideoSources(episodeId)`.
  Future<List<ExtensionVideoSource>> getVideoSources(String episodeId) async {
    final result = await _manager.invokeExtension(id, 'getVideoSources', [episodeId]);
    if (!result.isSuccess) {
      throw StateError(result.errorMessage ?? 'Failed to fetch video streams for $episodeId');
    }

    final rawList = result.data as List? ?? [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map((item) => ExtensionVideoSource.fromJson(item))
        .toList();
  }

  /// Retrieves subtitle tracks using `getSubtitles(episodeId)`.
  Future<List<ExtensionSubtitleTrack>> getSubtitles(String episodeId) async {
    final result = await _manager.invokeExtension(id, 'getSubtitles', [episodeId]);
    if (!result.isSuccess || result.data is! List) {
      return [];
    }

    return (result.data as List)
        .whereType<Map<String, dynamic>>()
        .map((item) => ExtensionSubtitleTrack.fromJson(item))
        .toList();
  }
}
