import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted configuration for the ApkBridge integration.
class ApkBridgeEntry {
  final String name;
  final String apkPath;
  final String? bridgeUrl;

  const ApkBridgeEntry({
    required this.name,
    required this.apkPath,
    this.bridgeUrl,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'apkPath': apkPath,
        if (bridgeUrl != null) 'bridgeUrl': bridgeUrl,
      };

  factory ApkBridgeEntry.fromJson(Map<String, dynamic> json) => ApkBridgeEntry(
        name: (json['name'] ?? '').toString(),
        apkPath: (json['apkPath'] ?? '').toString(),
        bridgeUrl: json['bridgeUrl']?.toString(),
      );
}

class ApkBridgeConfig {
  ApkBridgeConfig({this.bridgeUrl = 'http://127.0.0.1:8080', this.entries = const <ApkBridgeEntry>[]});

  String bridgeUrl;
  List<ApkBridgeEntry> entries;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/apkbridge_config.json');
  }

  static Future<ApkBridgeConfig> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return ApkBridgeConfig();
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return ApkBridgeConfig();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return ApkBridgeConfig();
      return ApkBridgeConfig(
        bridgeUrl: (json['bridgeUrl'] ?? 'http://127.0.0.1:8080').toString(),
        entries: (json['entries'] is List)
            ? (json['entries'] as List)
                .whereType<Map>()
                .map((e) => ApkBridgeEntry.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const <ApkBridgeEntry>[],
      );
    } catch (_) {
      return ApkBridgeConfig();
    }
  }

  Future<void> save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode(<String, dynamic>{
      'bridgeUrl': bridgeUrl,
      'entries': entries.map((e) => e.toJson()).toList(),
    }));
  }
}
