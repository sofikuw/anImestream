import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/app/ios_pip_service.dart';
import 'package:animestream/ui/models/playerControllers/videoController.dart';
import 'package:animestream/ui/models/playerControllers/betterPlayer.dart';
import 'package:animestream/ui/models/providers/playerDataProvider.dart';
import 'package:animestream/ui/models/providers/playerProvider.dart';
import 'package:animestream/ui/models/widgets/player/controls.dart';
import 'package:animestream/ui/models/widgets/player/mobileControls/bottomControls.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class WatchPage extends StatefulWidget {
  final String animeTitle;
  final String episodeNumber;
  final String videoUrl;

  const WatchPage({
    super.key,
    required this.animeTitle,
    required this.episodeNumber,
    required this.videoUrl,
  });

  @override
  State<WatchPage> createState() => _WatchPageState();
}

class _WatchPageState extends State<WatchPage> with WidgetsBindingObserver {
  late BetterPlayerControllerWrapper _playerWrapper;
  final IosPipService _pipService = IosPipService();
  bool _isPlaying = true;
  bool _isFullscreen = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(minutes: 24);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _playerWrapper = BetterPlayerControllerWrapper();
    _playerWrapper.initialize(
      url: widget.videoUrl,
      autoPlay: true,
      aspectRatio: 16 / 9,
    );

    // Ensure YouTube-style swipe-to-home PiP is enabled on iOS
    if (Platform.isIOS) {
      _pipService.setAutoPipEnabled(true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // On iOS, if video is playing when user swipes up to home or switches apps,
    // ensure Picture-in-Picture stays active like YouTube!
    if (Platform.isIOS && _isPlaying) {
      if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
        if (!_pipService.isPipActive) {
          _pipService.startPictureInPicture();
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerWrapper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _pipService.isPipActiveNotifier,
      builder: (context, isInPip, child) {
        // When active in PiP mode, iOS renders the floating window over other apps
        if (isInPip) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Playing in Picture-in-Picture',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          );
        }

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: _isFullscreen
              ? null
              : AppBar(
                  backgroundColor: Colors.black,
                  title: Text('${widget.animeTitle} - Ep ${widget.episodeNumber}'),
                  actions: [
                    IconButton(
                      tooltip: 'Picture in Picture',
                      icon: const Icon(Icons.picture_in_picture_alt_rounded),
                      onPressed: () => _playerWrapper.enterPictureInPicture(),
                    ),
                  ],
                ),
          body: SafeArea(
            child: Column(
              children: [
                // Video Player Area
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        color: Colors.black87,
                        child: const Center(
                          child: Icon(Icons.movie_rounded, color: Colors.white30, size: 48),
                        ),
                      ),
                      BottomControlsWithPip(
                        isPlaying: _isPlaying,
                        currentPosition: _position,
                        totalDuration: _duration,
                        isFullscreen: _isFullscreen,
                        onPlayPause: () => setState(() => _isPlaying = !_isPlaying),
                        onSeek: (value) => setState(() => _position = Duration(milliseconds: value.toInt())),
                        onToggleFullscreen: () => setState(() => _isFullscreen = !_isFullscreen),
                        onTogglePip: () => _playerWrapper.enterPictureInPicture(),
                      ),
                    ],
                  ),
                ),
                if (!_isFullscreen) ...[
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.animeTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 18),
                          label: const Text('Watch in PiP'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                          onPressed: () => _playerWrapper.enterPictureInPicture(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The app's streaming/download flow passes a VideoController and provider
/// state to Watch. Keep this contract alongside the standalone WatchPage.
class Watch extends StatefulWidget {
  final VideoController controller;
  final bool localSource;

  const Watch({
    super.key,
    required this.controller,
    this.localSource = false,
  });

  @override
  State<Watch> createState() => _WatchState();
}

class _WatchState extends State<Watch> {
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final dataProvider = context.read<PlayerDataProvider>();
    dataProvider.initSubsettings();
    try {
      final stream = dataProvider.state.currentStream;
      if (widget.localSource) {
        await widget.controller.initiateVideo(stream.url, offline: true);
      } else {
        await dataProvider.extractCurrentStreamQualities();
        final quality = dataProvider.getPreferredQualityStreamFromQualities();
        dataProvider.updateCurrentQuality(quality);
        await widget.controller.initiateVideo(
          quality.url,
          headers: stream.customHeaders,
        );
        widget.controller.setQuality(quality);
      }

      final duration = widget.controller.duration ?? 0;
      final resumePercent = (dataProvider.lastWatchDuration ?? 0).clamp(0, 100);
      if (duration > 0 && resumePercent > 0) {
        await widget.controller.seekTo(
          Duration(milliseconds: (duration * resumePercent / 100).round()),
        );
      }
      widget.controller.addListener(_updatePlaybackState);
      if (!mounted) return;
      context.read<PlayerProvider>().toggleControlsVisibility(action: true);
      setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _updatePlaybackState() {
    if (!mounted) return;
    final duration = widget.controller.duration ?? 0;
    final position = widget.controller.position ?? 0;
    final dataProvider = context.read<PlayerDataProvider>();
    dataProvider.update(dataProvider.state.copyWith(
      currentTimeStamp: _formatTime(position),
      maxTimeStamp: _formatTime(duration),
      sliderValue: position ~/ 1000,
    ));
    context.read<PlayerProvider>().updatePlayState(
          widget.controller.isBuffering == true
              ? PlayerState.buffering
              : widget.controller.isPlaying == true
                  ? PlayerState.playing
                  : PlayerState.paused,
        );
  }

  String _formatTime(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updatePlaybackState);
    widget.controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: widget.controller.getWidget()),
          if (_ready) const Controls(),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to start playback:\n$_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          if (!_ready && _error == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
