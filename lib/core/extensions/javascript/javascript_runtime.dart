import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart' as flutter_js;

/// Bounds the data crossing the JavaScript/Dart boundary.
///
/// These limits do not stop an infinite loop inside JavaScriptCore. The
/// flutter_js iOS API does not expose an interruptible execution deadline;
/// extension execution must not be enabled for untrusted repositories until
/// that gap is addressed and verified on an iOS device.
class JavaScriptRuntimeLimits {
  const JavaScriptRuntimeLimits({
    this.maxRequestIdBytes = 128,
    this.maxSourceBytes = 256 * 1024,
    this.maxInputBytes = 128 * 1024,
    this.maxOutputBytes = 1024 * 1024,
  });

  final int maxRequestIdBytes;
  final int maxSourceBytes;
  final int maxInputBytes;
  final int maxOutputBytes;
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
  Future<JavaScriptEngineResult> evaluate(String source);

  void dispose();
}

/// JavaScriptCore-backed runtime used by the current iOS app.
///
/// Network/XHR support is disabled and this adapter registers no Dart
/// callbacks, so extension code receives no application secrets, filesystem
/// access, or native API bridge.
class FlutterJsExecutionEngine implements JavaScriptExecutionEngine {
  FlutterJsExecutionEngine()
      : _runtime = flutter_js.getJavascriptRuntime(xhr: false);

  final flutter_js.JavascriptRuntime _runtime;

  @override
  Future<JavaScriptEngineResult> evaluate(String source) async {
    final result = _runtime.evaluate(source);
    return JavaScriptEngineResult(
      output: result.stringResult,
      isError: result.isError,
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
  }) : _engine = engine ?? FlutterJsExecutionEngine();

  final JavaScriptExecutionEngine _engine;
  final JavaScriptRuntimeLimits limits;

  Future<void> _queue = Future<void>.value();
  Future<void>? _disposeFuture;
  bool _disposing = false;
  bool _disposed = false;

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
      engineResult = await _engine.evaluate(_buildScript(request, inputJson));
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        JavaScriptExecutionException(
          'JavaScript engine failed: $error',
          requestId: request.requestId,
        ),
        stackTrace,
      );
    }

    if (utf8.encode(engineResult.output).length > limits.maxOutputBytes) {
      throw JavaScriptExecutionException(
        'Output exceeds ${limits.maxOutputBytes} bytes.',
        requestId: request.requestId,
      );
    }
    if (engineResult.isError) {
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
    return '''
(() => {
  const requestId = $requestId;
  try {
    const input = JSON.parse($inputLiteral);
    const value = (() => {
${request.source}
    })();
    if (value !== null && typeof value.then === 'function') {
      throw new Error(
        'Promise results are not supported in this proof of concept.',
      );
    }
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
})()
''';
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
