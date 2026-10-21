import 'package:animestream/core/anime/providers/anikoto.dart';
import 'package:animestream/core/anime/providers/animegg.dart';
import 'package:animestream/core/anime/providers/animeonsen.dart';
import 'package:animestream/core/anime/providers/animepahe.dart';
import 'package:animestream/core/anime/providers/anizone.dart';
import 'package:animestream/core/anime/providers/gojo.dart';
import 'package:animestream/core/anime/providers/anidb.dart';
import 'package:animestream/core/anime/providers/animeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/anime/providers/providerPlugin.dart';
import 'package:animestream/core/anime/providers/types.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:flutter/material.dart';

/// This Singleton manages all the sources/providers
/// Contains the list of sources and methods to interact with them
class SourceManager {
  SourceManager._();

  static final SourceManager instance = SourceManager._();

  static final _undownloadableSources = [
    //uses mpd which needs ffmpeg to download (makes the app bulky :< )
    "animeonsen", "anizone"
  ];

  final List<ProviderDetails> inbuiltSources = [
    "AnimeOnsen",
    "AniZone",
    "Anikoto",
    "Animegg",
    "AniDB",
  ]
      .map((e) => ProviderDetails(
          name: e,
          identifier: e.toLowerCase() + "_inbuilt",
          version: "0.0.0.0",
          supportDownloads: !_undownloadableSources.contains(e.toLowerCase())))
      .toList();

  /// Used till complete migration to remote providers is complete.
  bool _useInbuiltProviders = true;

  bool get useInbuiltProviders => _useInbuiltProviders;

  set useInbuiltProviders(bool val) => _useInbuiltProviders = val;

  final List<ProviderDetails> _sources = [];

  final ProviderPlugin _plugin = ProviderPlugin();

  List<ProviderDetails> get sources => _sources;

  /// The built-in providers that are currently in [sources].
  ///
  /// Installed extensions are excluded: removing one of those uninstalls it,
  /// while these are only hidden by settings and reappear unless filtered.
  List<ProviderDetails> get enabledInbuiltSources {
    final identifiers = inbuiltSources.map((p) => p.identifier).toSet();
    return _sources
        .where((provider) => identifiers.contains(provider.identifier))
        .toList(growable: false);
  }

  /// Rebuilds the built-in part of [sources] from the user's disabled list.
  ///
  /// Keeps installed extensions in place and puts the enabled built-ins back at
  /// the front, which is where [loadProviders] expects them. Safe to call more
  /// than once: the previous built-in entries are removed first.
  void applyDisabledInbuiltProviders(Iterable<String> disabled) {
    final disabledSet = disabled.toSet();
    final builtInIdentifiers =
        inbuiltSources.map((provider) => provider.identifier).toSet();
    _sources.removeWhere(
      (provider) => builtInIdentifiers.contains(provider.identifier),
    );
    _sources.insertAll(
      0,
      inbuiltSources.where(
        (provider) => !disabledSet.contains(provider.identifier),
      ),
    );
  }

  void addSource(ProviderDetails source) {
    _sources.add(source);
  }

  void addSources(List<ProviderDetails> sources) {
    _sources.addAll(sources);
  }

  void removeSource(String identifier) {
    _sources.removeWhere((e) => e.identifier == identifier);
  }

  Future<void> loadProviders({bool clearBeforeLoading = true}) async {
    final providers = await ProviderManager().getSavedProviders();
    if (clearBeforeLoading) _sources.clear();
    final builtInIdentifiers =
        inbuiltSources.map((provider) => provider.identifier).toSet();
    _sources.addAll(
      providers.where(
        (provider) =>
            provider.enabled &&
            provider.scriptType.toLowerCase() == 'javascript' &&
            !builtInIdentifiers.contains(provider.identifier),
      ),
    );
  }

  Future<void> refreshInstalledProviders() async {
    final builtInIdentifiers =
        inbuiltSources.map((provider) => provider.identifier).toSet();
    _sources.removeWhere(
      (provider) => !builtInIdentifiers.contains(provider.identifier),
    );
    final installed = await ProviderManager().getSavedProviders();
    _sources.addAll(
      installed
          .where(
            (provider) =>
                provider.enabled &&
                provider.scriptType.toLowerCase() == 'javascript',
          )
          .where(
            (provider) => !builtInIdentifiers.contains(provider.identifier),
          ),
    );
  }

  Future<void> disposeProvider(String identifier) =>
      _plugin.disposeProvider(identifier);

  Future<List<Map<String, String?>>> searchInSource(String source, String query) async {
    if (query.isEmpty) throw new Exception("ERR_EMPTY_QUERY");
    final searchResults = await (await _getProvider(source)).search(query);
    return searchResults;
  }

  Future<List<EpisodeDetails>> getAnimeEpisodes(String source, String link, {bool dub = false}) async {
    final info = await (await _getProvider(source)).getAnimeEpisodeLink(link, dub: dub);

    /// should be list of map corresponding to values of [EpisodeList]
    return info.map((e) => EpisodeDetails.fromMap(e)).toList();
  }

  Future<void> getDownloadSources(String source, String episodeUrl, Function(List<VideoStream>, bool) updateFunction,
      {bool dub = false, String? metadata}) async {
    await (await _getProvider(source)).getDownloadSources(episodeUrl, updateFunction, dub: dub, metadata: metadata);
  }

  Future<void> getStreams(String source, String episodeId, void Function(List<VideoStream>, bool) updateFunction,
      {bool dub = false, String? metadata}) async {
    await (await _getProvider(source)).getStreams(episodeId, updateFunction, dub: dub, metadata: metadata);
  }

  Future<AnimeProvider> _getProvider(String identifier) async {
    if (_useInbuiltProviders) {
      final builtIn =
          inbuiltAnimeProviders[identifier.replaceAll("_inbuilt", "")];
      if (builtIn != null) return builtIn;
    }
    final provider = await _plugin.getProvider(identifier);
    if (provider == null) {
      throw Exception("$identifier Provider doesnt exist!");
    }
    return provider;
  }
}

final Map<String, AnimeProvider> inbuiltAnimeProviders = {
  "animepahe": AnimePahe(),
  "animeonsen": AnimeOnsen(),
  "gojo": Gojo(),
  "anizone": AniZone(),
  "animegg": Animegg(),
  "anikoto": Anikoto(),
  "anidb": AniDB(),
};

/// Compatibility bridge for callers of the old top-level `sources` map.
/// Delete once nothing outside this file references it.
Map<String, AnimeProvider> get sources => inbuiltAnimeProviders;

AnimeProvider getClass(String source) {
  final match = inbuiltAnimeProviders[source.replaceAll("_inbuilt", "")]; // for ignoring _inbuilt suffix
  if (match == null) {
    throw Exception("Invalid Source!");
  }

  return match;
}

/// The entries offered by a source picker.
///
/// Filtered by content type, because a provider manifest declares what it can
/// serve and this list used to ignore that: a MangaDex install appeared in the
/// *anime* source dropdown, where selecting it could only ever fail. The filter
/// reads [ProviderDetails.contentTypes], which defaults to `['anime']` -- so the
/// built-in Dart providers, which never set it, keep behaving exactly as before.
///
/// The default keeps every existing call site working unchanged. A manga source
/// picker passes `contentType: 'manga'`; that is the only hook it needs.
List<DropdownMenuEntry> getSourceDropdownList({String contentType = 'anime'}) {
  List<DropdownMenuEntry> widget = [];
  final sources = SourceManager.instance.sources
      .where((source) => source.contentTypes.contains(contentType));
  int count = 0;
  for (final source in sources) {
    widget.add(
      DropdownMenuEntry(
        value: source,
        label: "${source.name}${source.version == "0.0.0.0" ? "" : " [Plugin]"}",
        trailingIcon:
            source.identifier == currentUserSettings?.preferredProvider ? Icon(Icons.star_border_rounded) : null,
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(appTheme.textMainColor),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              color: appTheme.textMainColor,
              fontFamily: "Rubik",
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
    count = count++;
  }
  return widget;
}
