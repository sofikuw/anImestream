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
    this.allowSubdomains = false,
    this.followRedirects = false,
    this.maxRedirects = 5,
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
    // 'cookie' used to be blocked here. Providers that authorise playback
    // with a Cookie header -- AnimeHeaven's gate.php sends a cookie with key=<gateKey>
    // -- cannot work with it blocked.
    //
    // This does not expose the app's sessions: the runtime's client is a bare
    // HttpClient() with no cookie jar, so it shares no state with AniList,
    // SimKL or any other session in the app. A provider can only set its own
    // cookie, never read one. Header-name and value validation (which rejects
    // CR/LF, and so blocks header injection) still runs before this list.
    //
    // 'authorization' stays blocked until a provider genuinely needs it.
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

  /// When true, `cdn.example.com` also satisfies an allowlisted `example.com`.
  ///
  /// MangaYomi sources routinely serve pages from a parent domain and images
  /// from a subdomain, so their bridges opt in. Native providers keep the
  /// exact-host behaviour.
  final bool allowSubdomains;

  /// When true, redirects are followed manually, revalidating every hop
  /// against the allowlist. Disabled for native providers.
  final bool followRedirects;
  final int maxRedirects;

  static const Set<String> _methods = <String>{
    'GET',
    'HEAD',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  };

  Future<Object?> request(Map<String, Object?> input) async {
    final url = input['url'];
    if (url is! String || url.length > 4096) {
      throw const FormatException('HTTP request URL must be a string under 4096 characters.');
    }
    final uri = _resolveUrl(url);
    final method = (input['method'] as String? ?? 'GET').toUpperCase();
    if (!_methods.contains(method)) {
      throw FormatException('Unsupported HTTP method: $method.');
    }
    if (method == 'HEAD' && input['body'] != null) {
      throw const FormatException('HEAD requests must not include a body.');
    }

    final headers = _validatedHeaders(input['headers']);
    final body = _encodeBody(input['body']);
    if (body != null && (method == 'GET' || method == 'HEAD')) {
      throw FormatException('$method requests must not include a body.');
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

  /// Validates [rawUrl] against this instance's allowlist, honouring
  /// [allowSubdomains].
  Uri _resolveUrl(String rawUrl) {
    final uri = _parseHttpsUrl(rawUrl);
    final host = _normalizeAllowedHost(uri.host);
    if (host == null || !ProviderRepository.isPublicDnsHost(host)) {
      throw const FormatException('IP-literal and invalid hosts are blocked.');
    }
    final permitted = _allowedHosts.contains(host) ||
        (allowSubdomains &&
            _allowedHosts.any((allowed) => host.endsWith('.$allowed')));
    if (!permitted) {
      throw FormatException('Provider host is not allowlisted: $host');
    }
    return uri.replace(scheme: 'https', host: host);
  }

  static Uri _parseHttpsUrl(String rawUrl) {
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
    if (uri.host.startsWith('[')) {
      throw const FormatException('IP-literal and invalid hosts are blocked.');
    }
    return uri;
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
    var currentUri = uri;
    var currentMethod = method;
    var currentBody = body;
    http.StreamedResponse? response;
    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = http.Request(currentMethod, currentUri)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (currentBody != null) request.body = currentBody;
      response = await client.send(request).timeout(requestTimeout);

      final location = response.headers['location'];
      final isRedirect = response.statusCode >= 300 && response.statusCode < 400;
      if (!isRedirect || location == null) break;
      if (!followRedirects) {
        throw const FormatException('Provider redirects are not permitted.');
      }
      if (hop == maxRedirects) {
        throw const FormatException('Provider redirected too many times.');
      }
      final nextUri = _resolveUrl(
        currentUri.resolve(location.trim()).toString(),
      );
      await response.stream.drain<void>();
      // 303, and 301/302 on POST, drop the body and become a GET.
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              currentMethod == 'POST')) {
        currentMethod = 'GET';
        currentBody = null;
      }
      currentUri = nextUri;
    }
    if (response == null) {
      throw StateError('Provider HTTP request produced no response.');
    }

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
    if (currentMethod != 'HEAD') {
      await for (final chunk in response.stream.timeout(requestTimeout)) {
        received += chunk.length;
        if (received > maxResponseBodyBytes) {
          throw FormatException(
            'HTTP response exceeds $maxResponseBodyBytes bytes.',
          );
        }
        bytes.add(chunk);
      }
    }
    return <String, Object?>{
      'statusCode': response.statusCode,
      'statusMessage': response.reasonPhrase ?? '',
      // MangaYomi and Tachiyomi sources read `reasonPhrase`; the native
      // contract reads `statusMessage`.
      'reasonPhrase': response.reasonPhrase ?? '',
      'headers': responseHeaders,
      'body': utf8.decode(bytes.takeBytes(), allowMalformed: true),
      'isRedirect': response.isRedirect,
      'persistentConnection': response.persistentConnection,
      'request': <String, Object?>{'url': currentUri.toString()},
    };
  }
}
