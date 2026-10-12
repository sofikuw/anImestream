import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/extension_catalog.dart';
import '../models/extension_manifest.dart';
import '../runtime/js_runtime_bridge.dart';
import 'safe_installer.dart';

/// Central Manager coordinating installed JavaScript extensions,
/// execution contexts, persistence, and safe runtime invocation.
class ExtensionManager extends ChangeNotifier {
  static final ExtensionManager _instance = ExtensionManager._internal();
  factory ExtensionManager() => _instance;
  ExtensionManager._internal();

  final Map<String, InstalledExtensionBundle> _installed = {};
  final Map<String, JsRuntimeBridge> _activeContexts = {};
  bool _isInitialized = false;

  Map<String, InstalledExtensionBundle> get installedExtensions =>
      Map.unmodifiable(_installed);

  List<InstalledExtensionBundle> get animeExtensions => _installed.values
      .where((e) => e.isEnabled && (e.manifest.type == ExtensionType.anime || e.manifest.type == ExtensionType.both))
      .toList();

  List<InstalledExtensionBundle> get mangaExtensions => _installed.values
      .where((e) => e.isEnabled && (e.manifest.type == ExtensionType.manga || e.manifest.type == ExtensionType.both))
      .toList();

  bool isInstalled(String id) => _installed.containsKey(id);

  /// Initializes installed extensions and seeds default providers if none exist.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Seed initial recommended dynamic extensions
    if (_installed.isEmpty) {
      _seedDefaultExtensions();
    }

    // Warm up active enabled extensions
    for (final bundle in _installed.values) {
      if (bundle.isEnabled) {
        await _ensureContextLoaded(bundle);
      }
    }

    notifyListeners();
  }

  /// Installs an extension from a catalog item with validation.
  Future<bool> installExtension(
    ExtensionCatalogItem item, {
    void Function(InstallProgress)? onProgress,
  }) async {
    try {
      final existing = _installed[item.id];
      final newBundle = await SafeExtensionInstaller.installOrUpdate(
        item: item,
        currentBundle: existing,
        onProgress: onProgress,
      );

      _installed[item.id] = newBundle;
      await _reloadContext(newBundle);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[ExtensionManager] Install failed for ${item.id}: $e');
      onProgress?.call(InstallProgress(
        extensionId: item.id,
        status: 'Installation failed: $e',
        error: e.toString(),
      ));
      return false;
    }
  }

  /// Updates an already installed extension.
  Future<bool> updateExtension(
    ExtensionCatalogItem item, {
    void Function(InstallProgress)? onProgress,
  }) async {
    return installExtension(item, onProgress: onProgress);
  }

  /// Toggles an extension between enabled and disabled states.
  Future<void> toggleExtension(String id, bool enable) async {
    final bundle = _installed[id];
    if (bundle == null) return;

    _installed[id] = bundle.copyWith(isEnabled: enable);

    if (!enable) {
      final bridge = _activeContexts.remove(id);
      await bridge?.dispose();
    } else {
      await _ensureContextLoaded(_installed[id]!);
    }

    notifyListeners();
  }

  /// Uninstalls and completely cleans up an extension.
  Future<void> uninstallExtension(String id) async {
    final bridge = _activeContexts.remove(id);
    await bridge?.dispose();
    _installed.remove(id);
    notifyListeners();
  }

  /// Calls a function on an extension, ensuring proper error containment and timeouts.
  Future<JsExecutionResult> invokeExtension(
    String extensionId,
    String functionName, [
    List<dynamic> args = const [],
  ]) async {
    final bundle = _installed[extensionId];
    if (bundle == null) {
      return JsExecutionResult.error('Extension $extensionId is not installed');
    }
    if (!bundle.isEnabled) {
      return JsExecutionResult.error('Extension $extensionId is disabled');
    }

    final bridge = await _ensureContextLoaded(bundle);
    return await bridge.callFunction(functionName, args);
  }

  Future<JsRuntimeBridge> _ensureContextLoaded(InstalledExtensionBundle bundle) async {
    final id = bundle.manifest.id;
    if (_activeContexts.containsKey(id)) {
      return _activeContexts[id]!;
    }

    final bridge = JsRuntimeBridge(contextId: 'ext_$id');
    await bridge.initialize();
    await bridge.evaluate(bundle.javascriptCode);
    _activeContexts[id] = bridge;
    return bridge;
  }

  Future<void> _reloadContext(InstalledExtensionBundle bundle) async {
    final id = bundle.manifest.id;
    final old = _activeContexts.remove(id);
    await old?.dispose();
    if (bundle.isEnabled) {
      await _ensureContextLoaded(bundle);
    }
  }

  void _seedDefaultExtensions() {
    // Seed GogoAnime (Anime)
    const gogoManifest = ExtensionManifest(
      id: 'animestream_gogoanime',
      name: 'GogoAnime',
      version: '1.2.0',
      apiVersion: '1.0.0',
      type: ExtensionType.anime,
      author: 'Animestream Community',
      description: 'Stream anime with multiple server mirrors.',
      iconUrl: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=128',
      lang: 'en',
      entrypoint: 'index.js',
      capabilities: {
        ExtensionCapability.searchAnime,
        ExtensionCapability.popularAnime,
        ExtensionCapability.animeDetails,
        ExtensionCapability.episodes,
        ExtensionCapability.videoSources,
      },
    );

    // Seed MangaDex (Manga)
    const mangadexManifest = ExtensionManifest(
      id: 'animestream_mangadex',
      name: 'MangaDex',
      version: '1.1.4',
      apiVersion: '1.0.0',
      type: ExtensionType.manga,
      author: 'Mangayomi Community',
      description: 'Extensive multi-language manga titles and high quality reader.',
      iconUrl: 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=128',
      lang: 'en',
      entrypoint: 'index.js',
      capabilities: {
        ExtensionCapability.searchManga,
        ExtensionCapability.popularManga,
        ExtensionCapability.latestManga,
        ExtensionCapability.mangaDetails,
        ExtensionCapability.chapters,
        ExtensionCapability.mangaPages,
      },
    );

    _installed[gogoManifest.id] = InstalledExtensionBundle(
      manifest: gogoManifest,
      javascriptCode: SafeExtensionInstaller._generateDefaultExtensionJs(gogoManifest),
      isEnabled: true,
      installedAt: DateTime.now(),
    );

    _installed[mangadexManifest.id] = InstalledExtensionBundle(
      manifest: mangadexManifest,
      javascriptCode: SafeExtensionInstaller._generateDefaultExtensionJs(mangadexManifest),
      isEnabled: true,
      installedAt: DateTime.now(),
    );
  }
}
