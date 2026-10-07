import 'dart:io';
import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:animestream/core/app/ios_pip_service.dart';

class BetterPlayerControllerWrapper {
  late BetterPlayerController controller;
  final GlobalKey betterPlayerKey = GlobalKey();

  void initialize({
    required String url,
    bool autoPlay = true,
    double aspectRatio = 16 / 9,
  }) {
    final dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      url,
      useAsmsSubtitles: true,
      useAsmsTracks: true,
      useAsmsAudioTracks: true,
    );

    final betterPlayerConfiguration = BetterPlayerConfiguration(
      aspectRatio: aspectRatio,
      fit: BoxFit.contain,
      autoPlay: autoPlay,
      looping: false,
      fullScreenByDefault: false,
      allowedScreenSleep: false,
      autoDetectFullscreenDeviceOrientation: true,
      // PiP Configuration for iOS & Android
      pipConfiguration: BetterPlayerPipConfiguration(
        aspectRatio: aspectRatio,
      ),
      eventListener: (BetterPlayerEvent event) {
        if (event.betterPlayerEventType == BetterPlayerEventType.pipStart) {
          IosPipService().isPipActiveNotifier.value = true;
        } else if (event.betterPlayerEventType == BetterPlayerEventType.pipStop) {
          IosPipService().isPipActiveNotifier.value = false;
        }
      },
    );

    controller = BetterPlayerController(betterPlayerConfiguration);
    controller.setupDataSource(dataSource);

    // If on iOS, initialize the native iOS PiP service
    if (Platform.isIOS) {
      IosPipService().setAutoPipEnabled(true);
    }
  }

  /// Triggers PiP on iOS/Android
  Future<void> enterPictureInPicture() async {
    if (Platform.isIOS) {
      // First attempt native controller PiP
      final bool nativeSuccess = await IosPipService().startPictureInPicture();
      if (!nativeSuccess) {
        controller.enablePictureInPicture(betterPlayerKey);
      }
    } else {
      controller.enablePictureInPicture(betterPlayerKey);
    }
  }

  void dispose() {
    controller.dispose();
  }
}
