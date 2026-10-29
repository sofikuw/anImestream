// The manga sources compiled into the app.
//
// This mirrors `inbuiltAnimeProviders` in `lib/ui/models/sources.dart`: the
// entry is available without installing anything, cannot be uninstalled, and
// is offered next to the installed JavaScript extensions. The `_inbuilt`
// suffix keeps its identifier distinct from a same-named extension, so a user
// who also installed `weebcentral-js` keeps both entries instead of one
// silently shadowing the other.

import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/providers/mangapill.dart';
import 'package:animestream/core/manga/providers/weebcentral.dart';

/// Manifests for the inbuilt manga sources, in the order they are offered.
///
/// `scriptType: 'dart'` is the marker the manga side uses to tell these apart
/// from installed JavaScript extensions: there is no code to load and no
/// runtime to spin up.
final List<ProviderDetails> inbuiltMangaSources = List<ProviderDetails>.unmodifiable(
  <ProviderDetails>[
    ProviderDetails(
      name: 'WeebCentral',
      identifier: 'weebcentral_inbuilt',
      version: '0.0.0.0',
      supportDownloads: true,
      scriptType: 'dart',
      contentTypes: const <String>['manga'],
      allowedHosts: const <String>['weebcentral.com'],
    ),
    ProviderDetails(
      name: 'MangaPill',
      identifier: 'mangapill_inbuilt',
      version: '0.0.0.0',
      supportDownloads: true,
      scriptType: 'dart',
      contentTypes: const <String>['manga'],
      allowedHosts: const <String>['mangapill.com'],
    ),
  ],
);

/// Constructors, not instances: a [MangaChapterProvider] is disposed by the
/// page that opened it, so a shared singleton would be dead after one visit.
final Map<String, MangaChapterProvider Function()> _inbuiltMangaFactories =
    <String, MangaChapterProvider Function()>{
  'weebcentral_inbuilt': WeebCentralMangaProvider.new,
  'mangapill_inbuilt': MangaPillMangaProvider.new,
};

bool isInbuiltMangaSource(String identifier) =>
    _inbuiltMangaFactories.containsKey(identifier);

/// A fresh inbuilt provider for [identifier], or null when it is not one.
MangaChapterProvider? inbuiltMangaProviderFor(String identifier) {
  final factory = _inbuiltMangaFactories[identifier];
  return factory?.call();
}

/// The manifest for [identifier] when it names an inbuilt source.
ProviderDetails? inbuiltMangaSourceFor(String identifier) {
  for (final source in inbuiltMangaSources) {
    if (source.identifier == identifier) return source;
  }
  return null;
}
