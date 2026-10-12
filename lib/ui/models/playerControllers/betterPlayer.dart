import 'dart:io';
import 'package:flutter/material.dart';
import 'package:better_player/better_player.dart';
import 'package:animestream/core/app/ios_pip_service.dart';
import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/commons/extractQuality.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/widgets/player/playerUtils.dart';

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

/// Adapter used by the app's existing playback flow.
///
/// Keep the app-facing VideoController API separate from the experimental
/// controller wrapper above; server selection and downloads depend on it.
class BetterPlayerWrapper implements VideoController {
  late BetterPlayerController controller = BetterPlayerController(_config);
  final List<VoidCallback?> listeners = [];
  final key = GlobalKey();

  static final _config = BetterPlayerConfiguration(
    aspectRatio: 16 / 9,
    fit: BoxFit.contain,
    expandToFill: true,
    autoPlay: true,
    errorBuilder: (context, errorMessage) => Center(
      child: Text(
        "Whoops! Ran into some errors playing this video!\nDetails:\n$errorMessage",
        style: const TextStyle(fontSize: 20),
      ),
    ),
    eventListener: (event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
        Logs.player.log("[PLAYER] Playback error: ${event.parameters}");
      }
    },
    handleLifecycle: !Platform.isIOS,
    autoDispose: true,
    controlsConfiguration: const BetterPlayerControlsConfiguration(showControls: false),
  );

  @override
  Future<void> initiateVideo(String url, {Map<String, String>? headers, bool offline = false}) async {
    final dataSource = offline
        ? BetterPlayerDataSource.file(url)
        : await dataSourceConfig(url, headers: headers);
    await controller.setupDataSource(dataSource);
  }

  @override
  bool? get isBuffering => controller.isBuffering();
  @override
  bool? get isPlaying => controller.isPlaying();
  @override
  int? get position => controller.videoPlayerController?.value.position.inMilliseconds;
  @override
  int? get duration => controller.videoPlayerController?.value.duration?.inMilliseconds;
  @override
  int? get buffered => controller.videoPlayerController?.value.buffered.lastOrNull?.end.inSeconds;
  @override
  double? get volume => controller.videoPlayerController?.value.volume;
  @override
  String? get activeMediaUrl => controller.betterPlayerDataSource?.url;
  @override
  bool? get isInitialized => controller.isVideoInitialized();

  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> play() => controller.play();
  @override
  Future<void> seekTo(Duration duration) => controller.seekTo(duration);
  @override
  Future<void> setSpeed(double speed) => controller.setSpeed(speed);
  @override
  Future<void> setVolume(double volume) => controller.setVolume(volume);
  @override
  void dispose() => controller.dispose();
  @override
  Widget getWidget() => BetterPlayer(controller: controller, key: key);
  @override
  void addListener(VoidCallback callback) {
    listeners.add(callback);
    controller.videoPlayerController?.addListener(callback);
  }
  @override
  void removeListener(VoidCallback callback) {
    controller.videoPlayerController?.removeListener(callback);
    listeners.remove(callback);
  }
  @override
  void setFit(BoxFit fit) => controller.setOverriddenFit(fit);

  @override
  Future<void> setPip(bool value) async {
    final operation = value ? controller.enablePictureInPicture(key) : controller.disablePictureInPicture();
    if (operation != null) await operation;
  }

  @override
  Future<void> setAudioTrack(AudioStream audio) async {
    final tracks = controller.betterPlayerAsmsAudioTracks;
    if (tracks == null || tracks.isEmpty) return;
    final track = tracks.firstWhere(
      (item) => item.label == audio.name && item.language == audio.language,
      orElse: () => tracks.firstWhere(
        (item) => item.language == audio.language,
        orElse: () => tracks.first,
      ),
    );
    controller.setAudioTrack(track);
  }

  @override
  void setQuality(QualityStream quality) {
    final tracks = controller.betterPlayerAsmsTracks;
    if (tracks.isEmpty) return;
    final height = int.tryParse(quality.resolution.split('x').last) ?? 0;
    final track = tracks.firstWhere(
      (item) => item.height == height && item.bitrate == (quality.bandwidth ?? 0),
      orElse: () => tracks.first,
    );
    controller.setTrack(track);
  }
}
