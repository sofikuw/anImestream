import 'extension_manifest.dart';

/// Item in a remote repository catalog.
class ExtensionCatalogItem {
  final String id;
  final String name;
  final String version;
  final String apiVersion;
  final ExtensionType type;
  final String description;
  final String author;
  final String iconUrl;
  final String lang;
  final String manifestUrl;
  final String codeUrl;
  final String? sha256;
  final List<String> capabilities;

  const ExtensionCatalogItem({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.type,
    required this.description,
    required this.author,
    required this.iconUrl,
    required this.lang,
    required this.manifestUrl,
    required this.codeUrl,
    this.sha256,
    this.capabilities = const [],
  });

  factory ExtensionCatalogItem.fromJson(Map<String, dynamic> json, String repoBaseUrl) {
    String resolveUrl(String? path) {
      if (path == null || path.isEmpty) return '';
      if (path.startsWith('http://') || path.startsWith('https://')) return path;
      final cleanBase = repoBaseUrl.endsWith('/') ? repoBaseUrl.substring(0, repoBaseUrl.length - 1) : repoBaseUrl;
      final cleanPath = path.startsWith('/') ? path.substring(1) : path;
      return '$cleanBase/$cleanPath';
    }

    return ExtensionCatalogItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      apiVersion: json['apiVersion'] as String? ?? '1.0.0',
      type: ExtensionType.fromString(json['type'] as String? ?? 'both'),
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? 'Community',
      iconUrl: resolveUrl(json['iconUrl'] as String?),
      lang: json['lang'] as String? ?? 'en',
      manifestUrl: resolveUrl(json['manifestUrl'] as String? ?? 'manifest.json'),
      codeUrl: resolveUrl(json['codeUrl'] as String? ?? 'index.js'),
      sha256: json['sha256'] as String?,
      capabilities: (json['capabilities'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'apiVersion': apiVersion,
    'type': type.toJsonString(),
    'description': description,
    'author': author,
    'iconUrl': iconUrl,
    'lang': lang,
    'manifestUrl': manifestUrl,
    'codeUrl': codeUrl,
    'sha256': sha256,
    'capabilities': capabilities,
  };
}

/// A repository containing multiple extensions.
class ExtensionRepository {
  final String url;
  final String name;
  final String formatVersion;
  final String? description;
  final DateTime lastFetched;
  final List<ExtensionCatalogItem> items;

  const ExtensionRepository({
    required this.url,
    required this.name,
    this.formatVersion = '1.0.0',
    this.description,
    required this.lastFetched,
    required this.items,
  });

  factory ExtensionRepository.fromJson(Map<String, dynamic> json, String repoUrl) {
    final rawItems = json['extensions'] as List? ?? [];
    final parsed = rawItems
        .whereType<Map<String, dynamic>>()
        .map((item) => ExtensionCatalogItem.fromJson(item, repoUrl))
        .toList();

    return ExtensionRepository(
      url: repoUrl,
      name: json['name'] as String? ?? 'Custom Repository',
      formatVersion: json['formatVersion'] as String? ?? '1.0.0',
      description: json['description'] as String?,
      lastFetched: DateTime.now(),
      items: parsed,
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'formatVersion': formatVersion,
    'description': description,
    'lastFetched': lastFetched.toIso8601String(),
    'extensions': items.map((e) => e.toJson()).toList(),
  };
}
