import 'dart:convert';

import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JavaScriptRuntime', () {
    test('converts the request and response through structured JSON', () async {
      final request = JavaScriptExecutionRequest(
        requestId: 'request-1',
        source: 'return { title: input.title, count: 2 };',
        input: const <String, Object?>{'title': 'Show "A"'},
      );
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => JavaScriptEngineResult(
          output: jsonEncode(<String, Object?>{
            'requestId': request.requestId,
            'ok': true,
            'value': <String, Object?>{'title': 'Show "A"', 'count': 2},
          }),
        ),
      );
      final runtime = JavaScriptRuntime(engine: engine);

      final response = await runtime.execute(request);

      expect(response.requestId, request.requestId);
      expect(response.value, <String, Object?>{'title': 'Show "A"', 'count': 2});
      expect(
        engine.scripts.single,
        contains(
          'const input = JSON.parse(${jsonEncode(jsonEncode(request.input))});',
        ),
      );
      expect(engine.scripts.single, contains(request.source));
      await runtime.dispose();
    });

    test('surfaces a JavaScript error envelope as a typed exception', () async {
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => JavaScriptEngineResult(
          output: jsonEncode(<String, Object?>{
            'requestId': 'request-2',
            'ok': false,
            'error': 'provider failed',
          }),
        ),
      );
      final runtime = JavaScriptRuntime(engine: engine);

      await expectLater(
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-2',
            source: 'throw new Error("provider failed");',
          ),
        ),
        throwsA(
          isA<JavaScriptExecutionException>()
              .having((error) => error.message, 'message', 'provider failed')
              .having((error) => error.requestId, 'requestId', 'request-2'),
        ),
      );
      await runtime.dispose();
    });

    test('rejects a response for a different request', () async {
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => JavaScriptEngineResult(
          output: jsonEncode(<String, Object?>{
            'requestId': 'another-request',
            'ok': true,
            'value': 1,
          }),
        ),
      );
      final runtime = JavaScriptRuntime(engine: engine);

      await expectLater(
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-3',
            source: 'return 1;',
          ),
        ),
        throwsA(
          isA<JavaScriptExecutionException>().having(
            (error) => error.message,
            'message',
            'Response request ID did not match the request.',
          ),
        ),
      );
      await runtime.dispose();
    });

    test('enforces source and output limits', () async {
      final sourceLimitEngine = _FakeJavaScriptExecutionEngine(
        (_) async => const JavaScriptEngineResult(output: 'too much output'),
      );
      final sourceLimitedRuntime = JavaScriptRuntime(
        engine: sourceLimitEngine,
        limits: const JavaScriptRuntimeLimits(maxSourceBytes: 3),
      );

      await expectLater(
        sourceLimitedRuntime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-4',
            source: 'return 1;',
          ),
        ),
        throwsA(isA<JavaScriptExecutionException>()),
      );
      expect(sourceLimitEngine.scripts, isEmpty);
      await sourceLimitedRuntime.dispose();

      final outputLimitEngine = _FakeJavaScriptExecutionEngine(
        (_) async => const JavaScriptEngineResult(output: 'too much output'),
      );
      final outputLimitedRuntime = JavaScriptRuntime(
        engine: outputLimitEngine,
        limits: const JavaScriptRuntimeLimits(maxOutputBytes: 4),
      );
      await expectLater(
        outputLimitedRuntime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-5',
            source: 'return 1;',
          ),
        ),
        throwsA(
          isA<JavaScriptExecutionException>().having(
            (error) => error.message,
            'message',
            'Output exceeds 4 bytes.',
          ),
        ),
      );
      await outputLimitedRuntime.dispose();
    });

    test('enforces the input limit before evaluation', () async {
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => const JavaScriptEngineResult(output: ''),
      );
      final runtime = JavaScriptRuntime(
        engine: engine,
        limits: const JavaScriptRuntimeLimits(maxInputBytes: 3),
      );

      await expectLater(
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-6',
            source: 'return input.value;',
            input: <String, Object?>{'value': 'long'},
          ),
        ),
        throwsA(
          isA<JavaScriptExecutionException>().having(
            (error) => error.message,
            'message',
            'Input exceeds 3 bytes.',
          ),
        ),
      );
      expect(engine.scripts, isEmpty);
      await runtime.dispose();
    });

    test('wraps engine-level failures', () async {
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => const JavaScriptEngineResult(
          output: 'synthetic engine failure',
          isError: true,
        ),
      );
      final runtime = JavaScriptRuntime(engine: engine);

      await expectLater(
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-7',
            source: 'return 1;',
          ),
        ),
        throwsA(
          isA<JavaScriptExecutionException>().having(
            (error) => error.message,
            'message',
            'synthetic engine failure',
          ),
        ),
      );
      await runtime.dispose();
    });

    test('serializes concurrent evaluations against one JS context', () async {
      var activeEvaluations = 0;
      var maximumConcurrentEvaluations = 0;
      final engine = _FakeJavaScriptExecutionEngine((script) async {
        activeEvaluations++;
        if (activeEvaluations > maximumConcurrentEvaluations) {
          maximumConcurrentEvaluations = activeEvaluations;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1));
        activeEvaluations--;

        final requestId =
            script.contains('"request-8"') ? 'request-8' : 'request-9';
        return JavaScriptEngineResult(
          output: jsonEncode(<String, Object?>{
            'requestId': requestId,
            'ok': true,
            'value': requestId,
          }),
        );
      });
      final runtime = JavaScriptRuntime(engine: engine);

      final responses = await Future.wait(<Future<JavaScriptExecutionResponse>>[
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-8',
            source: 'return 8;',
          ),
        ),
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-9',
            source: 'return 9;',
          ),
        ),
      ]);

      expect(responses.map((response) => response.requestId), [
        'request-8',
        'request-9',
      ]);
      expect(maximumConcurrentEvaluations, 1);
      await runtime.dispose();
    });

    test('disposes once and refuses subsequent work', () async {
      final engine = _FakeJavaScriptExecutionEngine(
        (_) async => JavaScriptEngineResult(
          output: jsonEncode(<String, Object?>{
            'requestId': 'request-10',
            'ok': true,
            'value': true,
          }),
        ),
      );
      final runtime = JavaScriptRuntime(engine: engine);

      await runtime.dispose();
      await runtime.dispose();

      expect(engine.disposeCount, 1);
      await expectLater(
        runtime.execute(
          const JavaScriptExecutionRequest(
            requestId: 'request-10',
            source: 'return true;',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _FakeJavaScriptExecutionEngine implements JavaScriptExecutionEngine {
  _FakeJavaScriptExecutionEngine(this.onEvaluate);

  final Future<JavaScriptEngineResult> Function(String source) onEvaluate;
  final List<String> scripts = <String>[];
  int disposeCount = 0;

  @override
  Future<JavaScriptEngineResult> evaluate(String source) {
    scripts.add(source);
    return onEvaluate(source);
  }

  @override
  void dispose() {
    disposeCount++;
  }
}
