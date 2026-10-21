import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/data/settings.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/ui/models/sources.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:flutter/material.dart';

/// Settings for the providers that ship with the app.
///
/// This page deliberately does not touch installed extensions: those are
/// uninstalled from "Manage Providers". Removing a built-in here only hides it,
/// which is why the disabled list has to be applied again on every launch.
class BuiltInProvidersPage extends StatefulWidget {
  const BuiltInProvidersPage({super.key});

  @override
  State<BuiltInProvidersPage> createState() => _BuiltInProvidersPageState();
}

class _BuiltInProvidersPageState extends State<BuiltInProvidersPage> {
  bool _loaded = false;
  final Set<String> _disabledProviders = <String>{};
  final Set<String> _disabledMetadata = <String>{};
  final Set<String> _fallbacks = <String>{'mal', 'kitsu'};

  static const List<String> _metadataProviders = <String>[
    'anilist',
    'mal',
    'simkl',
  ];

  static const List<String> _fallbackProviders = <String>['mal', 'kitsu'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await Settings().getSettings();
    _disabledProviders
      ..clear()
      ..addAll(settings.disabledProviders ?? const <String>[]);
    _disabledMetadata
      ..clear()
      ..addAll(settings.disabledMetadataProviders ?? const <String>[]);
    _fallbacks
      ..clear()
      ..addAll(settings.metadataFallbacks ?? const <String>['mal', 'kitsu']);
    if (mounted) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    await Settings().writeSettings(
      SettingsModal(
        disabledProviders: _disabledProviders.toList(growable: false),
        disabledMetadataProviders:
            _disabledMetadata.toList(growable: false),
        metadataFallbacks: _fallbackProviders
            .where(_fallbacks.contains)
            .toList(growable: false),
      ),
    );

    SourceManager.instance.applyDisabledInbuiltProviders(_disabledProviders);
    await _repairDefaults();

    if (mounted) setState(() {});
  }

  /// Keeps the "default provider" and "default database" settings pointing at
  /// something that is still enabled.
  Future<void> _repairDefaults() async {
    final preferred = currentUserSettings?.preferredProvider;
    final available = SourceManager.instance.sources;
    if (preferred != null && _disabledProviders.contains(preferred)) {
      await Settings().writeSettings(
        SettingsModal(
          preferredProvider:
              available.isEmpty ? null : available.first.identifier,
        ),
      );
    }

    final database = currentUserSettings?.database ?? Databases.anilist;
    if (_disabledMetadata.contains('anilist')) {
      // AniList is also the wrapper that routes to the fallbacks. Keep it as
      // the logical database even when its own API is disabled, otherwise a
      // switch to MAL would call MAL's unimplemented search path instead.
      if (database != Databases.anilist) {
        await Settings().writeSettings(
          SettingsModal(database: Databases.anilist),
        );
      }
    } else if (_disabledMetadata.contains(database.name)) {
      for (final candidate in Databases.values) {
        if (!_disabledMetadata.contains(candidate.name)) {
          await Settings().writeSettings(
            SettingsModal(database: candidate),
          );
          break;
        }
      }
    }
  }

  void _toggleProvider(String identifier, bool enabled) {
    setState(() {
      if (enabled) {
        _disabledProviders.remove(identifier);
      } else {
        _disabledProviders.add(identifier);
      }
    });
    _save();
  }

  void _toggleMetadata(String name, bool enabled) {
    setState(() {
      if (enabled) {
        _disabledMetadata.remove(name);
      } else {
        _disabledMetadata.add(name);
      }
      if (!enabled) {
        // A disabled metadata database cannot answer a fallback request.
        _fallbacks.remove(name);
        if (name == 'anilist' && _fallbacks.isEmpty) {
          // AniList is the only primary source. Keep at least one fallback so
          // search does not silently become empty.
          _fallbacks.add(_disabledMetadata.contains('mal') ? 'kitsu' : 'mal');
        }
      }
    });
    _save();
  }

  void _toggleFallback(String id, bool enabled) {
    setState(() {
      if (enabled) {
        _fallbacks.add(id);
      } else {
        _fallbacks.remove(id);
      }
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: pagePadding(context, bottom: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    settingPagesTitleHeader(context, "Built-in providers"),
                    _note(
                      "Removing a built-in provider hides it everywhere. "
                      "Installed extensions are managed from Manage Providers.",
                    ),
                    _sectionTitle("Streaming"),
                    for (final provider in SourceManager.instance.inbuiltSources)
                      _switch(
                        title: provider.name,
                        subtitle: provider.identifier,
                        value: !_disabledProviders.contains(provider.identifier),
                        onChanged: (value) =>
                            _toggleProvider(provider.identifier, value),
                      ),
                    if (SourceManager.instance.inbuiltSources.every(
                      (provider) =>
                          _disabledProviders.contains(provider.identifier),
                    ))
                      _note(
                        "No built-in streaming provider is enabled. "
                        "Install an extension or re-enable one to play episodes.",
                      ),
                    _sectionTitle("Metadata"),
                    for (final name in _metadataProviders)
                      _switch(
                        title: _metadataName(name),
                        subtitle: _metadataDescription(name),
                        value: !_disabledMetadata.contains(name),
                        onChanged: (value) => _toggleMetadata(name, value),
                      ),
                    _sectionTitle("Metadata fallbacks"),
                    _note(
                      "Used when AniList is unavailable, in this order: "
                      "MyAnimeList, then Kitsu. Manga fallbacks use the same "
                      "providers.",
                    ),
                    for (final id in _fallbackProviders)
                      _switch(
                        title: _metadataName(id),
                        subtitle: id == 'mal' && _disabledMetadata.contains('mal')
                            ? "Enable MyAnimeList under Metadata first"
                            : id == 'mal'
                                ? "MyAnimeList search, browse and details"
                                : "Kitsu search, browse and details",
                        value: _fallbacks.contains(id),
                        onChanged: (value) => _toggleFallback(id, value),
                      ),
                    if (_fallbacks.isEmpty)
                      _note(
                        "No metadata fallback is enabled. If AniList is down, "
                        "search and Discover will show an error instead.",
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 30, bottom: 10, left: 10),
      child: Text(
        title,
        style: textStyle().copyWith(fontSize: 21, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _note(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10),
      child: Text(
        text,
        style: textStyle().copyWith(
          fontSize: 14,
          color: appTheme.textMainColor.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      activeThumbColor: appTheme.accentColor,
      title: Text(title, style: textStyle().copyWith(fontSize: 17)),
      subtitle: Text(
        subtitle,
        style: textStyle().copyWith(
          fontSize: 13,
          color: appTheme.textMainColor.withValues(alpha: 0.65),
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  static String _metadataName(String id) {
    switch (id) {
      case 'anilist':
        return 'AniList';
      case 'mal':
        return 'MyAnimeList';
      case 'kitsu':
        return 'Kitsu';
      case 'simkl':
        return 'Simkl';
      default:
        return id;
    }
  }

  static String _metadataDescription(String id) {
    switch (id) {
      case 'anilist':
        return 'Primary source for anime and manga';
      case 'mal':
        return 'Anime and manga metadata, also used as a fallback';
      case 'simkl':
        return 'Anime metadata';
      default:
        return '';
    }
  }
}
