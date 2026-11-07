import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/data/secureStorage.dart';
import 'package:animestream/core/integrations/discord/desktopRPC.dart';
import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/foundation.dart';

/// How Discord should render the activity.
///
/// [streaming] is the purple "Streaming" status and needs [PresenceActivity.url].
/// [watching] prints "Watching anImestream" with the details below it, which is
/// what the manga reader uses ("Reading <title>").
enum PresenceActivityType {
  playing(0),
  streaming(1),
  listening(2),
  watching(3);

  const PresenceActivityType(this.code);

  final int code;
}

/// Platform-neutral activity. The desktop IPC client and the mobile gateway
/// client each translate this into their own payload.
class PresenceActivity {
  final String name;
  final PresenceActivityType type;
  final String? details;
  final String? state;
  final String? url;
  final int? start;

  const PresenceActivity({
    this.name = 'anImestream',
    required this.type,
    this.details,
    this.state,
    this.url,
    this.start,
  });

  static String _clamp(String value) {
    if (value.length <= 128) return value;
    // Cut on code points, not UTF-16 units, so a surrogate pair is never split.
    final runes = value.runes;
    final buffer = StringBuffer();
    var count = 0;
    for (final rune in runes) {
      if (count == 128) break;
      buffer.writeCharCode(rune);
      count++;
    }
    return buffer.toString();
  }

  Map<String, dynamic> toGatewayJson() {
    final activity = <String, dynamic>{
      'name': _clamp(name),
      'type': type.code,
    };
    if (url != null) activity['url'] = url;
    if (details != null && details!.trim().isNotEmpty) activity['details'] = _clamp(details!.trim());
    if (state != null && state!.trim().isNotEmpty) activity['state'] = _clamp(state!.trim());
    if (start != null) activity['timestamps'] = <String, dynamic>{'start': start};
    return activity;
  }

  DiscordPresence toDesktopPresence() {
    return DiscordPresence(
      type: switch (type) {
        PresenceActivityType.playing => DiscordActivityType.playing,
        PresenceActivityType.streaming => DiscordActivityType.streaming,
        PresenceActivityType.listening => DiscordActivityType.listening,
        PresenceActivityType.watching => DiscordActivityType.watching,
      },
      details: details,
      statusDisplayType: DiscordStatusDisplayType.details,
      state: state,
      timestamps: start != null ? DiscordTimestamps(start: start) : null,
    );
  }
}

class DiscordPresenceException implements Exception {
  final String message;
  const DiscordPresenceException(this.message);

  @override
  String toString() => message;
}

/// The token lives in the platform keystore (Android Keystore / iOS Keychain,
/// via flutter_secure_storage) and nowhere else. It is never written to Hive,
/// never logged, and never leaves the process except in the TLS handshake with
/// gateway.discord.gg.
class DiscordTokenStore {
  static const SecureStorageKey _key = SecureStorageKey.discordToken;

  static String normalize(String input) {
    var token = input.trim();
    if (token.length >= 2) {
      final first = token[0];
      final last = token[token.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        token = token.substring(1, token.length - 1).trim();
      }
    }
    return token;
  }

  /// Returns a human readable reason, or null when [input] looks like a Discord
  /// user token. Bot tokens are rejected on purpose: presence from a bot shows
  /// as the bot, not as the user.
  static String? validationError(String input) {
    final token = normalize(input);
    if (token.isEmpty) return 'Paste a Discord token.';
    if (token.toLowerCase().startsWith('bot ')) {
      return 'That is a bot token. Use your own user token (no "Bot " prefix).';
    }
    if (token.contains(RegExp(r'\s'))) {
      return 'That does not look like a Discord token.';
    }
    if (token.length < 50 || token.length > 120) {
      return 'That does not look like a Discord token.';
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(token)) {
      return 'That does not look like a Discord token.';
    }
    if (RegExp(r'\.').allMatches(token).length < 2) {
      return 'That does not look like a Discord token.';
    }
    return null;
  }

  static Future<bool> hasToken() async {
    try {
      final token = await getSecureVal(_key);
      return token != null && token.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> read() async {
    try {
      final token = await getSecureVal(_key);
      if (token == null) return null;
      final normalized = normalize(token);
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String token) => storeSecureVal(_key, normalize(token));

  static Future<void> clear() => storeSecureVal(_key, null);
}

/// Discord Gateway client. This is the only way to publish Rich Presence from
/// Android: the Gateway accepts a user token over a plain WebSocket, while the
/// official IPC/RPC path only exists on desktop Discord clients.
class DiscordGatewayRPC {
  /// Host is fixed so the token can only ever be sent to Discord. No user input
  /// reaches this URL.
  static const String _gatewayUrl = 'wss://gateway.discord.gg/?v=10&encoding=json';
  static const String _gatewayHost = 'gateway.discord.gg';

  /// Presence updates are throttled; the gateway rate-limits them and a burst
  /// of updates is exactly what anti-abuse looks for.
  static const Duration _presenceInterval = Duration(seconds: 15);

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeat;
  Timer? _presenceTimer;
  Timer? _reconnectTimer;
  int? _sequence;
  int _reconnectAttempts = 0;
  String? _token;
  bool _ready = false;
  bool _disposed = false;
  PresenceActivity? _pending;
  DateTime _lastPresence =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  bool get isConnected => connected.value;

  bool get isDisposed => _disposed;

  Future<void> connect() async {
    if (_disposed) return;
    if (_ready && _socket != null) return;

    final token = await DiscordTokenStore.read();
    if (token == null) {
      throw const DiscordPresenceException('No Discord token saved. Add one in Settings > General.');
    }
    final problem = DiscordTokenStore.validationError(token);
    if (problem != null) throw DiscordPresenceException(problem);

    final uri = Uri.parse(_gatewayUrl);
    if (uri.scheme != 'wss' || uri.host != _gatewayHost) {
      throw const DiscordPresenceException('Refusing to send the token to an unexpected host.');
    }

    await _closeSocket();

    _token = token;
    final socket = await WebSocket.connect(uri.toString())
        .timeout(const Duration(seconds: 15));
    // Keep the connection alive through NAT timeouts without touching the
    // application-level heartbeat.
    socket.pingInterval = const Duration(seconds: 30);
    _socket = socket;

    _subscription = socket.listen(
      _handlePayload,
      onDone: () => _handleClosed(socket.closeCode),
      onError: (Object _) => _handleClosed(socket.closeCode),
      cancelOnError: false,
    );
  }

  Future<void> setActivity(PresenceActivity? activity) async {
    if (_disposed) return;
    _pending = activity;
    if (!_ready) return;
    _schedulePresence();
  }

  Future<void> dispose() async {
    _disposed = true;
    _heartbeat?.cancel();
    _presenceTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeat = null;
    _presenceTimer = null;
    _reconnectTimer = null;
    _ready = false;
    _pending = null;
    _token = null;
    _sequence = null;
    await _closeSocket();
    connected.value = false;
  }

  void _send(Map<String, dynamic> payload) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(payload));
    } catch (_) {
      // A closed socket is handled by onDone/onError.
    }
  }

  void _handlePayload(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final sequence = payload['s'];
    if (sequence is int) _sequence = sequence;

    final op = payload['op'];
    final data = payload['d'];
    switch (op) {
      case 0:
        if (payload['t'] == 'READY') {
          _ready = true;
          _reconnectAttempts = 0;
          connected.value = true;
          error.value = null;
          _flushPresence();
        }
        break;
      case 1:
        _sendHeartbeat();
        break;
      case 7:
        unawaited(_reconnect());
        break;
      case 9:
        final resumable = data == true;
        if (!resumable) {
          _sequence = null;
          _ready = false;
        }
        unawaited(_reconnect());
        break;
      case 10:
        final interval = data is Map ? data['heartbeat_interval'] : null;
        if (interval is int && interval > 0) _startHeartbeat(interval);
        _identify();
        break;
      case 11:
        break;
    }
  }

  void _identify() {
    final token = _token;
    if (token == null) return;
    _send(<String, dynamic>{
      'op': 2,
      'd': <String, dynamic>{
        'token': token,
        'compress': false,
        'properties': <String, dynamic>{
          'os': Platform.operatingSystem,
          'browser': (Platform.isAndroid || Platform.isIOS) ? 'Discord Android' : 'Discord Client',
          'device': 'anImestream',
        },
        'presence': <String, dynamic>{
          'since': 0,
          'activities': <dynamic>[],
          'status': 'online',
          'afk': false,
        },
      },
    });
  }

  void _startHeartbeat(int intervalMs) {
    _heartbeat?.cancel();
    final interval = Duration(milliseconds: intervalMs);
    final first = Duration(milliseconds: (intervalMs * 0.5).round());
    _heartbeat = Timer(first, () {
      _sendHeartbeat();
      _heartbeat = Timer.periodic(interval, (_) => _sendHeartbeat());
    });
  }

  void _sendHeartbeat() => _send(<String, dynamic>{'op': 1, 'd': _sequence});

  void _schedulePresence() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastPresence);
    if (elapsed >= _presenceInterval) {
      _flushPresence();
      return;
    }
    _presenceTimer?.cancel();
    _presenceTimer = Timer(_presenceInterval - elapsed, _flushPresence);
  }

  void _flushPresence() {
    if (_disposed || !_ready || _socket == null) return;
    _lastPresence = DateTime.now();
    final activity = _pending;
    _send(<String, dynamic>{
      'op': 3,
      'd': <String, dynamic>{
        'since': 0,
        'activities': activity == null ? <dynamic>[] : <dynamic>[activity.toGatewayJson()],
        'status': 'online',
        'afk': false,
      },
    });
  }

  Future<void> _reconnect() async {
    if (_disposed) return;
    _ready = false;
    connected.value = false;
    _heartbeat?.cancel();
    await _closeSocket();
    if (_disposed) return;

    _reconnectAttempts++;
    if (_reconnectAttempts > 5) {
      error.value = 'Lost the Discord connection.';
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _reconnectAttempts * 2), () async {
      if (_disposed) return;
      try {
        await connect();
      } catch (e) {
        if (!_disposed) unawaited(_reconnect());
      }
    });
  }

  void _handleClosed(int? closeCode) {
    _ready = false;
    connected.value = false;
    if (_disposed) return;

    // 4004 is "authentication failed": reconnecting with the same token can
    // only produce the same answer, so stop and surface it.
    if (closeCode == 4004) {
      error.value = 'Discord rejected the token. It may have been reset.';
      unawaited(dispose());
      return;
    }
    unawaited(_reconnect());
  }

  Future<void> _closeSocket() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final socket = _socket;
    _socket = null;
    try {
      await socket?.close(WebSocketStatus.normalClosure);
    } catch (e) {
      Logs.app.log('Discord socket close failed: $e');
    }
  }
}

/// Single entry point used by the player and the manga reader.
///
/// Desktop keeps the existing local IPC client and only switches to the gateway
/// when a token is saved. Android and iOS always use the gateway, because their
/// Discord app does not expose an IPC socket.
class DiscordPresenceManager {
  DiscordPresenceManager._();

  static final DiscordPresenceManager instance = DiscordPresenceManager._();

  final ValueNotifier<String?> lastError = ValueNotifier<String?>(null);

  DiscordGatewayRPC? _gateway;
  DiscordDesktopRPC? _desktop;

  bool get _enabled => currentUserSettings?.enableDiscordRichPresence ?? false;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// True once the gateway has completed IDENTIFY (or the desktop IPC client is
  /// connected).
  bool get isConnected => _gateway?.isConnected ?? _desktop != null;

  Future<void> start() async {
    if (!_enabled) return;
    lastError.value = null;

    if (_isMobile) {
      await _startGateway();
      return;
    }

    // On desktop a token is optional: without one, talk to the local client
    // over IPC exactly as before.
    if (await DiscordTokenStore.hasToken()) {
      await _startGateway();
      return;
    }

    if (_desktop == null) {
      try {
        final desktop = DiscordDesktopRPC();
        await desktop.initiateConnection();
        _desktop = desktop;
      } catch (e) {
        lastError.value = 'Discord is not running.';
        _desktop = null;
      }
    }
  }

  Future<void> _startGateway() async {
    var gateway = _gateway;
    if (gateway == null || gateway.isDisposed) {
      gateway = DiscordGatewayRPC();
      gateway.error.addListener(_mirrorError);
      _gateway = gateway;
    }
    try {
      await gateway.connect();
      lastError.value = null;
    } on DiscordPresenceException catch (e) {
      lastError.value = e.message;
      await _gateway?.dispose();
      _gateway = null;
    } catch (e) {
      lastError.value = 'Could not connect to Discord.';
      Logs.app.log('Discord gateway connect failed: $e');
      await _gateway?.dispose();
      _gateway = null;
    }
  }

  void _mirrorError() {
    final message = _gateway?.error.value;
    if (message != null) lastError.value = message;
  }

  Future<void> setActivity(PresenceActivity? activity) async {
    if (!_enabled) return;

    final gateway = _gateway;
    if (gateway != null) {
      await gateway.setActivity(activity);
      return;
    }

    final desktop = _desktop;
    if (desktop == null) return;
    try {
      if (activity == null) {
        await desktop.clearPresence();
      } else {
        await desktop.updatePresence(activity.toDesktopPresence());
      }
    } catch (e) {
      Logs.app.log('Discord presence update failed: $e');
    }
  }

  Future<void> stop() async {
    await _gateway?.dispose();
    _gateway = null;
    await _desktop?.dispose();
    _desktop = null;
  }
}
