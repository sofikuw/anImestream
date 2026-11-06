import 'dart:io';

import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/manga/apkBridgeConfig.dart';
import 'package:animestream/core/manga/apkBridgeMangaProvider.dart';
import 'package:animestream/core/manga/mangaProvider.dart';

/// In-memory cache of configured ApkBridge sources. Populated by
/// [refreshApkBridgeSources] at startup and whenever settings change.
List<ProviderDetails> apkBridgeMangaSources = <ProviderDetails>[];
final Map<String, ApkBridgeEntry> _apkBridgeEntries = <String, ApkBridgeEntry>{};
String _apkBridgeUrl = 'http://127.0.0.1:8080';

Future<void> refreshApkBridgeSources() async {
  final config = await ApkBridgeConfig.load();
  _apkBridgeUrl = config.bridgeUrl;
  apkBridgeMangaSources = config.entries.map((entry) {
    final id = 'apkbridge_${entry.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}';
    _apkBridgeEntries[id] = entry;
    return ProviderDetails(
      name: entry.name,
      identifier: id,
      version: '0.0.0.0',
      supportDownloads: true,
      scriptType: 'apkbridge',
      contentTypes: const <String>['manga'],
      allowedHosts: const <String>[],
    );
  }).toList(growable: false);
}

bool isApkBridgeSource(String identifier) => _apkBridgeEntries.containsKey(identifier);

MangaChapterProvider? apkBridgeProviderFor(String identifier) {
  final entry = _apkBridgeEntries[identifier];
  if (entry == null) return null;
  final file = File(entry.apkPath);
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  return ApkBridgeMangaProvider(
    bridgeUrl: entry.bridgeUrl ?? _apkBridgeUrl,
    sourceName: entry.name,
    apkBytes: bytes,
    sourceId: identifier,
  );
}

ProviderDetails? apkBridgeSourceFor(String identifier) {
  for (final s in apkBridgeMangaSources) {
    if (s.identifier == identifier) return s;
  }
  return null;
}
