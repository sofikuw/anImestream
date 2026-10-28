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
    if (decoded is! Map<String, dynamic>) {
      if (decoded is List) {
        throw const FormatException(
          'This is a MangaYomi / Tachiyomi catalog. Their extensions use a '
          'different runtime API (Dart, Kotlin, or a different JavaScript API) '
          'that this app cannot run yet. Add an anImestream-format repository '
          'instead: a JSON object with "schemaVersion" and "providers".',
        );
      }
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

  Future<void> install(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    final existing =
        await _providerManager.getSavedProviderDetails(manifest.identifier);
    if (existing != null) {
      throw StateError('Provider "${manifest.identifier}" is already installed.');
    }
    final code = await _verifiedCode(repository, manifest);
    await _providerManager.saveProvider(
      _toProviderDetails(repository, manifest, code, enabled: false),
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
    final code = await _verifiedCode(repository, manifest);
    await _providerManager.saveProvider(
      _toProviderDetails(
        repository,
        manifest,
        code,
        enabled: existing.enabled,
      ),
    );
  }

  Future<String> _verifiedCode(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    if (manifest.repositoryUrl != repository.indexUrl ||
        manifest.codeUrl.host != repository.uri.host ||
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
    return utf8.decode(bytes);
  }

  ProviderDetails _toProviderDetails(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
    String code, {
    required bool enabled,
  }) {
    return ProviderDetails(
      name: manifest.name,
      identifier: manifest.identifier,
      version: manifest.version,
      code: code,
      supportDownloads: manifest.supportDownloads,
      scriptType: 'javascript',
      allowedHosts: manifest.allowedHosts,
      contentTypes: manifest.contentTypes,
      enabled: enabled,
      repositoryUrl: repository.indexUrl,
      sourceSha256: manifest.entrypointSha256,
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
