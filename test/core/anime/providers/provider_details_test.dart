import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderDetails', () {
    test('reads older saved records without an allowedHosts field', () {
      final details = ProviderDetails.fromMap(<String, dynamic>{
        'name': 'Legacy',
        'identifier': 'legacy',
        'version': '1',
        'code': 'module.exports = {};',
      });

      expect(details.allowedHosts, isEmpty);
      expect(details.scriptType, 'dart');
      expect(details.enabled, isTrue);
    });

    test('round trips exact allowed hosts and keeps list equality', () {
      final details = ProviderDetails(
        name: 'Example',
        identifier: 'example',
        version: '1',
        code: 'module.exports = {};',
        allowedHosts: const <String>['api.example.test'],
      );

      final restored = ProviderDetails.fromJson(details.toJson());

      expect(restored, details);
      expect(restored.allowedHosts, const <String>['api.example.test']);
      expect(restored.hashCode, details.hashCode);
    });

    test('round trips repository, digest, and disabled state', () {
      final details = ProviderDetails(
        name: 'Example',
        identifier: 'example',
        version: '1.0.0',
        code: 'module.exports = {};',
        scriptType: 'javascript',
        enabled: false,
        repositoryUrl: 'https://repo.example.test/index.json',
        sourceSha256: List<String>.filled(64, 'a').join(),
      );

      final restored = ProviderDetails.fromJson(details.toJson());

      expect(restored, details);
      expect(restored.enabled, isFalse);
      expect(restored.repositoryUrl, details.repositoryUrl);
      expect(restored.sourceSha256, details.sourceSha256);
    });
  });
}
