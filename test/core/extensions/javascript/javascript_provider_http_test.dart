import 'package:animestream/core/extensions/javascript/javascript_provider_http.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('JavaScriptProviderHttp', () {
    test('allows only exact HTTPS hosts in the allowlist', () {
      final uri = JavaScriptProviderHttp.validateUrl(
        'https://API.example.test:443/search?q=anime',
        const <String>['api.example.test'],
      );

      expect(uri.host, 'api.example.test');
      expect(
        () => JavaScriptProviderHttp.validateUrl(
          'https://other.example.test/search',
          const <String>['api.example.test'],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => JavaScriptProviderHttp.validateUrl(
          'https://sub.api.example.test/search',
          const <String>['api.example.test'],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects insecure, IP-literal, and credential-bearing URLs', () {
      const urls = <String, String>{
        'http://api.example.test/search': 'api.example.test',
        'https://127.0.0.1/search': '127.0.0.1',
        'https://user:pass@api.example.test/search': 'api.example.test',
        'https://service.local/search': 'service.local',
      };
      for (final entry in urls.entries) {
        expect(
          () => JavaScriptProviderHttp.validateUrl(
            entry.key,
            <String>[entry.value],
          ),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
      }
    });

    test('returns bounded response data and does not follow redirects', () async {
      http.BaseRequest? captured;
      final bridge = JavaScriptProviderHttp(
        allowedHosts: const <String>['api.example.test'],
        clientFactory: () => MockClient((request) async {
          captured = request;
          return http.Response(
            '{"ok":true}',
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
              'set-cookie': 'session=secret',
            },
          );
        }),
      );

      final response = await bridge.request(<String, Object?>{
        'url': 'https://api.example.test/search',
      }) as Map<String, Object?>;

      expect(captured, isA<http.Request>());
      expect((captured as http.Request).followRedirects, isFalse);
      expect(response['statusCode'], 200);
      expect(response['body'], '{"ok":true}');
      expect(response['headers'], <String, String>{
        'content-type': 'application/json',
      });
    });

    test('rejects application credential headers and oversized responses', () async {
      final blockedHeaderBridge = JavaScriptProviderHttp(
        allowedHosts: const <String>['api.example.test'],
      );
      await expectLater(
        blockedHeaderBridge.request(<String, Object?>{
          'url': 'https://api.example.test/search',
          'headers': <String, String>{'authorization': 'Bearer token'},
        }),
        throwsA(isA<FormatException>()),
      );

      final oversizedBridge = JavaScriptProviderHttp(
        allowedHosts: const <String>['api.example.test'],
        maxResponseBodyBytes: 4,
        clientFactory: () => MockClient(
          (_) async => http.Response('12345', 200),
        ),
      );
      await expectLater(
        oversizedBridge.request(<String, Object?>{
          'url': 'https://api.example.test/search',
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
