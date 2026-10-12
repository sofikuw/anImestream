import 'dart:io';
import 'dart:typed_data';

import 'package:animestream/core/extensions/javascript/provider_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPublicAddress', () {
    test('accepts globally routed IPv4 and IPv6 addresses', () {
      expect(isPublicAddress(InternetAddress('8.8.8.8')), isTrue);
      expect(
        isPublicAddress(InternetAddress('2001:4860:4860::8888')),
        isTrue,
      );
    });

    test('rejects private, reserved, loopback, and documentation addresses',
        () {
      for (final address in <String>[
        '10.1.2.3',
        '100.64.0.1',
        '127.0.0.1',
        '169.254.1.1',
        '172.20.0.1',
        '192.168.1.1',
        '192.0.2.1',
        '198.51.100.1',
        '203.0.113.1',
        '224.0.0.1',
        '::',
        '::1',
        'fc00::1',
        'fe80::1',
        '2001:2::1',
        '2001:db8::1',
        '3fff::1',
      ]) {
        expect(isPublicAddress(InternetAddress(address)), isFalse, reason: address);
      }
    });

    test('rejects IPv4-mapped private IPv6 addresses', () {
      final mappedLoopback = InternetAddress.fromRawAddress(
        Uint8List.fromList(<int>[
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          255,
          255,
          127,
          0,
          0,
          1,
        ]),
      );

      expect(isPublicAddress(mappedLoopback), isFalse);
    });

    test('checks the embedded IPv4 in well-known NAT64 addresses', () {
      final publicNat64 = InternetAddress.fromRawAddress(
        Uint8List.fromList(<int>[
          0,
          100,
          255,
          155,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          8,
          8,
          8,
          8,
        ]),
      );
      final privateNat64 = InternetAddress.fromRawAddress(
        Uint8List.fromList(<int>[
          0,
          100,
          255,
          155,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          10,
          0,
          0,
          1,
        ]),
      );

      expect(isPublicAddress(publicNat64), isTrue);
      expect(isPublicAddress(privateNat64), isFalse);
    });
  });
}
