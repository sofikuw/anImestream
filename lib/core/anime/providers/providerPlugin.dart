import 'package:animestream/core/anime/providers/animeProvider.dart';
import 'package:animestream/core/anime/providers/javascriptAnimeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/extensions/javascript/javascript_provider_http.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:animestream/core/extensions/mangayomi/mangayomi_providers.dart';
import 'package:http/http.dart' as http;

/// Creates and caches adapters for installed JavaScript anime providers.
class ProviderPlugin {
  ProviderPlugin({
    ProviderManager? providerManager,
    http.Client Function()? clientFactory,
  })  : _providerManager = providerManager ?? ProviderManager(),
        _clientFactory = clientFactory;

  final ProviderManager _providerManager;
  final http.Client Function()? _clientFactory;
  final Map<String, JavaScriptAnimeProvider> _compiledProviders =
      <String, JavaScriptAnimeProvider>{};
  final Map<String, MangayomiAnimeProvider> _mangayomiProviders =
      <String, MangayomiAnimeProvider>{};

  Future<AnimeProvider?> getProvider(
    String provider, {
    String? testCode,
  }) async {
    if (provider.trim().isEmpty && testCode == null) return null;

    if (testCode == null) {
      final cached = _compiledProviders[provider];
      if (cached != null) {
        if (cached.isUsable) return cached;
        _compiledProviders.remove(provider);
        await cached.dispose();
      }
      final cachedMangayomi = _mangayomiProviders[provider];
      if (cachedMangayomi != null) {
        if (cachedMangayomi.isUsable) return cachedMangayomi;
        _mangayomiProviders.remove(provider);
        await cachedMangayomi.dispose();
      }
    }

    final details = testCode == null
        ? await _providerManager.getSavedProviderDetails(provider)
        : ProviderDetails(
            name: provider,
            identifier: provider,
            version: 'test',
            code: testCode,
            scriptType: 'javascript',
          );
    if (details == null ||
        details.scriptType.toLowerCase() != 'javascript' ||
        !details.enabled ||
        details.code == null ||
        details.code!.trim().isEmpty) {
      return null;
    }

    if (details.isMangayomi) {
      if (testCode != null) return null;
      final adapter = MangayomiAnimeProvider(details);
      _mangayomiProviders[provider] = adapter;
      return adapter;
    }

    final httpBridge = JavaScriptProviderHttp(
      allowedHosts: details.allowedHosts,
      clientFactory: _clientFactory,
    );
    final runtime = JavaScriptRuntime(
      httpRequestHandler: httpBridge.request,
    );
    final adapter = JavaScriptAnimeProvider(
      details: details,
      runtime: runtime,
    );
    if (testCode == null) _compiledProviders[provider] = adapter;
    return adapter;
  }

  /// Release one cached provider's JavaScript context.
  Future<void> disposeProvider(String identifier) async {
    final provider = _compiledProviders.remove(identifier);
    final mangayomi = _mangayomiProviders.remove(identifier);
    await provider?.dispose();
    await mangayomi?.dispose();
  }

  /// Release all cached JavaScript contexts.
  Future<void> disposeAll() async {
    final providers = _compiledProviders.values.toList(growable: false);
    final mangayomi = _mangayomiProviders.values.toList(growable: false);
    _compiledProviders.clear();
    _mangayomiProviders.clear();
    await Future.wait(<Future<void>>[
      ...providers.map((provider) => provider.dispose()),
      ...mangayomi.map((provider) => provider.dispose()),
    ]);
  }
}
