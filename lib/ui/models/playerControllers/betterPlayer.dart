import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/commons/extractQuality.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/widgets/player/playerUtils.dart';
import 'package:better_player/better_player.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class BetterPlayerWrapper implements VideoController {
  late BetterPlayerController controller = BetterPlayerController(_config);

  final List<VoidCallback?> listeners = [];

  final key = GlobalKey();

  static final _config = BetterPlayerConfiguration(
    aspectRatio: 16 / 9,
    fit: BoxFit.contain,
    expandToFill: true,
    autoPlay: true,
    errorBuilder: (context, errorMessage) {
      return Center(
          child: Text(
        "Whoops! Ran into some errors playing this video!\nDetails:\n$errorMessage",
        style: TextStyle(fontSize: 20),
      ));
    },
    eventListener: (ev) {
      if (ev.betterPlayerEventType == BetterPlayerEventType.exception) {
        Logs.player.log("[PLAYER] Oooooooh! We've got some issues!!! \n${ev.parameters}");
      }
    },
    // iOS PiP must remain playing while the app transitions to the background.
    // Watch manages ordinary background pause/resume on iOS itself.
    handleLifecycle: !Platform.isIOS,
    autoDispose: true,
    controlsConfiguration: BetterPlayerControlsConfiguration(
      showControls: false,
    ),
  );

  @override
  Future<void> initiateVideo(String url, {Map<String, String>? headers, bool offline = false}) async {
    final ds = offline
        ? BetterPlayerDataSource.file(url)
        : await dataSourceConfig(url, headers: headers);
    await controller.setupDataSource(ds);
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
  Future<void> pause() {
    return controller.pause();
  }

  @override
  Future<void> play() {
    return controller.play();
  }

  @override
  Future<void> seekTo(Duration duration) {
    return controller.seekTo(duration);
  }

  @override
  Future<void> setSpeed(double speed) => controller.setSpeed(speed);

  @override
  void dispose() {
    return controller.dispose();
  }

  @override
  Widget getWidget() {
    return BetterPlayer(controller: controller, key: key);
  }

  @override
  void addListener(VoidCallback cb) {
    listeners.add(cb);
    controller.videoPlayerController?.addListener(cb);
  }

  @override
  void setFit(BoxFit fit) {
    return controller.setOverriddenFit(fit);
  }

  @override
  Future<void> setVolume(double volume) {
    return controller.setVolume(volume);
  }

  @override
  void removeListener(VoidCallback cb) {
    return controller.videoPlayerController?.removeListener(cb);
  }

  @override
  Future<void> setPip(bool value) async {
    if (value) {
      final operation = controller.enablePictureInPicture(key);
      if (operation != null) {
        await operation;
      }
    } else {
      final operation = controller.disablePictureInPicture();
      if (operation != null) {
        await operation;
      }
    }
  }

  /// Sources whose ASMS manifest has already been waited for, so a stream
  /// without separate tracks (or one the parser could not fetch) is only
  /// waited on once instead of stalling every later query.
  String? _audioWaitedFor;
  String? _videoWaitedFor;

  static const _asmsWaitAttempts = 20;

  @override
  Future<List<AudioStream>> getAudioTracks() async {
    try {
      final tracks = await _waitForAsms(
        audio: true,
        read: () => controller.betterPlayerAsmsAudioTracks,
      );
      if (tracks == null || tracks.isEmpty) {
        Logs.player.log("Player exposed no separate audio tracks for this stream");
        return [];
      }
      Logs.player.log("Player exposed ${tracks.length} audio track(s)");
      return tracks.map((t) {
        return AudioStream(
          groupId: (t.id ?? 0).toString(),
          name: t.label ?? t.language ?? "Track ${t.id}",
          url: "${controller.betterPlayerDataSource?.url}#track_${t.id}",
          language: t.language ?? "und",
          channels: "stereo",
        );
      }).toList();
    } catch (e) {
      Logs.player.log("Failed to get audio tracks in BetterPlayerWrapper: $e");
      return [];
    }
  }

  /// better_player parses the HLS/DASH master playlist in the background
  /// (setupDataSource does not await it), so the first query usually races it.
  Future<List<T>?> _waitForAsms<T>({required bool audio, required List<T>? Function() read}) async {
    final source = controller.betterPlayerDataSource;
    final url = source?.url;
    final asmsEnabled = audio ? source?.useAsmsAudioTracks : source?.useAsmsTracks;
    if (source == null || url == null || asmsEnabled != true) return read();
    final lower = url.toLowerCase();
    final isAsms = source.videoFormat == BetterPlayerVideoFormat.hls ||
        source.videoFormat == BetterPlayerVideoFormat.dash ||
        lower.contains('.m3u8') ||
        lower.contains('.mpd');
    if (!isAsms) return read();

    var tracks = read();
    final alreadyWaited = audio ? _audioWaitedFor == url : _videoWaitedFor == url;
    if (tracks == null && !alreadyWaited) {
      if (audio) {
        _audioWaitedFor = url;
      } else {
        _videoWaitedFor = url;
      }
      for (var attempt = 0; attempt < _asmsWaitAttempts && tracks == null; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        tracks = read();
      }
    }
    return tracks;
  }

  @override
  Future<void> setAudioTrack(AudioStream aud) async {
    final asmsTracks = await _waitForAsms(
      audio: true,
      read: () => controller.betterPlayerAsmsAudioTracks,
    );
    if (asmsTracks == null || asmsTracks.isEmpty) return;

    final track = asmsTracks.firstWhereOrNull(
          (element) => element.id != null && element.id.toString() == aud.groupId,
        ) ??
        asmsTracks.firstWhereOrNull(
          (element) => element.label != null && element.label == aud.name && element.language == aud.language,
        ) ??
        asmsTracks.firstWhereOrNull(
          (element) => element.language == aud.language,
        ) ??
        asmsTracks.first;

    Logs.player.log("Setting audio track to ${track.label} (${track.language}, id=${track.id})");
    return controller.setAudioTrack(track);
  }

  @override
  void setQuality(QualityStream qs) async {
    final tracks = await _waitForAsms(
      audio: false,
      read: () => controller.betterPlayerAsmsTracks,
    );
    if (tracks == null || tracks.isEmpty) {
      return Logs.player.log("No ASMS video tracks to set '${qs.resolution}' from");
    }
    final height = int.tryParse(qs.resolution.split("x").last);
    final track = tracks.firstWhereOrNull((t) => height != null && t.height == height) ?? tracks.first;
    Logs.player.log("Setting quality to ${track.height}p (requested '${qs.resolution}')");
    return controller.setTrack(track);
  }

}
