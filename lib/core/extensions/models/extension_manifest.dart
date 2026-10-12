import 'dart:convert';

/// Supported types of content an extension can provide.
enum ExtensionType {
  anime,
  manga,
  both;

  static ExtensionType fromString(String val) {
    switch (val.toLowerCase()) {
      case 'anime':
        return ExtensionType.anime;
      case 'manga':
        return ExtensionType.manga;
      case 'both':
      default:
        return ExtensionType.both;
    }
  }

  String toJsonString() => name;
}

/// Declared capabilities supported by an extension.
enum ExtensionCapability {
  searchAnime,
  popularAnime,
  latestAnime,
  animeDetails,
  episodes,
  videoSources,
  subtitles,
  searchManga,
  popularManga,
  latestManga,
  mangaDetails,
  chapters,
  mangaPages,
  filters;

  static ExtensionCapability? fromString(String val) {
    for (final cap in ExtensionCapability.values) {
      if (cap.name.toLowerCase() == val.toLowerCase()) return cap;
    }
    return null;
  }
}

/// Versioned metadata manifest for an Animestream JavaScript extension.
class ExtensionManifest {
  final String id;
  final String name;
  final String version;
  final String apiVersion;
  final ExtensionType type;
  final String author;
  final String description;
  final String iconUrl;
  final String lang;
  final String entrypoint;
  final String? baseUrl;
  final Set<ExtensionCapability> capabilities;
  final String? sha256;
  final int? minAppVersion;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.apiVersion,
    required this.type,
    required this.author,
    required this.description,
    required this.iconUrl,
    required this.lang,
    required this.entrypoint,
    this.baseUrl,
    required this.capabilities,
    this.sha256,
    this.minAppVersion,
  });

  /// Validates the manifest against schema constraints.
  List<String> validate() {
    final errors = <String>[];
    if (id.isEmpty || !RegExp(r'^[a-z0-9_.-]+$').hasMatch(id)) {
      errors.add('Invalid extension ID: must be lowercase alphanumeric with hyphens/dots/underscores');
    }
    if (name.isEmpty) errors.add('Extension name cannot be empty');
    if (version.isEmpty || !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      errors.add('Version must follow Semantic Versioning (e.g. 1.0.0)');
    }
    if (apiVersion.isEmpty) {
      errors.add('apiVersion is required');
    } else {
      final major = int.tryParse(apiVersion.split('.').first);
      if (major == null || major < 1) {
        errors.add('Incompatible apiVersion: current supported major version is 1.x');
      }
    }
    if (entrypoint.isEmpty) errors.add('Entrypoint file path must be specified');
    return errors;
  }

  bool isCompatibleWith(String targetApiVersion) {
    try {
      final myMajor = int.parse(apiVersion.split('.').first);
      final targetMajor = int.parse(targetApiVersion.split('.').first);
      return myMajor == targetMajor;
    } catch (_) {
      return false;
    }
  }

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    final rawCaps = json['capabilities'] as List? ?? [];
    final parsedCaps = <ExtensionCapability>{};
    for (final c in rawCaps) {
      final cap = ExtensionCapability.fromString(c.toString());
      if (cap != null) parsedCaps.add(cap);
    }

    return ExtensionManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      apiVersion: json['apiVersion'] as String? ?? '1.0.0',
      type: ExtensionType.fromString(json['type'] as String? ?? 'both'),
      author: json['author'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      iconUrl: json['iconUrl'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      entrypoint: json['entrypoint'] as String? ?? 'index.js',
      baseUrl: json['baseUrl'] as String?,
      capabilities: parsedCaps,
      sha256: json['sha256'] as String?,
      minAppVersion: json['minAppVersion'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'apiVersion': apiVersion,
    'type': type.toJsonString(),
    'author': author,
    'description': description,
    'iconUrl': iconUrl,
    'lang': lang,
    'entrypoint': entrypoint,
    'baseUrl': baseUrl,
    'capabilities': capabilities.map((c) => c.name).toList(),
    'sha256': sha256,
    'minAppVersion': minAppVersion,
  };

  @override
  String toString() => 'ExtensionManifest(id: $id, name: $name, v: $version)';
}
