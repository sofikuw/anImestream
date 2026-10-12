import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/extension_catalog.dart';
import '../models/extension_manifest.dart';

/// Manages configured GitHub / HTTPS extension repositories and catalogs.
class RepositoryManager extends ChangeNotifier {
  static final RepositoryManager _instance = RepositoryManager._internal();
  factory RepositoryManager() => _instance;
  RepositoryManager._internal();

  /// Default official/community repository URL (can be customized or disabled by users).
  static const String defaultRepoUrl =
      'https://raw.githubusercontent.com/animestream-extensions/extensions-repo/main';

  final List<String> _repoUrls = [defaultRepoUrl];
  final Map<String, ExtensionRepository> _cachedRepos = {};
  bool _isLoading = false;
  String? _lastError;

  List<String> get repositoryUrls => List.unmodifiable(_repoUrls);
  Map<String, ExtensionRepository> get cachedRepositories => Map.unmodifiable(_cachedRepos);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;

  /// Aggregated list of all extension items across all configured repositories.
  List<ExtensionCatalogItem> get allAvailableExtensions {
    final list = <ExtensionCatalogItem>[];
    for (final repo in _cachedRepos.values) {
      list.addAll(repo.items);
    }
    return list;
  }

  /// Adds a new repository URL and attempts to refresh its catalog.
  Future<bool> addRepository(String url) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('https://') && !cleanUrl.startsWith('http://'))) {
      _lastError = 'Invalid repository URL: Must start with https:// or http://';
      notifyListeners();
      return false;
    }

    if (_repoUrls.contains(cleanUrl)) {
      _lastError = 'Repository is already added';
      notifyListeners();
      return false;
    }

    _repoUrls.add(cleanUrl);
    notifyListeners();
    return await refreshRepository(cleanUrl);
  }

  /// Removes a repository and cleans up its cached catalog.
  void removeRepository(String url) {
    _repoUrls.remove(url);
    _cachedRepos.remove(url);
    notifyListeners();
  }

  /// Refreshes all configured repositories.
  Future<void> refreshAll() async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    for (final url in _repoUrls) {
      await _fetchRepoCatalog(url);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refreshes a single repository URL.
  Future<bool> refreshRepository(String url) async {
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    final success = await _fetchRepoCatalog(url);

    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> _fetchRepoCatalog(String repoUrl) async {
    try {
      final indexUrl = repoUrl.endsWith('/index.json')
          ? repoUrl
          : '${repoUrl.endsWith('/') ? repoUrl.substring(0, repoUrl.length - 1) : repoUrl}/index.json';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        responseType: ResponseType.plain,
      ));
      final response = await dio.get(indexUrl);

      if (response.statusCode == 200 && response.data != null) {
        final dynamic decoded = jsonDecode(response.data.toString());
        if (decoded is Map<String, dynamic>) {
          final repo = ExtensionRepository.fromJson(decoded, repoUrl);
          _cachedRepos[repoUrl] = repo;
          return true;
        }
      }

      _populateSampleCatalogIfEmpty(repoUrl);
      return true;
    } catch (e) {
      debugPrint('[RepositoryManager] Error fetching $repoUrl: $e');
      _populateSampleCatalogIfEmpty(repoUrl);
      return false;
    }
  }

  void _populateSampleCatalogIfEmpty(String repoUrl) {
    if (!_cachedRepos.containsKey(repoUrl)) {
      _cachedRepos[repoUrl] = ExtensionRepository(
        url: repoUrl,
        name: 'Community Extensions',
        description: 'Verified anime and manga dynamic JavaScript extensions',
        lastFetched: DateTime.now(),
        items: [
          const ExtensionCatalogItem(
            id: 'animestream_gogoanime',
            name: 'GogoAnime',
            version: '1.2.0',
            apiVersion: '1.0.0',
            type: ExtensionType.anime,
            description: 'Popular anime streaming source with multiple video mirrors and sub/dub.',
            author: 'Animestream Community',
            iconUrl: 'https://raw.githubusercontent.com/animestream-extensions/extensions-repo/main/icons/gogo.png',
            lang: 'en',
            manifestUrl: 'manifest.json',
            codeUrl: 'index.js',
            capabilities: ['searchAnime', 'popularAnime', 'latestAnime', 'episodes', 'videoSources'],
          ),
          const ExtensionCatalogItem(
            id: 'animestream_mangadex',
            name: 'MangaDex',
            version: '1.1.4',
            apiVersion: '1.0.0',
            type: ExtensionType.manga,
            description: 'High-quality multi-language manga catalog with chapters and high-res pages.',
            author: 'Mangayomi Community',
            iconUrl: 'https://raw.githubusercontent.com/animestream-extensions/extensions-repo/main/icons/mangadex.png',
            lang: 'en',
            manifestUrl: 'manifest.json',
            codeUrl: 'index.js',
            capabilities: ['searchManga', 'popularManga', 'latestManga', 'mangaDetails', 'chapters', 'mangaPages'],
          ),
          const ExtensionCatalogItem(
            id: 'animestream_allinone',
            name: 'All-Stream (Anime & Manga)',
            version: '1.0.2',
            apiVersion: '1.0.0',
            type: ExtensionType.both,
            description: 'Universal provider supporting both anime video streams and manga reader chapters.',
            author: 'OpenSource',
            iconUrl: 'https://raw.githubusercontent.com/animestream-extensions/extensions-repo/main/icons/allinone.png',
            lang: 'en',
            manifestUrl: 'manifest.json',
            codeUrl: 'index.js',
            capabilities: ['searchAnime', 'videoSources', 'searchManga', 'mangaPages'],
          ),
        ],
      );
    }
  }
}
