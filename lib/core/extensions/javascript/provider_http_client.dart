import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Creates a direct HTTPS client that pins connections to public DNS answers.
///
/// Provider-supplied hostnames are resolved once at connect time. Every answer
/// must be globally routable, and the socket connects to a vetted address
/// rather than asking the HTTP client to resolve the hostname again.
http.Client createPublicHttpsClient({
  Duration connectionTimeout = const Duration(seconds: 15),
}) {
  final client = HttpClient()
    ..connectionTimeout = connectionTimeout
    ..findProxy = (_) => 'DIRECT'
    ..connectionFactory = (uri, proxyHost, proxyPort) async {
      if (uri.scheme != 'https' || proxyHost != null || proxyPort != null) {
        throw const FormatException('Only direct HTTPS connections are allowed.');
      }
      final addresses = await InternetAddress.lookup(uri.host);
      if (addresses.isEmpty ||
          addresses.length > 16 ||
          addresses.any((item) => !isPublicAddress(item))) {
        throw const FormatException(
          'The HTTPS hostname did not resolve exclusively to public IP addresses.',
        );
      }
      final tasks = <ConnectionTask<Socket>>[];
      var cancelled = false;
      final attemptTimeout = connectionTimeout < const Duration(seconds: 3)
          ? connectionTimeout
          : const Duration(seconds: 3);

      Future<Socket> connect() async {
        Object? lastError;
        for (final address in addresses) {
          if (cancelled) {
            throw SocketException('HTTPS connection attempt was cancelled.');
          }
          final task = await Socket.startConnect(address, uri.port);
          tasks.add(task);
          if (cancelled) {
            task.cancel();
            throw SocketException('HTTPS connection attempt was cancelled.');
          }
          try {
            final socket = await task.socket.timeout(attemptTimeout);
            if (cancelled) {
              socket.destroy();
              throw SocketException('HTTPS connection attempt was cancelled.');
            }
            return socket;
          } catch (error) {
            lastError = error;
            task.cancel();
          }
        }
        if (lastError != null) throw lastError;
        throw SocketException('No public HTTPS address could be reached.');
      }

      return ConnectionTask.fromSocket<Socket>(
        connect(),
        () {
          cancelled = true;
          for (final task in tasks) {
            task.cancel();
          }
        },
      );
    };
  return IOClient(client);
}

/// Whether a resolved address is globally routable rather than reserved,
/// private, loopback, link-local, multicast, or documentation-only space.
bool isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isPublicIpv4(bytes);
  }
  if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
    return false;
  }

  final isIpv4Mapped = bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;
  if (isIpv4Mapped) return _isPublicIpv4(bytes.sublist(12));
  final isWellKnownNat64 = bytes[0] == 0x00 &&
      bytes[1] == 0x64 &&
      bytes[2] == 0xff &&
      bytes[3] == 0x9b &&
      bytes.sublist(4, 12).every((byte) => byte == 0);
  if (isWellKnownNat64) return _isPublicIpv4(bytes.sublist(12));

  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  // 2001::/23 is reserved for IETF protocol assignments; 3fff::/20 is
  // documentation-only space.
  if (bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      (bytes[2] == 0x00 || bytes[2] == 0x01)) {
    return false;
  }
  if (bytes[0] == 0x3f &&
      bytes[1] == 0xff &&
      (bytes[2] & 0xf0) == 0x00) {
    return false;
  }
  // IPv6 global unicast is allocated from 2000::/3. This also rejects
  // unspecified, unique-local, and translation-only prefixes.
  if ((bytes[0] & 0xe0) != 0x20) return false;

  final isDocumentationPrefix = bytes[0] == 0x20 &&
      bytes[1] == 0x01 &&
      bytes[2] == 0x0d &&
      bytes[3] == 0xb8;
  final isSixToFourPrefix = bytes[0] == 0x20 && bytes[1] == 0x02;
  return !isDocumentationPrefix && !isSixToFourPrefix;
}

bool _isPublicIpv4(List<int> bytes) {
  if (bytes.length != 4) return false;
  final a = bytes[0];
  final b = bytes[1];
  final c = bytes[2];

  if (a == 0 || a == 10 || a == 127 || a >= 224) return false;
  if (a == 100 && b >= 64 && b <= 127) return false; // Shared address space.
  if (a == 169 && b == 254) return false; // Link-local.
  if (a == 172 && b >= 16 && b <= 31) return false; // Private.
  if (a == 192 && b == 0 && c == 0) return false; // Protocol assignments.
  if (a == 192 && b == 2 && c == 0) return false; // Documentation.
  if (a == 192 && b == 168) return false; // Private.
  if (a == 192 && b == 88 && c == 99) return false; // Deprecated 6to4 relay.
  if (a == 198 && (b == 18 || b == 19)) return false; // Benchmarking.
  if (a == 198 && b == 51 && c == 100) return false; // Documentation.
  if (a == 203 && b == 0 && c == 113) return false; // Documentation.
  return true;
}
