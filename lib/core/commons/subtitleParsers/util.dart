import 'package:animestream/ui/models/widgets/subtitles/subtitle.dart';

class SubtitleParserUtil {

  /// Returns a short label ("SRT", "VTT", "ASS") for a subtitle, or null when
  /// the format is absent or unknown.
  static String? formatLabel(String? format, String? url) {
    final declared = _normalizeFormat(format);
    if (declared != null) return declared;
    return _formatFromUrl(url);
  }

  static String? _normalizeFormat(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (value.contains('ass') || value.contains('ssa')) return 'ASS';
    if (value.contains('vtt')) return 'VTT';
    if (value.contains('srt') || value.contains('subrip')) return 'SRT';
    return null;
  }

  static String? _formatFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return _normalizeFormat(path.substring(dot + 1));
  }

   static SubtitleAlignment getAlignmentFromNumber(int number) {
    return switch (number) {
      1 => SubtitleAlignment.bottomLeft,
      2 => SubtitleAlignment.bottomCenter,
      3 => SubtitleAlignment.bottomRight,
      4 => SubtitleAlignment.centerLeft,
      5 => SubtitleAlignment.center,
      6 => SubtitleAlignment.centerRight,
      7 => SubtitleAlignment.topLeft,
      8 => SubtitleAlignment.topCenter,
      9 => SubtitleAlignment.topRight,
      _ => throw Exception("Unknown position for sub")
    };
  }
}