import 'package:animestream/core/anime/providers/animeProvider.dart';
import 'package:animestream/core/anime/providers/javascriptAnimeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/extensions/javascript/javascript_provider_http.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
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
    await provider?.dispose();
  }

  /// Release all cached JavaScript contexts.
  Future<void> disposeAll() async {
    final providers = _compiledProviders.values.toList(growable: false);
    _compiledProviders.clear();
    await Future.wait(providers.map((provider) => provider.dispose()));
  }
}
