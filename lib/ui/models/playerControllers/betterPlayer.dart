import 'dart:io';

import 'package:animestream/core/commons/extractQuality.dart';
import 'package:animestream/core/app/ios_pip_service.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/widgets/player/playerUtils.dart';
import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';

/// Better Player-backed controller used on mobile platforms.
///
/// The important PiP detail is that the GlobalKey below is attached to the
/// actual BetterPlayer widget. Better Player then owns the native
/// AVPictureInPictureController and its AVPlayerLayer on iOS.
class BetterPlayerWrapper implements VideoController {
  late BetterPlayerController controller;

  final GlobalKey<State<StatefulWidget>> betterPlayerKey =
      GlobalKey<State<StatefulWidget>>();

  final List<VoidCallback> _listeners = [];
  bool _initialized = false;
  bool _offline = false;
  String? _activeUrl;
  Map<String, String>? _headers;

  BetterPlayerWrapper();

  Future<void> _createController() async {
    controller = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        looping: false,
        fit: BoxFit.contain,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        autoDetectFullscreenDeviceOrientation: true,
        pipConfiguration: BetterPlayerPipConfiguration(
          aspectRatio: 16 / 9,
        ),
        eventListener: (event) {
          if (event.betterPlayerEventType == BetterPlayerEventType.pipStart) {
            IosPipService().setActive(true);
          } else if (event.betterPlayerEventType ==
              BetterPlayerEventType.pipStop) {
            IosPipService().setActive(false);
          }
        },
      ),
    );
  }

  @override
  Future<void> initiateVideo(
    String url, {
    Map<String, String>? headers,
    bool offline = false,
  }) async {
    final volume = _initialized ? (controller.videoPlayerController?.value.volume ?? 1.0) : 1.0;

    if (_initialized) {
      controller.dispose();
      _initialized = false;
    }

    await _createController();

    final BetterPlayerDataSource dataSource;
    if (offline) {
      dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.file,
        url,
        useAsmsSubtitles: true,
        useAsmsTracks: true,
        useAsmsAudioTracks: true,
      );
    } else {
      dataSource = await dataSourceConfig(url, headers: headers);
    }

    await controller.setupDataSource(dataSource);
    await controller.setVolume(volume);

    _activeUrl = url;
    _headers = headers;
    _offline = offline;
    _initialized = true;

    for (final listener in _listeners) {
      controller.videoPlayerController?.addListener(listener);
    }
  }

  @override
  Widget getWidget() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: BetterPlayer(
        key: betterPlayerKey,
        controller: controller,
      ),
    );
  }

  /// Enter PiP through Better Player. On iOS the key must be attached to the
  /// BetterPlayer widget rendered by [getWidget].
  Future<void> enterPictureInPicture() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    if (!await controller.isPictureInPictureSupported()) return;
    await controller.enablePictureInPicture(betterPlayerKey);
  }

  Future<void> exitPictureInPicture() async {
    await controller.disablePictureInPicture();
  }

  @override
  Future<void> play() => controller.play();

  @override
  Future<void> pause() => controller.pause();

  @override
  Future<void> seekTo(Duration duration) => controller.seekTo(duration);

  @override
  Future<void> setSpeed(double speed) => controller.setSpeed(speed);

  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);

  @override
  void setFit(BoxFit fit) => controller.setOverriddenFit(fit);

  @override
  Future<void> setPip(bool value) async {
    if (value) {
      await enterPictureInPicture();
    } else {
      await exitPictureInPicture();
    }
  }

  @override
  void setAudioTrack(AudioStream aud) {
    // Better Player exposes audio-track selection for HLS/DASH through its
    // native track APIs. Keep this as a no-op for file/non-adaptive sources.
  }

  @override
  void setQuality(QualityStream qs) async {
    await initiateVideo(qs.url, headers: _headers, offline: _offline);
  }

  @override
  void addListener(VoidCallback cb) {
    _listeners.add(cb);
    if (_initialized) controller.videoPlayerController?.addListener(cb);
  }

  @override
  void removeListener(VoidCallback cb) {
    _listeners.remove(cb);
    if (_initialized) controller.videoPlayerController?.removeListener(cb);
  }

  @override
  void dispose() {
    IosPipService().setActive(false);
    if (_initialized) controller.dispose();
    _initialized = false;
  }

  @override
  bool? get isPlaying => controller.isPlaying();

  @override
  bool? get isBuffering => controller.isBuffering();

  @override
  int? get position => controller.videoPlayerController?.value.position.inMilliseconds;

  @override
  int? get duration => controller.videoPlayerController?.value.duration.inMilliseconds;

  @override
  int? get buffered {
    final ranges = controller.videoPlayerController?.value.buffered;
    if (ranges == null || ranges.isEmpty) return 0;
    return ranges.last.end.inMilliseconds;
  }

  @override
  double? get volume => controller.videoPlayerController?.value.volume;

  @override
  String? get activeMediaUrl => _activeUrl;

  @override
  bool? get isInitialized => controller.isVideoInitialized();
}

/// Compatibility alias for code that used the experimental wrapper name.
typedef BetterPlayerControllerWrapper = BetterPlayerWrapper;
