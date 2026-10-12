import 'dart:convert';

import 'package:animestream/core/anime/providers/animeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/types.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';

/// Adapts a CommonJS-style JavaScript anime provider to [AnimeProvider].
///
/// Provider code exports an object with `search`, `getAnimeEpisodeLink`,
/// `getStreams`, and optionally `getDownloadSources` methods. Each method is
/// called as `(input, api)` and may be async. The `api.request` capability is
/// HTTPS-only and limited to the provider's exact `allowedHosts`.
///
/// The method inputs mirror [AnimeProvider]: search receives `{query}`,
/// episode lookup receives `{aliasId, dub}`, stream lookup receives
/// `{episodeId, dub, metadata}`, and downloads receive
/// `{episodeUrl, dub, metadata}`. Search results use `{name, alias, imageUrl}`;
/// episodes use `episodeLink` and integer `episodeNumber`; streams use
/// `quality`, `url`, optional `server`, and optional `backup`. `api.request`
/// accepts `{url, method?, headers?, body?}` and returns
/// `{statusCode, headers, body}` with the response body as text.
///
/// Example:
/// ```javascript
/// module.exports = {
///   async search({ query }, api) {
///     const response = await api.request({
///       url: `https://catalog.example.test/search?q=${encodeURIComponent(query)}`
///     });
///     return JSON.parse(response.body).map(item => ({
///       name: item.title,
///       alias: item.url,
///       imageUrl: item.cover
///     }));
///   }
/// };
/// ```
///
/// QuickJS enforces a native execution deadline and heap cap. The adapter still
/// exposes only the app's narrow, per-provider HTTP capability.
class JavaScriptAnimeProvider implements AnimeProvider {
  JavaScriptAnimeProvider({
    required this.details,
    required JavaScriptRuntime runtime,
  }) : _runtime = runtime;

  final ProviderDetails details;
  final JavaScriptRuntime _runtime;

  Future<void>? _loadFuture;
  int _requestSequence = 0;
  bool _disposed = false;

  bool get isUsable => !_disposed && !_runtime.isDisposed;

  @override
  String get providerName => details.name;

  /// Load provider source once into this provider's isolated JS runtime.
  Future<void> ensureLoaded() {
    if (_disposed || _runtime.isDisposed) {
      return Future<void>.error(
        StateError('The JavaScript provider has been disposed.'),
      );
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final code = details.code;
    if (code == null || code.trim().isEmpty) {
      throw StateError('Provider "${details.identifier}" has no JavaScript code.');
    }
    await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: _nextRequestId('load'),
        source: '''
const module = { exports: {} };
const exports = module.exports;
const api = {
  request: (request) => {
    const transport = globalThis.__ANIMESTREAM_HTTP_REQUEST__;
    if (typeof transport !== 'function') {
      return Promise.reject(new Error('Provider HTTP capability is unavailable.'));
    }
    return transport(request);
  }
};
(function (module, exports, api) {
$code
})(module, exports, api);
const exported = module.exports;
const provider = exported && (
  exported.default !== undefined
    ? exported.default
    : exported.provider !== undefined
      ? exported.provider
      : exported
);
if (provider === null || typeof provider !== 'object') {
  throw new Error('JavaScript provider must export an object.');
}
globalThis.__ANIMESTREAM_PROVIDER__ = provider;
globalThis.__ANIMESTREAM_PROVIDER_API__ = api;
return { ready: true };
''',
      ),
    );
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> input,
  ) async {
    await ensureLoaded();
    final response = await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: _nextRequestId(method),
        input: input,
        source: '''
const provider = globalThis.__ANIMESTREAM_PROVIDER__;
const method = provider && provider[${jsonEncode(method)}];
if (typeof method !== 'function') {
  throw new Error('Provider method is not implemented: ${jsonEncode(method)}');
}
return await method.call(
  provider,
  input,
  globalThis.__ANIMESTREAM_PROVIDER_API__
);
''',
      ),
    );
    return response.value;
  }

  String _nextRequestId(String method) =>
      '${details.identifier}:$method:${_requestSequence++}';

  @override
  Future<List<Map<String, String?>>> search(String query) async {
    final results = await _invoke('search', <String, Object?>{'query': query});
    if (results is! List) {
      throw const FormatException('JavaScript search must return an array.');
    }
    return results.map((item) {
      final map = _asStringMap(item, 'search result');
      final image = map['imageUrl'] ?? map['image'];
      return <String, String?>{
        'name': _requiredString(map['name'], 'search result name'),
        'alias': _requiredString(map['alias'], 'search result alias'),
        'imageUrl': _optionalString(image, 'search result imageUrl'),
      };
    }).toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> getAnimeEpisodeLink(
    String aliasId, {
    bool dub = false,
  }) async {
    final result = await _invoke(
      'getAnimeEpisodeLink',
      <String, Object?>{'aliasId': aliasId, 'dub': dub},
    );
    if (result is! List) {
      throw const FormatException('JavaScript episode lookup must return an array.');
    }
    return result.map((item) {
      final map = _asStringMap(item, 'episode');
      final number = _episodeNumber(map['episodeNumber']);
      final normalized = <String, dynamic>{
        'episodeLink': _requiredString(map['episodeLink'], 'episodeLink'),
        'episodeNumber': number,
        'thumbnail': _optionalString(map['thumbnail'], 'thumbnail'),
        'episodeTitle': _optionalString(map['episodeTitle'], 'episodeTitle'),
        'description': _optionalString(map['description'], 'description'),
        'hasDub': _optionalBool(map['hasDub'], 'hasDub'),
        'isFiller': _optionalBool(map['isFiller'], 'isFiller'),
        'metadata': _optionalString(map['metadata'], 'metadata'),
      };
      return EpisodeDetails.fromMap(normalized).toMap();
    }).toList(growable: false);
  }

  @override
  Future<void> getStreams(
    String episodeId,
    Function(List<VideoStream>, bool) update, {
    bool dub = false,
    String? metadata,
  }) async {
    final result = await _invoke('getStreams', <String, Object?>{
      'episodeId': episodeId,
      'dub': dub,
      'metadata': metadata,
    });
    update(_streamsFrom(result), true);
  }

  @override
  Future<void> getDownloadSources(
    String episodeUrl,
    Function(List<VideoStream>, bool) update, {
    bool dub = false,
    String? metadata,
  }) async {
    if (!details.supportDownloads) {
      throw UnsupportedError(
        'Provider "${details.name}" does not support downloads.',
      );
    }
    final result = await _invoke('getDownloadSources', <String, Object?>{
      'episodeUrl': episodeUrl,
      'dub': dub,
      'metadata': metadata,
    });
    update(_streamsFrom(result), true);
  }

  List<VideoStream> _streamsFrom(Object? result) {
    if (result is! List) {
      throw const FormatException('JavaScript stream lookup must return an array.');
    }
    return result.map((item) {
      final map = _asStringMap(item, 'video stream');
      final customHeaders = map['customHeaders'];
      Map<String, String>? headers;
      if (customHeaders != null) {
        if (customHeaders is! Map) {
          throw const FormatException('Stream customHeaders must be an object.');
        }
        headers = <String, String>{};
        for (final entry in customHeaders.entries) {
          if (entry.key is! String || entry.value is! String) {
            throw const FormatException(
              'Stream header names and values must be strings.',
            );
          }
          headers[entry.key as String] = entry.value as String;
        }
      }
      return VideoStream(
        quality: _requiredString(map['quality'], 'stream quality'),
        url: _requiredString(map['url'], 'stream url'),
        server: _optionalString(map['server'], 'stream server') ?? details.name,
        backup: map['backup'] == null
            ? false
            : _requiredBool(map['backup'], 'stream backup'),
        subtitle: _optionalString(map['subtitle'], 'stream subtitle'),
        subtitleFormat:
            _optionalString(map['subtitleFormat'], 'stream subtitleFormat'),
        customHeaders: headers,
      );
    }).toList(growable: false);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _runtime.dispose();
  }

  static Map<String, Object?> _asStringMap(Object? value, String field) {
    if (value is! Map) throw FormatException('$field must be an object.');
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('$field keys must be strings.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  static String _requiredString(Object? value, String field) {
    final result = _optionalString(value, field);
    if (result == null || result.isEmpty) {
      throw FormatException('$field must be a non-empty string.');
    }
    return result;
  }

  static String? _optionalString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw FormatException('$field must be a string or null.');
    return value;
  }

  static bool _requiredBool(Object? value, String field) {
    final result = _optionalBool(value, field);
    if (result == null) throw FormatException('$field must be a boolean.');
    return result;
  }

  static bool? _optionalBool(Object? value, String field) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'true':
          return true;
        case 'false':
          return false;
      }
    }
    throw FormatException('$field must be a boolean or null.');
  }

  static int _episodeNumber(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException('episodeNumber must be an integer.');
  }
}
