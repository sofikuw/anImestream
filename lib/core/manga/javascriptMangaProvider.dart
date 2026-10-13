import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/extensions/javascript/javascript_provider_http.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';

/// Adapts an installed JavaScript *manga* extension to [MangaChapterProvider].
///
/// Same envelope as `JavaScriptAnimeProvider`: the source is evaluated once in
/// its own [JavaScriptRuntime] behind a CommonJS-shaped `module.exports`, and
/// every call is a fresh script body that sees `input` and `api`. The only
/// capability handed across the boundary is `api.request`, which is HTTPS-only
/// and restricted to the provider's exact `allowedHosts`.
///
/// Provider methods, mirroring the anime side's `(input, api)` shape:
///
/// ```javascript
/// module.exports = {
///   async getChapters({ title, totalChapters }, api) {
///     return [{ chapterId, chapterNumber, chapterTitle, scanlator }];
///   },
///   async getPages({ chapterId }, api) {
///     return [{ url, headers }];   // reading order
///   }
/// };
/// ```
///
/// AniList remains the metadata source. This provider is only asked for the two
/// things AniList cannot answer: which chapters exist, and what images are in
/// one of them. That is why nothing here synthesises chapters from AniList's
/// chapter *count*.
class JavaScriptMangaProvider implements MangaChapterProvider {
  JavaScriptMangaProvider({
    required this.details,
    required JavaScriptRuntime runtime,
  }) : _runtime = runtime;

  final ProviderDetails details;
  final JavaScriptRuntime _runtime;

  Future<void>? _loadFuture;
  int _requestSequence = 0;
  bool _disposed = false;

  bool get isUsable => !_disposed && !_runtime.isDisposed;

  /// Every installed extension that declares the `manga` content type.
  ///
  /// Returns manifests, not providers, on purpose: each
  /// [JavaScriptMangaProvider] owns an isolated JS runtime, so instantiating
  /// every candidate just to populate a picker would spin up runtimes nothing
  /// ever calls. Hand the chosen manifest's identifier to [forIdentifier].
  static Future<List<ProviderDetails>> installedDetails({
    ProviderManager? providerManager,
  }) async {
    final List<ProviderDetails> installed;
    try {
      installed = await (providerManager ?? ProviderManager()).getSavedProviders();
    } catch (_) {
      // A storage failure must not take the caller down with it.
      return const <ProviderDetails>[];
    }
    return installed.where(_isUsableMangaExtension).toList(growable: false);
  }

  /// A provider for one installed manga extension, or null when that identifier
  /// is not an installed, usable manga extension.
  static Future<JavaScriptMangaProvider?> forIdentifier(
    String identifier, {
    ProviderManager? providerManager,
  }) async {
    for (final details in await installedDetails(providerManager: providerManager)) {
      if (details.identifier == identifier) return _fromDetails(details);
    }
    return null;
  }

  /// The first installed extension that declares the `manga` content type.
  ///
  /// Returns null when no manga extension is installed, which is the app's
  /// normal state rather than an error: the Manga tab browses and renders
  /// details from AniList with nothing installed at all.
  ///
  /// Anime-only extensions are skipped even though they are installed, because
  /// a provider that never declared `manga` has no manga methods to call.
  static Future<JavaScriptMangaProvider?> firstInstalled({
    ProviderManager? providerManager,
  }) async {
    final candidates = await installedDetails(providerManager: providerManager);
    if (candidates.isEmpty) return null;
    return _fromDetails(candidates.first);
  }

  /// True when an installed record can actually serve manga.
  ///
  /// A provider that declared `manga` but shipped no code is skipped rather
  /// than offered: selecting it could only ever fail.
  static bool _isUsableMangaExtension(ProviderDetails details) {
    if (details.scriptType.toLowerCase() != 'javascript') return false;
    if (!details.contentTypes.contains('manga')) return false;
    final code = details.code;
    return code != null && code.trim().isNotEmpty;
  }

  static JavaScriptMangaProvider _fromDetails(ProviderDetails details) {
    return JavaScriptMangaProvider(
      details: details,
      runtime: JavaScriptRuntime(
        httpRequestHandler: JavaScriptProviderHttp(
          allowedHosts: details.allowedHosts,
        ).request,
      ),
    );
  }

  @override
  String get providerName => details.name;

  @override
  String get providerId => details.identifier;

  /// Loads the provider source once into this provider's isolated JS runtime.
  Future<void> ensureLoaded() {
    if (_disposed || _runtime.isDisposed) {
      return Future<void>.error(
        StateError('The JavaScript manga provider has been disposed.'),
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

  Future<Object?> _invoke(String method, Map<String, Object?> input) async {
    await ensureLoaded();
    final response = await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: _nextRequestId(method),
        input: input,
        source: '''
const provider = globalThis.__ANIMESTREAM_PROVIDER__;
const method = provider && provider[${_jsonString(method)}];
if (typeof method !== 'function') {
  throw new Error('Provider method is not implemented: ${_jsonString(method)}');
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
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    final result = await _invoke('getChapters', <String, Object?>{
      // The whole title, not an id: a manga source matches AniList's title (and
      // its alternative titles) against its own catalogue.
      'title': manga.title,
      'totalChapters': manga.totalChapters,
    });
    if (result is! List) {
      throw const FormatException('getChapters must return an array.');
    }

    final chapters = <MangaChapter>[];
    for (final item in result) {
      final map = _asMap(item, 'chapter');
      chapters.add(
        MangaChapter(
          id: _requiredString(map['chapterId'] ?? map['id'], 'chapterId'),
          title: _optionalString(
            map['chapterTitle'] ?? map['title'],
            'chapterTitle',
          ),
          number: _optionalNumber(map['chapterNumber'] ?? map['number']),
          scanlator: _optionalString(map['scanlator'], 'scanlator'),
        ),
      );
    }
    return chapters;
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final result = await _invoke('getPages', <String, Object?>{
      'chapterId': chapter.id,
    });
    if (result is! List) {
      throw const FormatException('getPages must return an array.');
    }

    final pages = <MangaPage>[];
    for (var position = 0; position < result.length; position++) {
      final item = result[position];
      // Bare URL strings are accepted: a provider whose pages need no special
      // headers should not have to wrap each one in an object.
      if (item is String) {
        pages.add(
          MangaPage(
            index: position,
            imageUrl: _requiredString(item, 'page url'),
          ),
        );
        continue;
      }
      final map = _asMap(item, 'page');
      pages.add(
        MangaPage(
          index: _optionalInt(map['index']) ?? position,
          imageUrl: _requiredString(map['url'] ?? map['imageUrl'], 'page url'),
          headers: _headers(map['headers']),
        ),
      );
    }

    // Reading order is the contract, but a provider that supplies explicit
    // indices has expressed an order, so honour it.
    pages.sort((left, right) => left.index.compareTo(right.index));
    return pages;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _runtime.dispose();
  }

  static String _jsonString(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', ' ');
    return '"$escaped"';
  }

  static Map<String, Object?> _asMap(Object? value, String field) {
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
    if (value is! String) {
      throw FormatException('$field must be a string or null.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? _optionalNumber(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final asDouble = value.toDouble();
      return asDouble.isFinite ? asDouble : null;
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  static int? _optionalInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Page headers are optional, but a provider that sends them must send clean
  /// ones: CR/LF here would be a header injection.
  static Map<String, String>? _headers(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('page headers must be an object.');
    }
    final headers = <String, String>{};
    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('page header names and values must be strings.');
      }
      final name = entry.key as String;
      final headerValue = entry.value as String;
      if (headerValue.contains('\r') || headerValue.contains('\n')) {
        throw const FormatException('page header values must not contain CR or LF.');
      }
      headers[name] = headerValue;
    }
    return headers;
  }
}
