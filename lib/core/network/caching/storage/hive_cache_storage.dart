import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'package:animestream/core/network/caching/domain/cache_entry.dart';
import 'package:animestream/core/network/caching/storage/cache_storage.dart';
import 'package:hive/hive.dart';

class CacheEntryAdapter extends TypeAdapter<CacheEntry> {
  @override
  final int typeId = 120;

  @override
  CacheEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CacheEntry(
      key: fields[0] as String? ?? '',
      bodyBytes: (fields[1] as List<dynamic>? ?? []).cast<int>(),
      etag: fields[2] as String?,
      lastModified: fields[3] as String?,
      expiry: fields[4] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  void write(BinaryWriter writer, CacheEntry obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.key)
      ..writeByte(1)
      ..write(obj.bodyBytes)
      ..writeByte(2)
      ..write(obj.etag)
      ..writeByte(3)
      ..write(obj.lastModified)
      ..writeByte(4)
      ..write(obj.expiry);
  }
}

class HiveCacheStorage implements CacheStorage {
  final String boxName;

  HiveCacheStorage({this.boxName = 'network_cache_box'});

  String _safeKey(String key) {
    if (key.length <= 250) return key;
    final hash = md5.convert(utf8.encode(key)).toString();
    return '${key.substring(0, 100)}..._$hash';
  }

  /// A lazy box keeps cached response bodies on disk instead of deserialising
  /// every entry into RAM when the network layer starts.
  Future<LazyBox<CacheEntry>> _getBox() async {
    if (!Hive.isAdapterRegistered(120)) {
      Hive.registerAdapter(CacheEntryAdapter());
    }
    if (Hive.isBoxOpen(boxName)) {
      return Hive.lazyBox<CacheEntry>(boxName);
    }
    return await Hive.openLazyBox<CacheEntry>(boxName);
  }

  @override
  Future<void> init() async {
    await _getBox();
  }

  @override
  Future<CacheEntry?> get(String key) async {
    final box = await _getBox();
    return box.get(_safeKey(key));
  }

  @override
  Future<void> put(String key, CacheEntry entry) async {
    final box = await _getBox();
    final sk = _safeKey(key);
    entry.key = sk;
    await box.put(sk, entry);
  }

  @override
  Future<void> delete(String key) async {
    final box = await _getBox();
    await box.delete(_safeKey(key));
  }

  @override
  Future<int> deleteExpired(DateTime now) async {
    final box = await _getBox();
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final entry = await box.get(key);
      if (entry != null && entry.expiry.isBefore(now)) keysToDelete.add(key);
    }

    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
    }
    return keysToDelete.length;
  }

  @override
  Future<int> getCacheSize() async {
    final box = await _getBox();
    if (box.path != null) {
      final file = File(box.path!);
      if (await file.exists()) {
        return await file.length();
      }
    }
    int totalBytes = 0;
    for (final key in box.keys) {
      final entry = await box.get(key);
      if (entry != null) totalBytes += entry.bodyBytes.length + entry.key.length + 32;
    }
    return totalBytes;
  }

  @override
  Future<void> clear() async {
    final box = await _getBox();
    await box.clear();
  }

  @override
  Future<List<CacheEntry>> getAll() async {
    final box = await _getBox();
    final entries = <CacheEntry>[];
    for (final key in box.keys) {
      final entry = await box.get(key);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  @override
  Future<void> deleteKeys(List<String> keys) async {
    if (keys.isEmpty) return;
    final box = await _getBox();
    await box.deleteAll(keys);
  }
}
