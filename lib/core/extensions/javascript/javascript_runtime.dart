import 'dart:async';
import 'dart:convert';

import 'package:flutter_qjs_next/flutter_qjs.dart' as quickjs;

/// Bounds both script execution and the data crossing the JavaScript/Dart
/// boundary. The engine deadline is enforced inside QuickJS, so it also
/// interrupts synchronous loops that would block a Dart Future timeout.
class JavaScriptRuntimeLimits {
  const JavaScriptRuntimeLimits({
    this.maxRequestIdBytes = 128,
    this.maxSourceBytes = 256 * 1024,
    this.maxInputBytes = 128 * 1024,
    this.maxOutputBytes = 1024 * 1024,
    this.maxHttpRequestsPerExecution = 12,
    this.maxAsyncExecutionTime = const Duration(seconds: 25),
    this.maxSynchronousExecutionTime = const Duration(seconds: 5),
    this.maxJavaScriptHeapBytes = 64 * 1024 * 1024,
  });

  final int maxRequestIdBytes;
  final int maxSourceBytes;
  final int maxInputBytes;
  final int maxOutputBytes;
  final int maxHttpRequestsPerExecution;

  /// Bounds awaited I/O and asynchronous provider work.
  final Duration maxAsyncExecutionTime;
  final Duration maxSynchronousExecutionTime;
  final int maxJavaScriptHeapBytes;
}

typedef JavaScriptHttpRequestHandler =
    FutureOr<Object?> Function(Map<String, Object?> request);

/// A host function callable from JavaScript through `sendMessage(channel, ...)`.
///
/// Values cross the boundary as JSON, so handlers receive decoded Dart values
/// and must return something JSON-encodable.
typedef JavaScriptHostMessageHandler = Object? Function(dynamic arguments);

/// Optional engine capability for registering host message channels.
///
/// Kept separate from [JavaScriptExecutionEngine] so existing engines and test
/// doubles keep compiling. Engines that do not implement it can still evaluate
/// scripts; only channel-based APIs such as MangaYomi extensions need it.
abstract interface class JavaScriptHostMessageBridge {
  void registerMessageHandler(
    String channel,
    JavaScriptHostMessageHandler handler,
  );
}

/// A single script invocation. [source] is a function body that can
/// read the JSON-decoded [input] value and must return a JSON-compatible value.
class JavaScriptExecutionRequest {
  const JavaScriptExecutionRequest({
    required this.requestId,
    required this.source,
    this.input = const <String, Object?>{},
  });

  final String requestId;
  final String source;
  final Map<String, Object?> input;
}

/// A JSON-compatible value returned by the JavaScript engine.
class JavaScriptExecutionResponse {
  const JavaScriptExecutionResponse({
    required this.requestId,
    required this.value,
  });

  final String requestId;
  final Object? value;
}

class JavaScriptExecutionException implements Exception {
  const JavaScriptExecutionException(
    this.message, {
    this.requestId,
  });

  final String message;
  final String? requestId;

  @override
  String toString() {
    final id = requestId;
    return id == null
        ? 'JavaScriptExecutionException: $message'
        : 'JavaScriptExecutionException ($id): $message';
  }
}

/// Result from a concrete JavaScript engine.
class JavaScriptEngineResult {
  const JavaScriptEngineResult({
    required this.output,
    this.isError = false,
  });

  final String output;
  final bool isError;
}

/// Engine seam kept independent of the selected JavaScript implementation.
abstract interface class JavaScriptExecutionEngine {
  void setHttpRequestHandler(JavaScriptHttpRequestHandler handler);

  Future<JavaScriptEngineResult> evaluate(String source);

  void dispose();
}

/// QuickJS runtime with a native interrupt deadline and bounded heap.
///
/// Web APIs are disabled. The only optional capability is the bounded,
/// allowlisted provider HTTP bridge supplied by the caller.
class QuickJsExecutionEngine
    implements JavaScriptExecutionEngine, JavaScriptHostMessageBridge {
  QuickJsExecutionEngine({
    int timeoutMs = 5000,
    int memoryLimitBytes = 64 * 1024 * 1024,
  }) : _runtime = quickjs.getJavascriptRuntime(
          xhr: false,
          timeout: timeoutMs,
          memoryLimit: memoryLimitBytes,
          webApis: const quickjs.JsWebApis.none(),
        ) {
    _runtime.onMessage(_httpRequestChannel, (dynamic arguments) {
      if (arguments is! Map) {
        throw const FormatException('HTTP bridge payload must be an object.');
      }
      final handler = _httpRequestHandler;
      if (handler == null) {
        throw StateError('The JavaScript HTTP bridge is not configured.');
      }
      return handler(Map<String, Object?>.from(arguments));
    });
  }

  static const String _httpRequestChannel = 'animestream_provider_http';
  final quickjs.JavascriptRuntime _runtime;
  JavaScriptHttpRequestHandler? _httpRequestHandler;

  @override
  void setHttpRequestHandler(JavaScriptHttpRequestHandler handler) {
    _httpRequestHandler = handler;
  }

  @override
  void registerMessageHandler(
    String channel,
    JavaScriptHostMessageHandler handler,
  ) {
    if (channel.isEmpty) {
      throw const FormatException('Host message channel must not be empty.');
    }
    _runtime.onMessage(channel, (dynamic arguments) => handler(arguments));
  }

  @override
  Future<JavaScriptEngineResult> evaluate(String source) async {
    final result = _runtime.evaluate(source);
    if (result.isError) {
      return JavaScriptEngineResult(
        output: result.stringResult,
        isError: true,
      );
    }
    if (result.isPromise) {
      // Resolve the returned async IIFE and any bounded host-bridge calls.
      final resolved = await _runtime.handlePromise(result);
      return JavaScriptEngineResult(
        output: resolved.stringResult,
        isError: resolved.isError,
      );
    }
    return JavaScriptEngineResult(
      output: _runtime.jsonStringify(result),
    );
  }

  @override
  void dispose() {
    _runtime.dispose();
  }
}

/// A small, replaceable Dart facade for structured JavaScript execution.
///
/// Calls against a runtime are serialized because the underlying JS context is
/// mutable and is not safe for concurrent evaluation.
class JavaScriptRuntime {
  JavaScriptRuntime({
    JavaScriptExecutionEngine? engine,
    this.limits = const JavaScriptRuntimeLimits(),
    JavaScriptHttpRequestHandler? httpRequestHandler,
  })  : _engine = engine ??
            QuickJsExecutionEngine(
              timeoutMs: limits.maxSynchronousExecutionTime.inMilliseconds,
              memoryLimitBytes: limits.maxJavaScriptHeapBytes,
            ),
        _httpRequestHandler = httpRequestHandler {
    _engine.setHttpRequestHandler(_handleHttpRequest);
  }

  final JavaScriptExecutionEngine _engine;
  final JavaScriptRuntimeLimits limits;
  final JavaScriptHttpRequestHandler? _httpRequestHandler;

  Future<void> _queue = Future<void>.value();
  Future<void>? _disposeFuture;
  String? _activeRequestId;
  int _activeHttpRequestCount = 0;
  bool _disposing = false;
  bool _disposed = false;

  bool get isDisposed => _disposed || _disposing;

  /// True when the underlying engine supports host message channels.
  bool get supportsHostMessageHandlers =>
      _engine is JavaScriptHostMessageBridge;

  /// Registers a `sendMessage`-style host channel.
  ///
  /// Throws [UnsupportedError] when the engine cannot register channels, so a
  /// caller can check [supportsHostMessageHandlers] first instead of failing
  /// partway through setup.
  void registerHostMessageHandler(
    String channel,
    JavaScriptHostMessageHandler handler,
  ) {
    final bridge = _engine as JavaScriptHostMessageBridge?;
    if (bridge != null) {
      bridge.registerMessageHandler(channel, handler);
    } else {
      throw UnsupportedError(
        'The JavaScript engine does not support host message handlers.',
      );
    }
  }

  Future<JavaScriptExecutionResponse> execute(
    JavaScriptExecutionRequest request,
  ) {
    if (_disposing || _disposed) {
      return Future<JavaScriptExecutionResponse>.error(
        StateError('The JavaScript runtime has been disposed.'),
      );
    }

    final completer = Completer<JavaScriptExecutionResponse>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await _executeQueued(request));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<JavaScriptExecutionResponse> _executeQueued(
    JavaScriptExecutionRequest request,
  ) async {
    if (_disposed) {
      throw StateError('The JavaScript runtime has been disposed.');
    }
    if (request.requestId.isEmpty) {
      throw ArgumentError.value(
        request.requestId,
        'requestId',
        'Must not be empty.',
      );
    }
    if (utf8.encode(request.requestId).length > limits.maxRequestIdBytes) {
      throw JavaScriptExecutionException(
        'Request ID exceeds ${limits.maxRequestIdBytes} bytes.',
        requestId: request.requestId,
      );
    }
    if (request.source.trim().isEmpty) {
      throw ArgumentError.value(request.source, 'source', 'Must not be empty.');
    }
    if (utf8.encode(request.source).length > limits.maxSourceBytes) {
      throw JavaScriptExecutionException(
        'Script exceeds ${limits.maxSourceBytes} bytes.',
        requestId: request.requestId,
      );
    }

    final inputJson = jsonEncode(request.input);
    if (utf8.encode(inputJson).length > limits.maxInputBytes) {
      throw JavaScriptExecutionException(
        'Input exceeds ${limits.maxInputBytes} bytes.',
        requestId: request.requestId,
      );
    }

    final JavaScriptEngineResult engineResult;
    try {
      _activeRequestId = request.requestId;
      _activeHttpRequestCount = 0;
      engineResult = await _engine
          .evaluate(_buildScript(request, inputJson))
          .timeout(
        limits.maxAsyncExecutionTime + const Duration(seconds: 5),
        onTimeout: () {
          _poison();
          throw JavaScriptExecutionException(
            'JavaScript engine did not complete within '
            '${limits.maxAsyncExecutionTime.inSeconds + 5}s.',
            requestId: request.requestId,
          );
        },
      );
    } catch (error, stackTrace) {
      final message = error.toString().toLowerCase();
      if (message.contains('interrupt') ||
          message.contains('timeout') ||
          message.contains('out of memory')) {
        _poison();
      }
      Error.throwWithStackTrace(
        JavaScriptExecutionException(
          'JavaScript engine failed: $error',
          requestId: request.requestId,
        ),
        stackTrace,
      );
    } finally {
      _activeRequestId = null;
      _activeHttpRequestCount = 0;
    }

    if (utf8.encode(engineResult.output).length > limits.maxOutputBytes) {
      throw JavaScriptExecutionException(
        'Output exceeds ${limits.maxOutputBytes} bytes.',
        requestId: request.requestId,
      );
    }
    if (engineResult.isError) {
      final message = engineResult.output.toLowerCase();
      if (message.contains('interrupt') ||
          message.contains('timeout') ||
          message.contains('out of memory')) {
        _poison();
      }
      throw JavaScriptExecutionException(
        engineResult.output,
        requestId: request.requestId,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(engineResult.output);
    } on FormatException catch (error) {
      throw JavaScriptExecutionException(
        'Malformed JavaScript response: ${error.message}',
        requestId: request.requestId,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw JavaScriptExecutionException(
        'JavaScript response must be a JSON object.',
        requestId: request.requestId,
      );
    }
    if (decoded['requestId'] != request.requestId) {
      throw JavaScriptExecutionException(
        'Response request ID did not match the request.',
        requestId: request.requestId,
      );
    }
    if (decoded['ok'] != true) {
      final error = decoded['error'];
      if (error is String &&
          (error.toLowerCase().contains('interrupted') ||
              error.toLowerCase().contains('timeout') ||
              error.toLowerCase().contains('out of memory'))) {
        _poison();
      }
      throw JavaScriptExecutionException(
        error is String ? error : 'JavaScript execution failed.',
        requestId: request.requestId,
      );
    }
    if (!decoded.containsKey('value')) {
      throw JavaScriptExecutionException(
        'JavaScript response did not contain a value.',
        requestId: request.requestId,
      );
    }

    return JavaScriptExecutionResponse(
      requestId: request.requestId,
      value: decoded['value'],
    );
  }

  String _buildScript(
    JavaScriptExecutionRequest request,
    String inputJson,
  ) {
    final requestId = jsonEncode(request.requestId);
    final inputLiteral = jsonEncode(inputJson);
    final httpRequest = _httpRequestHandler == null
        ? '''
    const httpRequest = () =>
      Promise.reject(new Error('The JavaScript HTTP bridge is disabled.'));
'''
        : '''
    const httpRequest = (request) => {
      if (request === null || typeof request !== 'object') {
        return Promise.reject(new Error('HTTP request must be an object.'));
      }
      return sendMessage(
        'animestream_provider_http',
        JSON.stringify({ ...request, requestId })
      );
    };
''';
    return '''
((async () => {
  const requestId = $requestId;
  const nativePromise = Promise;
  try {
    const input = JSON.parse($inputLiteral);
${httpRequest}
    globalThis.__ANIMESTREAM_HTTP_REQUEST__ = httpRequest;

    // Tachiyomi / MangaYomi extension compatibility shims (Client & HttpClient)
    const createHttpClient = () => ({
      async get(url, headers = {}) {
        const res = await httpRequest({ url, method: 'GET', headers });
        return {
          code: res.statusCode,
          headers: res.headers || {},
          body: res.body,
          bodyString: res.body
        };
      },
      async post(url, headers = {}, body = null) {
        const res = await httpRequest({ url, method: 'POST', headers, body: typeof body === 'string' ? body : JSON.stringify(body) });
        return {
          code: res.statusCode,
          headers: res.headers || {},
          body: res.body,
          bodyString: res.body
        };
      }
    });
    globalThis.Client = createHttpClient();
    globalThis.HttpClient = globalThis.Client;
    globalThis.fetch = async (url, options = {}) => {
      const method = options.method || 'GET';
      const headers = options.headers || {};
      const body = options.body || null;
      const res = await httpRequest({ url, method, headers, body });
      return {
        status: res.statusCode,
        ok: res.statusCode >= 200 && res.statusCode < 300,
        headers: res.headers || {},
        async text() { return res.body; },
        async json() { return JSON.parse(res.body); }
      };
    };

    const value = await nativePromise.resolve((async () => {
${request.source}
    })());
    const encodedValue = JSON.stringify(value);
    if (encodedValue === undefined) {
      throw new Error('The script must return a JSON-compatible value.');
    }
    return JSON.stringify({
      requestId,
      ok: true,
      value: JSON.parse(encodedValue)
    });
  } catch (error) {
    let message = 'JavaScript execution failed';
    try {
      message = String(
        error && error.message !== undefined ? error.message : error
      );
    } catch (_) {}
    return JSON.stringify({
      requestId,
      ok: false,
      error: message
    });
  }
})())
''';
  }

  Future<Object?> _handleHttpRequest(Map<String, Object?> payload) async {
    final activeRequestId = _activeRequestId;
    if (activeRequestId == null || payload['requestId'] != activeRequestId) {
      throw StateError('HTTP request is not associated with an active call.');
    }
    final handler = _httpRequestHandler;
    if (handler == null) {
      throw UnsupportedError('The JavaScript HTTP bridge is disabled.');
    }
    _activeHttpRequestCount++;
    if (_activeHttpRequestCount > limits.maxHttpRequestsPerExecution) {
      throw JavaScriptExecutionException(
        'HTTP request limit (${limits.maxHttpRequestsPerExecution}) exceeded.',
        requestId: activeRequestId,
      );
    }
    final request = Map<String, Object?>.from(payload)..remove('requestId');
    if (utf8.encode(jsonEncode(request)).length > limits.maxInputBytes) {
      throw JavaScriptExecutionException(
        'HTTP request payload exceeds ${limits.maxInputBytes} bytes.',
        requestId: activeRequestId,
      );
    }
    return handler(request);
  }

  /// A timed-out JS promise may still be running in the shared context. Dispose
  /// that context instead of allowing its late callbacks into a later request.
  void _poison() {
    _disposing = true;
    if (_disposed) return;
    _engine.dispose();
    _disposed = true;
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) {
      return existing;
    }

    _disposing = true;
    _disposeFuture = _queue.then((_) {
      if (!_disposed) {
        _engine.dispose();
        _disposed = true;
      }
    });
    return _disposeFuture!;
  }
}
