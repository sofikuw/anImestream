import 'dart:convert';

import 'package:animestream/core/anime/providers/providerCatalogService.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ProviderRepository', () {
    test('accepts public HTTPS index URLs and rejects unsafe schemes/hosts', () {
      expect(
        ProviderRepository.fromIndexUrl(
          'https://repo.example.test/providers/index.json',
        ).name,
        'repo.example.test/providers/index.json',
      );
      expect(
        () => ProviderRepository.fromIndexUrl(
          'http://repo.example.test/index.json',
        ),
        throwsFormatException,
      );
      expect(
        () => ProviderRepository.fromIndexUrl(
          'https://127.0.0.1/index.json',
        ),
        throwsFormatException,
      );
      expect(
        () => ProviderRepository.fromIndexUrl(
          'https://repo.example.test/index.json?x=1',
        ),
        throwsFormatException,
      );
    });

    test('validates versioned anime manifests and resolves local entrypoints',
        () {
      final repository = ProviderRepository.fromIndexUrl(
        'https://repo.example.test/providers/index.json',
      );
      final manifest = JsAnimeProviderManifest.fromMap(
        _manifest(hash: List<String>.filled(64, 'b').join()),
        repository: repository,
      );

      expect(manifest.identifier, 'sample');
      expect(manifest.codeUrl.toString(),
          'https://repo.example.test/providers/sample.js');
      expect(manifest.allowedHosts, const <String>['api.example.test']);
      expect(
        JsAnimeProviderManifest.compareVersions('1.10.0', '1.9.9'),
        greaterThan(0),
      );
    });

    test('rejects unsupported schema versions and path traversal', () {
      final repository =
          ProviderRepository.fromIndexUrl('https://repo.example.test/index.json');
      expect(
        () => JsAnimeProviderManifest.fromMap(
          _manifest(
            hash: List<String>.filled(64, 'b').join(),
            manifestVersion: 2,
          ),
          repository: repository,
        ),
        throwsFormatException,
      );
      expect(
        () => JsAnimeProviderManifest.fromMap(
          _manifest(
            hash: List<String>.filled(64, 'b').join(),
            entrypoint: '../outside.js',
          ),
          repository: repository,
        ),
        throwsFormatException,
      );
    });
  });

  group('ProviderCatalogService', () {
    test('fetches a catalog and installs hash-verified code disabled', () async {
      const code = 'module.exports = { search: async () => [] };';
      final codeHash = sha256.convert(utf8.encode(code)).toString();
      final repository =
          ProviderRepository.fromIndexUrl('https://repo.example.test/index.json');
      final catalogBody = jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'providers': <Object?>[_manifest(hash: codeHash)],
      });
      final manager = _MemoryProviderManager();
      final service = ProviderCatalogService(
        providerManager: manager,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/index.json') {
            return http.Response(catalogBody, 200);
          }
          if (request.url.path == '/sample.js') {
            return http.Response(code, 200);
          }
          return http.Response('not found', 404);
        }),
      );

      final catalog = await service.fetchCatalog(repository);
      await service.install(repository, catalog.providers.single);

      final saved = await manager.getSavedProviderDetails('sample');
      expect(catalog.providers, hasLength(1));
      expect(saved?.code, code);
      expect(saved?.enabled, isFalse);
      expect(saved?.sourceSha256, codeHash);
      expect(saved?.repositoryUrl, repository.indexUrl);
    });

    test('does not install source whose digest differs from the manifest',
        () async {
      const code = 'module.exports = { search: async () => [] };';
      final repository =
          ProviderRepository.fromIndexUrl('https://repo.example.test/index.json');
      final manager = _MemoryProviderManager();
      final service = ProviderCatalogService(
        providerManager: manager,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/index.json') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'providers': <Object?>[
                  _manifest(hash: List<String>.filled(64, '0').join()),
                ],
              }),
              200,
            );
          }
          return http.Response(code, 200);
        }),
      );

      final catalog = await service.fetchCatalog(repository);
      await expectLater(
        service.install(repository, catalog.providers.single),
        throwsFormatException,
      );
      expect(manager.providers, isEmpty);
    });

    test('updates from its original repository and preserves enable state',
        () async {
      const code = 'module.exports = { search: async () => ["updated"] };';
      final codeHash = sha256.convert(utf8.encode(code)).toString();
      final repository =
          ProviderRepository.fromIndexUrl('https://repo.example.test/index.json');
      final manager = _MemoryProviderManager();
      manager.providers['sample'] = ProviderDetails(
        name: 'Sample Anime',
        identifier: 'sample',
        version: '1.0.0',
        code: 'old source',
        scriptType: 'javascript',
        enabled: true,
        repositoryUrl: repository.indexUrl,
      );
      final manifest = _manifest(hash: codeHash);
      manifest['version'] = '1.1.0';
      final service = ProviderCatalogService(
        providerManager: manager,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/index.json') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'providers': <Object?>[manifest],
              }),
              200,
            );
          }
          return http.Response(code, 200);
        }),
      );

      final catalog = await service.fetchCatalog(repository);
      await service.update(repository, catalog.providers.single);

      final saved = manager.providers['sample'];
      expect(saved?.version, '1.1.0');
      expect(saved?.code, code);
      expect(saved?.enabled, isTrue);
      expect(saved?.sourceSha256, codeHash);
    });
  });

  group('MangaYomi catalogs', () {
    const code = 'class DefaultExtension extends MProvider {}';
    const codeUrl = 'https://raw.example.test/manga/src/en/pill.js';

    Map<String, Object?> entry({
      bool isManga = true,
      String sourceCodeUrl = codeUrl,
      Object? version = '0.1.3',
    }) {
      return <String, Object?>{
        'name': 'MangaPill',
        'id': 1,
        'baseUrl': 'https://source.example.test',
        'apiUrl': 'https://api.source.example.test',
        'lang': 'en',
        'isManga': isManga,
        'version': version,
        'sourceCodeUrl': sourceCodeUrl,
        'sourceCodeLanguage': 1,
      };
    }

    test('maps an entry onto the manifest shape', () {
      final repository = ProviderRepository.fromIndexUrl(
        'https://repo.example.test/index.json',
      );
      final manifest = JsAnimeProviderManifest.fromMangayomiMap(
        entry(),
        repository: repository,
        index: 0,
      );

      expect(manifest.format, 'mangayomi');
      expect(manifest.contentTypes, const <String>['manga']);
      expect(manifest.version, '0.1.3');
      expect(manifest.identifier, startsWith('mg-'));
      expect(manifest.allowedHosts, contains('source.example.test'));
      expect(manifest.allowedHosts, contains('api.source.example.test'));
      expect(manifest.codeUrl.toString(), codeUrl);
    });

    test('skips Dart entries but keeps JavaScript ones', () async {
      final repository = ProviderRepository.fromIndexUrl(
        'https://repo.example.test/index.json',
      );
      final manager = _MemoryProviderManager();
      final service = ProviderCatalogService(
        providerManager: manager,
        clientFactory: () => MockClient((request) async {
          if (request.url.path == '/index.json') {
            return http.Response(
              jsonEncode(<Object?>[
                entry(
                  sourceCodeUrl:
                      'https://raw.example.test/manga/src/en/pill.dart',
                ),
                entry(),
              ]),
              200,
            );
          }
          return http.Response(code, 200);
        }),
      );

      final catalog = await service.fetchCatalog(repository);
      expect(catalog.providers, hasLength(1));
      expect(catalog.providers.single.format, 'mangayomi');

      await service.install(repository, catalog.providers.single);
      final saved = manager.providers[catalog.providers.single.identifier];
      expect(saved?.code, code);
      expect(saved?.format, 'mangayomi');
      expect(saved?.contentTypes, const <String>['manga']);
    });
  });
}

Map<String, dynamic> _manifest({
  required String hash,
  int manifestVersion = 1,
  String entrypoint = 'sample.js',
}) {
  return <String, dynamic>{
    'manifestVersion': manifestVersion,
    'name': 'Sample Anime',
    'identifier': 'sample',
    'version': '1.0.0',
    'scriptType': 'javascript',
    'contentTypes': <String>['anime'],
    'entrypoint': entrypoint,
    'entrypointSha256': hash,
    'allowedHosts': <String>['api.example.test'],
    'supportDownloads': false,
  };
}

class _MemoryProviderManager extends ProviderManager {
  final Map<String, ProviderDetails> providers = <String, ProviderDetails>{};

  @override
  Future<ProviderDetails?> getSavedProviderDetails(String identifier) async =>
      providers[identifier];

  @override
  Future<void> saveProvider(ProviderDetails provider) async {
    providers[provider.identifier] = provider;
  }
}
