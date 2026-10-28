import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:animestream/core/extensions/javascript/provider_http_client.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Fetches versioned catalogs and installs their hash-checked JavaScript code.
class ProviderCatalogService {
  ProviderCatalogService({
    ProviderManager? providerManager,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _providerManager = providerManager ?? ProviderManager(),
        _clientFactory = clientFactory ?? (() => createPublicHttpsClient());

  static const int maxCatalogBytes = 1024 * 1024;
  static const int maxProviderCodeBytes = 256 * 1024;

  final ProviderManager _providerManager;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout;

  Future<ProviderCatalog> fetchCatalog(
    ProviderRepository repository,
  ) async {
    final bytes = await _getBytes(
      repository.uri,
      maxBytes: maxCatalogBytes,
    );
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw FormatException('Repository catalog is not valid UTF-8 JSON: $error');
    }
    if (decoded is List) {
      return _fetchMangayomiCatalog(repository, decoded);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Repository catalog must be a JSON object.');
    }
    if (decoded['schemaVersion'] != 1) {
      throw FormatException(
        'Unsupported repository schemaVersion: ${decoded['schemaVersion']}.',
      );
    }
    final rawProviders = decoded['providers'];
    if (rawProviders is! List || rawProviders.length > 500) {
      throw const FormatException(
        'Catalog providers must be a list with at most 500 entries.',
      );
    }
    final providers = <JsAnimeProviderManifest>[];
    final identifiers = <String>{};
    for (final raw in rawProviders) {
      if (raw is! Map) {
        throw const FormatException('Every catalog provider must be an object.');
      }
      final manifest = JsAnimeProviderManifest.fromMap(
        Map<String, dynamic>.from(raw),
        repository: repository,
      );
      if (!identifiers.add(manifest.identifier)) {
        throw FormatException(
          'Catalog contains duplicate provider identifier "${manifest.identifier}".',
        );
      }
      providers.add(manifest);
    }
    return ProviderCatalog(
      repository: repository,
      providers: List<JsAnimeProviderManifest>.unmodifiable(providers),
    );
  }

  /// Parses a MangaYomi `index.json` array.
  ///
  /// Entries are skipped rather than fatal: a MangaYomi index mixes Dart and
  /// JavaScript sources, and one Dart entry must not hide the 100 runnable
  /// JavaScript ones around it.
  ProviderCatalog _fetchMangayomiCatalog(
    ProviderRepository repository,
    List<dynamic> rawEntries,
  ) {
    if (rawEntries.length > 2000) {
      throw const FormatException(
        'MangaYomi catalog has too many entries (max 2000).',
      );
    }
    final providers = <JsAnimeProviderManifest>[];
    final identifiers = <String>{};
    for (var index = 0; index < rawEntries.length; index++) {
      final raw = rawEntries[index];
      if (raw is! Map) continue;
      final JsAnimeProviderManifest manifest;
      try {
        manifest = JsAnimeProviderManifest.fromMangayomiMap(
          Map<String, dynamic>.from(raw),
          repository: repository,
          index: index,
        );
      } on FormatException {
        continue;
      }
      if (!identifiers.add(manifest.identifier)) continue;
      providers.add(manifest);
    }
    if (providers.isEmpty) {
      throw const FormatException(
        'This MangaYomi catalog has no JavaScript extensions this app can run. '
        'Its entry may be Dart-only.',
      );
    }
    return ProviderCatalog(
      repository: repository,
      providers: List<JsAnimeProviderManifest>.unmodifiable(providers),
    );
  }

  Future<void> install(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    final existing =
        await _providerManager.getSavedProviderDetails(manifest.identifier);
    if (existing != null) {
      throw StateError('Provider "${manifest.identifier}" is already installed.');
    }
    final verified = await _verifiedCode(repository, manifest);
    await _providerManager.saveProvider(
      _toProviderDetails(repository, manifest, verified, enabled: false),
    );
  }

  Future<void> update(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    final existing =
        await _providerManager.getSavedProviderDetails(manifest.identifier);
    if (existing == null) {
      throw StateError('Provider "${manifest.identifier}" is not installed.');
    }
    if (existing.scriptType.toLowerCase() != 'javascript') {
      throw StateError(
        'A legacy Dart provider with this identifier cannot be replaced.',
      );
    }
    if (existing.repositoryUrl != repository.indexUrl) {
      throw StateError(
        'Provider updates must come from the repository it was installed from.',
      );
    }
    if (JsAnimeProviderManifest.compareVersions(
          manifest.version,
          existing.version,
        ) <=
        0) {
      throw StateError(
        'Catalog version ${manifest.version} is not newer than '
        'installed version ${existing.version}.',
      );
    }
    final verified = await _verifiedCode(repository, manifest);
    await _providerManager.saveProvider(
      _toProviderDetails(
        repository,
        manifest,
        verified,
        enabled: existing.enabled,
      ),
    );
  }

  Future<_VerifiedCode> _verifiedCode(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    if (manifest.repositoryUrl != repository.indexUrl) {
      throw const FormatException(
        'Provider manifest does not belong to this repository.',
      );
    }
    if (manifest.isMangayomi) {
      // MangaYomi indexes carry no digest and may point at a source repo on
      // another host. The URL was already required to be public HTTPS when
      // parsed; pin the digest of what we actually download.
      if (manifest.codeUrl.scheme != 'https') {
        throw const FormatException(
          'MangaYomi source code must be fetched over HTTPS.',
        );
      }
      final bytes = await _getBytes(
        manifest.codeUrl,
        maxBytes: maxProviderCodeBytes,
      );
      return _VerifiedCode(
        code: utf8.decode(bytes),
        sha256: sha256.convert(bytes).toString(),
      );
    }
    if (manifest.codeUrl.host != repository.uri.host ||
        manifest.codeUrl.scheme != 'https') {
      throw const FormatException(
        'Provider manifest does not belong to this HTTPS repository.',
      );
    }
    final bytes = await _getBytes(
      manifest.codeUrl,
      maxBytes: maxProviderCodeBytes,
    );
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != manifest.entrypointSha256) {
      throw const FormatException(
        'Provider code SHA-256 does not match its manifest.',
      );
    }
    return _VerifiedCode(
      code: utf8.decode(bytes),
      sha256: actualHash,
    );
  }

  ProviderDetails _toProviderDetails(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
    _VerifiedCode verified, {
    required bool enabled,
  }) {
    return ProviderDetails(
      name: manifest.name,
      identifier: manifest.identifier,
      version: manifest.version,
      icon: manifest.iconUrl,
      code: verified.code,
      supportDownloads: manifest.supportDownloads,
      scriptType: 'javascript',
      allowedHosts: manifest.allowedHosts,
      contentTypes: manifest.contentTypes,
      enabled: enabled,
      repositoryUrl: repository.indexUrl,
      sourceSha256: verified.sha256,
      format: manifest.format,
      baseUrl: manifest.baseUrl,
      apiUrl: manifest.apiUrl,
      lang: manifest.lang,
      dateFormat: manifest.dateFormat,
      dateFormatLocale: manifest.dateFormatLocale,
    );
  }

  Future<List<int>> _getBytes(
    Uri uri, {
    required int maxBytes,
  }) async {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        !ProviderRepository.isPublicDnsHost(uri.host)) {
      throw const FormatException('Repository requests must use public HTTPS.');
    }
    final client = _clientFactory();
    try {
      final responseFuture = () async {
        final request = http.Request('GET', uri)..followRedirects = false;
        final response = await client.send(request).timeout(requestTimeout);
        if (response.statusCode >= 300 && response.statusCode < 400) {
          throw const FormatException('Repository redirects are not permitted.');
        }
        if (response.statusCode != 200) {
          throw FormatException(
            'Repository request failed with HTTP ${response.statusCode}.',
          );
        }
        final builder = BytesBuilder(copy: false);
        var received = 0;
        await for (final chunk in response.stream.timeout(requestTimeout)) {
          received += chunk.length;
          if (received > maxBytes) {
            throw FormatException(
              'Repository response exceeds $maxBytes bytes.',
            );
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      }();
      return await responseFuture.timeout(
        requestTimeout,
        onTimeout: () {
          client.close();
          throw TimeoutException(
            'Repository request timed out after ${requestTimeout.inSeconds}s.',
          );
        },
      );
    } finally {
      client.close();
    }
  }
}

class _VerifiedCode {
  const _VerifiedCode({required this.code, required this.sha256});

  final String code;
  final String sha256;
}
