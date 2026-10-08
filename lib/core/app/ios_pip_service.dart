import 'dart:io';

import 'package:flutter/foundation.dart';

/// Lightweight PiP state service.
///
/// Native PiP is owned by Better Player. Keeping a second AVPictureInPicture-
/// Controller in the Runner app creates a detached player layer and cannot
/// control the Flutter player's video. This service therefore only exposes
/// state to the Flutter UI.
class IosPipService {
  static final IosPipService _instance = IosPipService._internal();

  factory IosPipService() => _instance;

  IosPipService._internal();

  final ValueNotifier<bool> isPipActiveNotifier = ValueNotifier<bool>(false);

  bool get isPipActive => isPipActiveNotifier.value;

  bool get isSupportedPlatform => Platform.isIOS || Platform.isAndroid;

  void setActive(bool active) {
    if (isPipActiveNotifier.value != active) {
      isPipActiveNotifier.value = active;
    }
  }

  void dispose() {
    isPipActiveNotifier.dispose();
  }
}
