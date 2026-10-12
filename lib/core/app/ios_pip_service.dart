import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart Service for managing iOS YouTube-style Picture-in-Picture.
/// Communicates with native Swift layer via MethodChannel `com.animestream/pip`.
class IosPipService {
  static const MethodChannel _channel = MethodChannel('com.animestream/pip');
  static final IosPipService _instance = IosPipService._internal();

  factory IosPipService() => _instance;

  IosPipService._internal() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final ValueNotifier<bool> isPipActiveNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isAutoPipEnabledNotifier = ValueNotifier<bool>(true);

  bool get isPipActive => isPipActiveNotifier.value;
  bool get isAutoPipEnabled => isAutoPipEnabledNotifier.value;

  /// Check if the current device/iOS version supports PiP
  Future<bool> isPipSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final bool? supported = await _channel.invokeMethod<bool>('isPipSupported');
      return supported ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error checking PiP support: ${e.message}');
      return false;
    }
  }

  /// Enable or disable automatic PiP when swiping home (like YouTube on iOS 15+)
  Future<bool> setAutoPipEnabled(bool enable) async {
    if (!Platform.isIOS) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('enableAutoPip', {'enable': enable});
      isAutoPipEnabledNotifier.value = enable;
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error setting auto PiP: ${e.message}');
      return false;
    }
  }

  /// Manually trigger Picture-in-Picture from Dart (e.g. clicking the PiP button)
  Future<bool> startPictureInPicture() async {
    if (!Platform.isIOS) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('startPip');
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error starting PiP: ${e.message}');
      return false;
    }
  }

  /// Stop Picture-in-Picture and return to the main app
  Future<bool> stopPictureInPicture() async {
    if (!Platform.isIOS) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('stopPip');
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('Error stopping PiP: ${e.message}');
      return false;
    }
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipStateChanged':
        final bool isActive = call.arguments?['isActive'] ?? false;
        isPipActiveNotifier.value = isActive;
        debugPrint('Animestream PiP State Changed: $isActive');
        break;
      default:
        break;
    }
  }
}
