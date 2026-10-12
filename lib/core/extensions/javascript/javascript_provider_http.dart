import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:animestream/core/extensions/javascript/provider_http_client.dart';
import 'package:http/http.dart' as http;

/// A deliberately narrow HTTP capability for JavaScript anime providers.
///
/// Requests are HTTPS-only, limited to exact manifest-declared hosts, never
/// follow redirects, and do not inherit application cookies or credentials.
class JavaScriptProviderHttp {
  JavaScriptProviderHttp({
    required Iterable<String> allowedHosts,
    http.Client Function()? clientFactory,
    this.requestTimeout = const Duration(seconds: 15),
    this.maxRequestBodyBytes = 128 * 1024,
    this.maxResponseBodyBytes = 1024 * 1024,
  })  : _allowedHosts = Set<String>.unmodifiable(
          allowedHosts.map(_normalizeAllowedHost).whereType<String>(),
        ),
        _clientFactory = clientFactory ?? (() => createPublicHttpsClient());

  static const int _maxHeaderCount = 64;
  static const int _maxHeaderBytes = 32 * 1024;
  static const Set<String> _blockedRequestHeaders = <String>{
    'authorization',
    'connection',
    'content-length',
    'cookie',
    'host',
    'proxy-authorization',
    'transfer-encoding',
  };
  static const Set<String> _blockedResponseHeaders = <String>{
    'connection',
    'set-cookie',
    'transfer-encoding',
  };

  final Set<String> _allowedHosts;
  final http.Client Function() _clientFactory;
  final Duration requestTimeout;
  final int maxRequestBodyBytes;
  final int maxResponseBodyBytes;

  Future<Object?> request(Map<String, Object?> input) async {
    final url = input['url'];
    if (url is! String || url.length > 4096) {
      throw const FormatException('HTTP request URL must be a string under 4096 characters.');
    }
    final uri = validateUrl(url, _allowedHosts);
    final method = (input['method'] as String? ?? 'GET').toUpperCase();
    if (method != 'GET' && method != 'POST') {
      throw const FormatException('Only GET and POST are supported.');
    }

    final headers = _validatedHeaders(input['headers']);
    final body = _encodeBody(input['body']);
    if (body != null && method != 'POST') {
      throw const FormatException('Only POST requests may include a body.');
    }
    if (body != null && utf8.encode(body).length > maxRequestBodyBytes) {
      throw FormatException(
        'HTTP request body exceeds $maxRequestBodyBytes bytes.',
      );
    }
    if (body != null &&
        !headers.keys.any((key) => key.toLowerCase() == 'content-type')) {
      headers['content-type'] = 'application/json';
    }

    final client = _clientFactory();
    try {
      return await _send(
        client,
        uri,
        method,
        headers,
        body,
      ).timeout(
        requestTimeout,
        onTimeout: () {
          client.close();
          throw TimeoutException(
            'Provider HTTP request timed out after ${requestTimeout.inSeconds}s.',
          );
        },
      );
    } finally {
      client.close();
    }
  }

  static Uri validateUrl(String rawUrl, Iterable<String> allowedHosts) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const FormatException(
        'Provider requests must use HTTPS on the standard port.',
      );
    }

    final host = _normalizeAllowedHost(uri.host);
    if (host == null || !ProviderRepository.isPublicDnsHost(host)) {
      throw const FormatException('IP-literal and invalid hosts are blocked.');
    }
    final normalizedAllowlist = allowedHosts
        .map(_normalizeAllowedHost)
        .whereType<String>()
        .toSet();
    if (!normalizedAllowlist.contains(host)) {
      throw FormatException('Provider host is not allowlisted: $host');
    }
    return uri.replace(scheme: 'https', host: host);
  }

  static String? _normalizeAllowedHost(String rawHost) {
    final host = rawHost.trim().toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    if (host.isEmpty ||
        !ProviderRepository.isPublicDnsHost(host) ||
        host.contains('*') ||
        host.contains('/') ||
        host.contains(':') ||
        host.contains('@') ||
        host.contains(' ')) {
      return null;
    }
    return host;
  }

  static Map<String, String> _validatedHeaders(Object? input) {
    if (input == null) return <String, String>{};
    if (input is! Map) {
      throw const FormatException('HTTP headers must be an object.');
    }
    if (input.length > _maxHeaderCount) {
      throw const FormatException('Too many HTTP request headers.');
    }
    final headers = <String, String>{};
    var encodedSize = 0;
    for (final entry in input.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('HTTP header names and values must be strings.');
      }
      final name = (entry.key as String).toLowerCase();
      final value = entry.value as String;
      if (!RegExp(r"^[!#$%&'*+\-.^_`|~0-9a-z]+$").hasMatch(name) ||
          value.contains('\r') ||
          value.contains('\n') ||
          _blockedRequestHeaders.contains(name)) {
        throw FormatException('HTTP request header is not permitted: $name');
      }
      encodedSize += utf8.encode(name).length + utf8.encode(value).length;
      if (encodedSize > _maxHeaderBytes) {
        throw const FormatException('HTTP request headers exceed the size limit.');
      }
      headers[name] = value;
    }
    return headers;
  }

  String? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is String) return body;
    if (body is Map || body is List) return jsonEncode(body);
    throw const FormatException('HTTP body must be a string, object, or array.');
  }

  Future<Map<String, Object?>> _send(
    http.Client client,
    Uri uri,
    String method,
    Map<String, String> headers,
    String? body,
  ) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (body != null) request.body = body;
    final response = await client.send(request).timeout(requestTimeout);

    if (response.headers.length > _maxHeaderCount) {
      throw const FormatException('Provider response has too many headers.');
    }
    var responseHeaderBytes = 0;
    final responseHeaders = <String, String>{};
    for (final entry in response.headers.entries) {
      responseHeaderBytes +=
          utf8.encode(entry.key).length + utf8.encode(entry.value).length;
      if (responseHeaderBytes > _maxHeaderBytes) {
        throw const FormatException('Provider response headers exceed the size limit.');
      }
      if (!_blockedResponseHeaders.contains(entry.key.toLowerCase())) {
        responseHeaders[entry.key.toLowerCase()] = entry.value;
      }
    }

    final bytes = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in response.stream.timeout(requestTimeout)) {
      received += chunk.length;
      if (received > maxResponseBodyBytes) {
        throw FormatException(
          'HTTP response exceeds $maxResponseBodyBytes bytes.',
        );
      }
      bytes.add(chunk);
    }
    return <String, Object?>{
      'statusCode': response.statusCode,
      'headers': responseHeaders,
      'body': utf8.decode(bytes.takeBytes(), allowMalformed: true),
    };
  }
}
