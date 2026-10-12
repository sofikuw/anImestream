import 'dart:convert';

import 'package:animestream/core/anime/providers/javascriptAnimeProvider.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/types.dart';
import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JavaScriptAnimeProvider', () {
    test('maps JS search, episode, and stream values to existing models',
        () async {
      final engine = _FakeEngine((script) async {
        if (script.contains('const module =')) {
          return _success(script, true);
        }
        if (script.contains('provider["search"]')) {
          return _success(script, <Object?>[
            <String, Object?>{
              'name': 'Example Anime',
              'alias': '/anime/example',
              'imageUrl': 'https://cdn.example.test/cover.jpg',
            },
          ]);
        }
        if (script.contains('provider["getAnimeEpisodeLink"]')) {
          return _success(script, <Object?>[
            <String, Object?>{
              'episodeLink': '/episode/1',
              'episodeNumber': 1.0,
              'hasDub': true,
              'isFiller': false,
            },
          ]);
        }
        if (script.contains('provider["getStreams"]')) {
          return _success(script, <Object?>[
            <String, Object?>{
              'quality': '1080p',
              'url': 'https://video.example.test/stream.m3u8',
              'customHeaders': <String, Object?>{'referer': 'https://example.test'},
            },
          ]);
        }
        throw StateError('Unexpected JS invocation');
      });
      final provider = _provider(engine, supportDownloads: true);

      final results = await provider.search('example');
      final episodes = await provider.getAnimeEpisodeLink('/anime/example');
      List<VideoStream>? streams;
      var finished = false;
      await provider.getStreams(
        '/episode/1',
        (value, isFinished) {
          streams = value;
          finished = isFinished;
        },
      );

      expect(results.single, <String, String?>{
        'name': 'Example Anime',
        'alias': '/anime/example',
        'imageUrl': 'https://cdn.example.test/cover.jpg',
      });
      expect(episodes.single['episodeNumber'], 1);
      expect(episodes.single['hasDub'], isTrue);
      expect(streams!.single.quality, '1080p');
      expect(streams!.single.server, 'Test Provider');
      expect(streams!.single.backup, isFalse);
      expect(streams!.single.customHeaders, <String, String>{
        'referer': 'https://example.test',
      });
      expect(finished, isTrue);
      await provider.dispose();
      expect(engine.disposeCount, 1);
    });

    test('sends a stable input object to the exported provider method',
        () async {
      final engine = _FakeEngine((script) async {
        if (script.contains('const module =')) return _success(script, true);
        return _success(script, <Object?>[]);
      });
      final provider = _provider(engine);

      await provider.search('needle');

      expect(engine.scripts.last, contains(r'\"query\":\"needle\"'));
      await provider.dispose();
    });

    test('does not call download methods when downloads are unsupported',
        () async {
      final engine = _FakeEngine((script) async => _success(script, true));
      final provider = _provider(engine);

      await expectLater(
        provider.getDownloadSources('/episode/1', (_, __) {}),
        throwsA(isA<UnsupportedError>()),
      );
      expect(engine.scripts, isEmpty);
      await provider.dispose();
    });

    test('rejects malformed provider results instead of coercing them',
        () async {
      final engine = _FakeEngine((script) async {
        if (script.contains('const module =')) return _success(script, true);
        return _success(script, <Object?>[
          <String, Object?>{'name': 'Missing alias'},
        ]);
      });
      final provider = _provider(engine);

      await expectLater(
        provider.search('bad'),
        throwsA(isA<FormatException>()),
      );
      await provider.dispose();
    });
  });
}

JavaScriptAnimeProvider _provider(
  _FakeEngine engine, {
  bool supportDownloads = false,
}) {
  return JavaScriptAnimeProvider(
    details: ProviderDetails(
      name: 'Test Provider',
      identifier: 'test-provider',
      version: '1',
      code: 'module.exports = { search() {} };',
      scriptType: 'javascript',
      supportDownloads: supportDownloads,
    ),
    runtime: JavaScriptRuntime(engine: engine),
  );
}

JavaScriptEngineResult _success(String script, Object? value) {
  final requestIdMatch = RegExp(r'const requestId = ("(?:[^"\\]|\\.)*");')
      .firstMatch(script);
  final requestId = requestIdMatch == null
      ? ''
      : jsonDecode(requestIdMatch.group(1)!) as String;
  return JavaScriptEngineResult(
    output: jsonEncode(<String, Object?>{
      'requestId': requestId,
      'ok': true,
      'value': value,
    }),
  );
}

class _FakeEngine implements JavaScriptExecutionEngine {
  _FakeEngine(this.onEvaluate);

  final Future<JavaScriptEngineResult> Function(String script) onEvaluate;
  final List<String> scripts = <String>[];
  int disposeCount = 0;

  @override
  void setHttpRequestHandler(JavaScriptHttpRequestHandler handler) {}

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
