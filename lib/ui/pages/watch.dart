import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animestream/core/app/ios_pip_service.dart';
import 'package:animestream/ui/models/playerControllers/betterPlayer.dart';
import 'package:animestream/ui/models/widgets/player/mobileControls/bottomControls.dart';

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
