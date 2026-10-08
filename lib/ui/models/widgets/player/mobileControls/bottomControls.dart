import 'package:animestream/ui/models/providers/playerProvider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BottomControls extends StatelessWidget {
  const BottomControls({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlayerProvider>();
    final position = Duration(milliseconds: provider.controller.position ?? 0);
    final duration = Duration(milliseconds: provider.controller.duration ?? 0);
    final max = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

    return Row(
      children: [
        IconButton(
          icon: Icon(
            provider.controller.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
          ),
          onPressed: () => provider.controller.isPlaying == true
              ? provider.controller.pause()
              : provider.controller.play(),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: duration.inMilliseconds > 0
                ? (v) => provider.controller.seekTo(Duration(milliseconds: v.toInt()))
                : null,
          ),
        ),
        IconButton(
          tooltip: 'Picture in Picture',
          icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white),
          onPressed: () => provider.setPip(true),
        ),
      ],
    );
  }
}
