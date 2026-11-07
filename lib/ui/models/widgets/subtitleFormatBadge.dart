import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:flutter/material.dart';

/// Small pill that shows a subtitle's format ("SRT", "VTT", "ASS").
/// Renders nothing when the format is unknown.
class SubtitleFormatBadge extends StatelessWidget {
  final String? format;

  const SubtitleFormatBadge({super.key, required this.format});

  @override
  Widget build(BuildContext context) {
    final label = format;
    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: appTheme.accentColor.withAlpha(24),
        border: Border.all(color: appTheme.accentColor.withAlpha(70)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: appTheme.accentColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
