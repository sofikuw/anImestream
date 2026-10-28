import 'dart:convert';

import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/extensions/javascript/javascript_provider_http.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:animestream/core/extensions/mangayomi/mangayomi_dom_bridge.dart';
import 'package:animestream/core/extensions/mangayomi/mangayomi_js_prelude.dart';
import 'package:flutter/foundation.dart';

/// A MangaYomi JavaScript extension bound to its own QuickJS runtime.
///
/// Setup injects the MangaYomi host API, evaluates the extension source once,
/// and keeps the `DefaultExtension` instance alive for later calls. Every call
/// is a small script body that awaits one instance method, so the runtime's
/// existing deadline, heap cap, and serialized execution still apply.
class MangayomiRuntime {
  MangayomiRuntime._({
    required this.details,
    required JavaScriptRuntime runtime,
    required JavaScriptProviderHttp http,
    required MangayomiDomBridge dom,
  })  : _runtime = runtime,
        _http = http,
        _dom = dom;

  final ProviderDetails details;
  final JavaScriptRuntime _runtime;
  final JavaScriptProviderHttp _http;
  final MangayomiDomBridge _dom;
  final Map<String, String?> _preferences = <String, String?>{};

  int _requestSequence = 0;
  Future<void>? _loadFuture;
  bool _disposed = false;

  bool get isUsable => !_disposed && !_runtime.isDisposed;

  static Future<MangayomiRuntime> create(ProviderDetails details) async {
    final http = JavaScriptProviderHttp(
      allowedHosts: details.allowedHosts,
      // MangaYomi sources routinely span a parent domain and its CDN, and
      // rely on redirects to reach the real page or image URL.
      allowSubdomains: true,
      followRedirects: true,
      maxResponseBodyBytes: 4 * 1024 * 1024,
    );
    final runtime = JavaScriptRuntime(
      limits: const JavaScriptRuntimeLimits(
        maxSourceBytes: 512 * 1024,
        maxHttpRequestsPerExecution: 32,
        maxAsyncExecutionTime: Duration(seconds: 45),
      ),
      httpRequestHandler: http.request,
    );
    final dom = MangayomiDomBridge();
    final instance = MangayomiRuntime._(
      details: details,
      runtime: runtime,
      http: http,
      dom: dom,
    );
    instance._installChannels();
    await instance.ensureLoaded();
    return instance;
  }

  Future<void> ensureLoaded() {
    if (_disposed || _runtime.isDisposed) {
      return Future<void>.error(
        StateError('The MangaYomi runtime has been disposed.'),
      );
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    final code = details.code;
    if (code == null || code.trim().isEmpty) {
      throw StateError(
        'Provider "${details.identifier}" has no JavaScript code.',
      );
    }
    // The catalog entry knows `isManga`, `baseUrl`, and `lang`; the extension
    // file does not. Merge the catalog view into the source object the
    // extension reads through `this.source`.
    final injectedSource = jsonEncode(<String, Object?>{
      'name': details.name,
      'isManga': details.contentTypes.contains('manga'),
      'hasCloudflare': false,
      'isFullData': false,
      if (details.baseUrl != null)
        'baseUrl': details.baseUrl
      else if (details.allowedHosts.isNotEmpty)
        'baseUrl': 'https://${details.allowedHosts.first}',
      if (details.apiUrl != null) 'apiUrl': details.apiUrl,
      if (details.lang != null) 'lang': details.lang,
      if (details.dateFormat != null) 'dateFormat': details.dateFormat,
      if (details.dateFormatLocale != null)
        'dateFormatLocale': details.dateFormatLocale,
    });
    final source = <String>[
      mangayomiCommonPrelude,
      mangayomiLibraryPrelude,
      mangayomiProviderPrelude,
      mangayomiHostHelpersPrelude,
      code,
      // The file's own declaration wins where it has a value (notably a
      // baseUrl with a path); the catalog fills in what it omits.
      '(globalThis.__MG_SOURCE__ = Object.assign('
          '{}, $injectedSource, '
          '(typeof mangayomiSources !== "undefined" && '
          'mangayomiSources.length) ? mangayomiSources[0] : {}));',
      'globalThis.__MG_EXT__ = new (class extends DefaultExtension { '
          'get source() { return globalThis.__MG_SOURCE__; } })();',
      'return null;',
    ].join('\n');

    await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: _nextRequestId('load'),
        source: source,
      ),
    );
  }

  Future<Object?> invoke(String method, [List<Object?> arguments = const []]) {
    final encoded = arguments.map(jsonEncode).join(', ');
    return _evaluate(
      'if (!globalThis.__MG_EXT__) throw new Error("Extension failed to load.");\n'
      'return await globalThis.__MG_EXT__.$method($encoded);',
      label: method,
    );
  }

  /// Reads a property such as `supportsLatest`, returning [fallback] when the
  /// source throws "not implemented".
  Future<Object?> readProperty(String property, {Object? fallback}) async {
    try {
      return await _evaluate(
        'if (!globalThis.__MG_EXT__) throw new Error("Extension failed to load.");\n'
        'return await globalThis.__MG_EXT__.$property;',
        label: property,
      );
    } on JavaScriptExecutionException {
      return fallback;
    }
  }

  Future<Object?> _evaluate(String source, {required String label}) async {
    await ensureLoaded();
    final response = await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: _nextRequestId(label),
        source: source,
      ),
    );
    return response.value;
  }

  String _nextRequestId(String label) {
    _requestSequence++;
    final sanitized = label.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return 'mangayomi-$sanitized-$_requestSequence';
  }

  void _installChannels() {
    _dom.register(_runtime);

    _runtime.registerHostMessageHandler('get', (dynamic arguments) {
      final key = _firstArgument(arguments);
      return _preferences['$key'];
    });
    _runtime.registerHostMessageHandler('getString', (dynamic arguments) {
      final args = _arguments(arguments);
      final key = '${args[0]}';
      return _preferences[key] ?? (args.length > 1 ? args[1] : null);
    });
    _runtime.registerHostMessageHandler('setString', (dynamic arguments) {
      final args = _arguments(arguments);
      _preferences['${args[0]}'] = args.length > 1 ? '${args[1]}' : null;
      return null;
    });
    _runtime.registerHostMessageHandler('log', (dynamic arguments) {
      if (kDebugMode) {
        // The console shim sends [level, message]; older extensions that call
        // `sendMessage("log", ...)` directly send a bare payload instead.
        final args = _arguments(arguments);
        final message = args.length > 1
            ? args.skip(1).join(' ')
            : (args.isEmpty ? '' : '${args[0]}');
        debugPrint('[MangaYomi:${details.identifier}] $message');
      }
      return null;
    });

    const methods = <String, String>{
      'http_head': 'HEAD',
      'http_get': 'GET',
      'http_post': 'POST',
      'http_put': 'PUT',
      'http_delete': 'DELETE',
      'http_patch': 'PATCH',
    };
    methods.forEach((channel, method) {
      _runtime.registerHostMessageHandler(
        channel,
        (dynamic arguments) => _httpCall(arguments, method),
      );
    });

    _runtime.registerHostMessageHandler('cryptoHandler', (dynamic) {
      throw UnsupportedError(
        'This MangaYomi source uses the native AES crypto helper, which '
        'anImestream does not implement yet.',
      );
    });
    _runtime.registerHostMessageHandler('encryptAESCryptoJS', (dynamic) {
      throw UnsupportedError(
        'This MangaYomi source uses the native AES crypto helper, which '
        'anImestream does not implement yet.',
      );
    });
    _runtime.registerHostMessageHandler('decryptAESCryptoJS', (dynamic) {
      throw UnsupportedError(
        'This MangaYomi source uses the native AES crypto helper, which '
        'anImestream does not implement yet.',
      );
    });
    _runtime.registerHostMessageHandler('decryptAESGCM', (dynamic) {
      throw UnsupportedError(
        'This MangaYomi source uses the native AES crypto helper, which '
        'anImestream does not implement yet.',
      );
    });
    _runtime.registerHostMessageHandler('parseDates', (dynamic arguments) {
      final args = _arguments(arguments);
      return args.isEmpty ? const <String>[] : args[0];
    });
    _runtime.registerHostMessageHandler('deobfuscateJsPassword', (dynamic) {
      throw UnsupportedError(
        'This MangaYomi source uses the native JS deobfuscator, which '
        'anImestream does not implement yet.',
      );
    });
    // Registered so the failure names the missing capability instead of
    // surfacing as an unknown channel inside QuickJS.
    for (final channel in const <String>[
      'unpackJs',
      'unpackJsAndCombine',
      'evaluateJavascriptViaWebview',
      'createHlsProxyUrl',
      'parseEpub',
      'parseEpubChapter',
    ]) {
      _runtime.registerHostMessageHandler(channel, (dynamic) {
        throw UnsupportedError(
          'This MangaYomi source uses $channel, which anImestream does not '
          'implement yet.',
        );
      });
    }
  }

  Future<String> _httpCall(dynamic arguments, String method) async {
    final args = _arguments(arguments);
    if (args.length < 3) {
      throw const FormatException('MangaYomi HTTP call is missing its URL.');
    }
    final url = '${args[2]}';
    // `new Client({headers: {...}})` supplies per-client defaults; per-call
    // headers win.
    final headers = <String, String>{
      if (args.length > 1 && args[1] is Map)
        ..._stringMap((args[1] as Map)['headers']),
      ..._stringMap(args.length > 3 ? args[3] : null),
    };
    final body = args.length > 4 ? args[4] : null;

    final response = await _http.request(<String, Object?>{
      'url': url,
      'method': method,
      'headers': headers,
      'body': _encodeBody(body, headers),
    });
    return jsonEncode(response);
  }

  /// MangaYomi passes Maps for JSON APIs and form posts; the host request
  /// builder needs the already-encoded payload.
  static Object? _encodeBody(Object? body, Map<String, String> headers) {
    if (body == null) return null;
    if (body is String || body is List<int>) return body;
    var contentType = '';
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        contentType = entry.value.toLowerCase();
        break;
      }
    }
    // Mirrors package:http, which MangaYomi's own bridge uses: an explicit
    // JSON content type JSON-encodes the map, anything else is form-encoded.
    if (body is Map) {
      if (contentType.contains('json')) return jsonEncode(body);
      return body.entries
          .map(
            (entry) =>
                '${Uri.encodeQueryComponent('${entry.key}')}='
                '${Uri.encodeQueryComponent('${entry.value}')}',
          )
          .join('&');
    }
    if (body is List) return jsonEncode(body);
    return '$body';
  }

  /// MangaYomi hosts receive the channel payload as a JSON string
  /// (`sendMessage(channel, JSON.stringify([...]))`), so decode it. Accepting a
  /// ready-made list keeps newer forks that pass one working.
  static List<dynamic> _arguments(dynamic arguments) {
    var value = arguments;
    if (value is String) value = jsonDecode(value);
    if (value is List) return value;
    throw const FormatException('MangaYomi channel expects an array payload.');
  }

  static Object? _firstArgument(dynamic arguments) {
    final args = _arguments(arguments);
    return args.isEmpty ? null : args[0];
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return <String, String>{};
    return value.map((key, entry) => MapEntry('$key', '$entry'));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _dom.dispose();
    await _runtime.dispose();
  }
}
