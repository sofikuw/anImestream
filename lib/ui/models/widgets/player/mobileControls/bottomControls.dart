import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animestream/core/app/ios_pip_service.dart';

class BottomControlsWithPip extends StatelessWidget {
  final VoidCallback onPlayPause;
  final bool isPlaying;
  final Duration currentPosition;
  final Duration totalDuration;
  final ValueChanged<double> onSeek;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;
  final VoidCallback? onTogglePip;

  const BottomControlsWithPip({
    super.key,
    required this.onPlayPause,
    required this.isPlaying,
    required this.currentPosition,
    required this.totalDuration,
    required this.onSeek,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    this.onTogglePip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Timeline Slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: Colors.white24,
              thumbColor: Theme.of(context).primaryColor,
            ),
            child: Slider(
              value: currentPosition.inMilliseconds.toDouble().clamp(
                    0.0,
                    totalDuration.inMilliseconds.toDouble().clamp(0.0, double.infinity),
                  ),
              min: 0.0,
              max: totalDuration.inMilliseconds > 0
                  ? totalDuration.inMilliseconds.toDouble()
                  : 1.0,
              onChanged: onSeek,
            ),
          ),

          // Control Buttons Row
          Row(
            children: [
              IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: onPlayPause,
              ),
              const SizedBox(width: 8),
              Text(
                '${_formatDuration(currentPosition)} / ${_formatDuration(totalDuration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Rubik',
                ),
              ),
              const Spacer(),

              // YouTube-style iOS PiP Button
              if (Platform.isIOS || Platform.isAndroid)
                IconButton(
                  tooltip: 'Picture in Picture',
                  icon: const Icon(
                    Icons.picture_in_picture_alt_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: onTogglePip ??
                      () async {
                        await IosPipService().startPictureInPicture();
                      },
                ),

              // Fullscreen Toggle Button
              IconButton(
                tooltip: isFullscreen ? 'Exit Fullscreen' : 'Fullscreen',
                icon: Icon(
                  isFullscreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: onToggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
