import 'package:flutter_test/flutter_test.dart';
import '../lib/core/extensions/models/extension_manifest.dart';
import '../lib/core/extensions/models/extension_catalog.dart';
import '../lib/core/extensions/runtime/js_runtime_bridge.dart';
import '../lib/core/extensions/manager/extension_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExtensionManifest Tests', () {
    test('Valid manifest passes validation', () {
      const manifest = ExtensionManifest(
        id: 'test_extension',
        name: 'Test Source',
        version: '1.0.0',
        apiVersion: '1.0.0',
        type: ExtensionType.anime,
        author: 'Tester',
        description: 'Test description',
        iconUrl: 'https://example.com/icon.png',
        lang: 'en',
        entrypoint: 'index.js',
        capabilities: {ExtensionCapability.searchAnime},
      );

      final errors = manifest.validate();
      expect(errors, isEmpty);
      expect(manifest.isCompatibleWith('1.0.0'), isTrue);
    });

    test('Invalid manifest triggers schema errors', () {
      const invalidManifest = ExtensionManifest(
        id: 'INVALID ID WITH SPACES',
        name: '',
        version: 'not-semver',
        apiVersion: '0.1.0',
        type: ExtensionType.manga,
        author: 'Tester',
        description: '',
        iconUrl: '',
        lang: 'en',
        entrypoint: '',
        capabilities: {},
      );

      final errors = invalidManifest.validate();
      expect(errors.length, greaterThanOrEqualTo(3));
      expect(invalidManifest.isCompatibleWith('1.0.0'), isFalse);
    });
  });

  group('ExtensionCatalog Tests', () {
    test('Parses repository catalog index correctly', () {
      final json = {
        'name': 'Official Community Repo',
        'formatVersion': '1.0.0',
        'description': 'Main repo',
        'extensions': [
          {
            'id': 'gogo_anime',
            'name': 'GogoAnime',
            'version': '1.2.0',
            'apiVersion': '1.0.0',
            'type': 'anime',
            'description': 'Anime provider',
            'author': 'Community',
            'iconUrl': 'icon.png',
            'lang': 'en',
            'manifestUrl': 'manifest.json',
            'codeUrl': 'index.js',
            'capabilities': ['searchAnime', 'videoSources'],
          }
        ]
      };

      final repo = ExtensionRepository.fromJson(json, 'https://example.com/repo');
      expect(repo.name, 'Official Community Repo');
      expect(repo.items.length, 1);
      expect(repo.items.first.id, 'gogo_anime');
      expect(repo.items.first.manifestUrl, 'https://example.com/repo/manifest.json');
    });
  });

  group('JsRuntimeBridge Tests', () {
    test('Context initializes and cleans up gracefully', () async {
      final bridge = JsRuntimeBridge(contextId: 'test_ctx_1');
      await bridge.initialize();
      expect(bridge.contextId, 'test_ctx_1');
      await bridge.dispose();
    });

    test('Handles fallback execution without crashing', () async {
      final bridge = JsRuntimeBridge(contextId: 'test_ctx_2');
      await bridge.initialize();
      final res = await bridge.evaluate('var a = 10; a * 2;');
      expect(res.isSuccess, isTrue);
      await bridge.dispose();
    });
  });

  group('ExtensionManager Lifecycle Tests', () {
    test('Initializes default providers and allows disable/enable', () async {
      final manager = ExtensionManager();
      await manager.initialize();

      expect(manager.installedExtensions.isNotEmpty, isTrue);
      final gogoId = 'animestream_gogoanime';
      expect(manager.isInstalled(gogoId), isTrue);

      // Disable
      await manager.toggleExtension(gogoId, false);
      expect(manager.installedExtensions[gogoId]!.isEnabled, isFalse);

      // Re-enable
      await manager.toggleExtension(gogoId, true);
      expect(manager.installedExtensions[gogoId]!.isEnabled, isTrue);
    });
  });
}
