import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A user-added HTTPS index containing versioned JavaScript anime manifests.
class ProviderRepository {
  const ProviderRepository._(this.indexUrl);

  factory ProviderRepository.fromIndexUrl(String rawUrl) {
    final uri = validateIndexUrl(rawUrl);
    return ProviderRepository._(uri.toString());
  }

  factory ProviderRepository.fromMap(Map<String, dynamic> map) =>
      ProviderRepository.fromIndexUrl(map['indexUrl'] as String);

  final String indexUrl;

  Uri get uri => Uri.parse(indexUrl);

  String get id => sha256.convert(utf8.encode(indexUrl)).toString();

  String get name {
    final parsed = uri;
    final path = parsed.path == '/' ? '' : parsed.path;
    return '${parsed.host}$path';
  }

  Map<String, dynamic> toMap() => <String, dynamic>{'indexUrl': indexUrl};

  static Uri validateIndexUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_isPublicDnsHost(uri.host)) {
      throw const FormatException(
        'Repository index must be an HTTPS URL on a public DNS hostname.',
      );
    }
    return uri.replace(
      scheme: 'https',
      host: uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), ''),
    );
  }

  static bool isPublicDnsHost(String rawHost) => _isPublicDnsHost(rawHost);

  static bool _isPublicDnsHost(String rawHost) {
    final host = rawHost.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.length > 253 ||
        host.isEmpty ||
        host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.contains(':') ||
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
      return false;
    }
    final labels = host.split('.');
    if (labels.length < 2) return false;
    if (labels.every((label) => RegExp(r'^\d+$').hasMatch(label))) {
      return false;
    }
    return labels.every(
      (label) =>
          label.length <= 63 &&
          RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label),
    );
  }
}

/// One versioned JavaScript anime-provider entry from a repository index.
class JsAnimeProviderManifest {
  const JsAnimeProviderManifest({
    required this.manifestVersion,
    required this.name,
    required this.identifier,
    required this.version,
    required this.entrypoint,
    required this.entrypointSha256,
    required this.allowedHosts,
    required this.supportDownloads,
    required this.repositoryUrl,
    required this.codeUrl,
  });

  final int manifestVersion;
  final String name;
  final String identifier;
  final String version;
  final String entrypoint;
  final String entrypointSha256;
  final List<String> allowedHosts;
  final bool supportDownloads;
  final String repositoryUrl;
  final Uri codeUrl;

  factory JsAnimeProviderManifest.fromMap(
    Map<String, dynamic> map, {
    required ProviderRepository repository,
  }) {
    final manifestVersion = map['manifestVersion'];
    if (manifestVersion != 1) {
      throw FormatException(
        'Unsupported provider manifestVersion: $manifestVersion.',
      );
    }

    final name = _requiredString(map['name'], 'name', maxLength: 100);
    final identifier = _requiredString(
      map['identifier'],
      'identifier',
      maxLength: 64,
    );
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(identifier) ||
        identifier.endsWith('_inbuilt')) {
      throw const FormatException('Provider identifier is invalid.');
    }

    final version = _requiredString(map['version'], 'version', maxLength: 64);
    if (!_isSemver(version)) {
      throw const FormatException(
        'Provider version must use major.minor.patch numeric format.',
      );
    }
    if (map['scriptType'] != 'javascript') {
      throw const FormatException(
        'This catalog only accepts JavaScript providers.',
      );
    }

    final contentTypes = map['contentTypes'];
    if (contentTypes is! List || !contentTypes.contains('anime')) {
      throw const FormatException(
        'Provider must declare anime in contentTypes.',
      );
    }

    final entrypoint = _requiredString(
      map['entrypoint'],
      'entrypoint',
      maxLength: 512,
    );
    final entryUri = Uri.tryParse(entrypoint);
    if (entryUri == null ||
        entryUri.hasScheme ||
        entryUri.hasAuthority ||
        entryUri.hasQuery ||
        entryUri.hasFragment ||
        entryUri.path.startsWith('/') ||
        entrypoint.contains(r'\') ||
        entryUri.pathSegments.contains('..') ||
        entryUri.pathSegments.contains('.')) {
      throw const FormatException(
        'Provider entrypoint must be a relative path inside its repository.',
      );
    }
    final repositoryUri = repository.uri;
    final codeUrl = repositoryUri.resolve(entrypoint);
    if (codeUrl.scheme != 'https' ||
        codeUrl.host != repositoryUri.host ||
        codeUrl.port != repositoryUri.port ||
        codeUrl.userInfo.isNotEmpty) {
      throw const FormatException(
        'Provider entrypoint must stay on the repository HTTPS host.',
      );
    }

    final digest = _requiredString(
      map['entrypointSha256'],
      'entrypointSha256',
      maxLength: 64,
    ).toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'entrypointSha256 must be a 64-character SHA-256 hex digest.',
      );
    }

    final rawHosts = map['allowedHosts'];
    if (rawHosts is! List || rawHosts.length > 32) {
      throw const FormatException(
        'allowedHosts must be a list with at most 32 hostnames.',
      );
    }
    final hosts = <String>[];
    for (final value in rawHosts) {
      if (value is! String ||
          !ProviderRepository.isPublicDnsHost(value) ||
          value.trim() != value) {
        throw const FormatException(
          'allowedHosts must contain exact public DNS hostnames.',
        );
      }
      final normalized = value.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
      if (hosts.contains(normalized)) {
        throw FormatException('Duplicate allowed host: $normalized.');
      }
      hosts.add(normalized);
    }

    final supportDownloads = map['supportDownloads'];
    if (supportDownloads is! bool) {
      throw const FormatException('supportDownloads must be a boolean.');
    }

    return JsAnimeProviderManifest(
      manifestVersion: manifestVersion,
      name: name,
      identifier: identifier,
      version: version,
      entrypoint: entrypoint,
      entrypointSha256: digest,
      allowedHosts: List<String>.unmodifiable(hosts),
      supportDownloads: supportDownloads,
      repositoryUrl: repository.indexUrl,
      codeUrl: codeUrl,
    );
  }

  static String _requiredString(
    Object? value,
    String field, {
    required int maxLength,
  }) {
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        value.length > maxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw FormatException(
        '$field must be a clean string of at most $maxLength characters.',
      );
    }
    return value;
  }

  static bool _isSemver(String value) =>
      RegExp(r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')
          .hasMatch(value);

  /// Returns -1, 0, or 1 for supported `major.minor.patch` versions.
  static int compareVersions(String left, String right) {
    if (!_isSemver(left) || !_isSemver(right)) {
      throw const FormatException('Cannot compare invalid provider versions.');
    }
    final a = left.split('.').map(BigInt.parse).toList(growable: false);
    final b = right.split('.').map(BigInt.parse).toList(growable: false);
    for (var index = 0; index < 3; index++) {
      if (a[index] < b[index]) return -1;
      if (a[index] > b[index]) return 1;
    }
    return 0;
  }
}

class ProviderCatalog {
  const ProviderCatalog({
    required this.repository,
    required this.providers,
  });

  final ProviderRepository repository;
  final List<JsAnimeProviderManifest> providers;
}
