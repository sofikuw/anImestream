import 'dart:io';
import 'dart:math';

import 'package:animestream/core/commons/utils.dart';
import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';

Future<BetterPlayerDataSource> dataSourceConfig(String url, {Map<String, String>? headers = null}) async {
  return BetterPlayerDataSource(
    BetterPlayerDataSourceType.network,
    url,
    videoFormat: await _getFormat(url, headers),
    useAsmsAudioTracks: true,
    useAsmsTracks: true,
    bufferingConfiguration: BetterPlayerBufferingConfiguration(
      maxBufferMs: 120000,
    ),
    cacheConfiguration: BetterPlayerCacheConfiguration(
      // The iOS HLS cache proxy drops source request headers. Let AVPlayer
      // request iOS streams directly so Referer/auth headers keep working.
      useCache: !Platform.isIOS,
      maxCacheFileSize: 50 * 1024 * 1024,
      maxCacheSize: 50 * 1024 * 1024,
    ),
    headers: headers,
    placeholder: PlayerLoadingWidget(),
  );
}

Future<BetterPlayerVideoFormat> _getFormat(String url, Map<String, String>? headers) async {
  // Use the URL when it is explicit. Some stream hosts reject or stall on HEAD
  // requests, so don't make normal HLS/DASH playback wait for MIME detection.
  final urlPath = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase().split('?').first;
  if (urlPath.endsWith(".m3u8") || urlPath.endsWith(".m3u")) {
    return BetterPlayerVideoFormat.hls;
  }
  if (urlPath.endsWith(".mpd") || urlPath.endsWith(".dash")) {
    return BetterPlayerVideoFormat.dash;
  }

  // For extensionless URLs, MIME detection is best-effort and must not block
  // starting the player when a CDN does not support HEAD.
  try {
    final mime = (await getMediaMimeType(url, headers).timeout(const Duration(seconds: 2)))?.toLowerCase();
    if (mime != null && (mime.contains("mpegurl") || mime.contains("mp2t"))) {
      return BetterPlayerVideoFormat.hls;
    }
    if (mime != null && mime.contains("dash")) {
      return BetterPlayerVideoFormat.dash;
    }
  } catch (_) {
    // Let the native player infer the format from the response.
  }

  return BetterPlayerVideoFormat.other;
}

class PlayerLoadingWidget extends StatelessWidget {
  const PlayerLoadingWidget({
    super.key,
  });

  // Why not have some fun :)
  final messages = const [
    "Loading Your Anime...",
    "Tweaking the pixels...",
    "Setting up the fun...",
    "Tried Oreshura? Loading anyway...",
    "Just a moment, Senpai...",
    ":)",
    "Cooking up the playback...",
    "Hold on! Will Ya?",
    "Aligning the frames...",
    "anime...stream...ing...",
  ];

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              height: 200,
              width: 200,
              child: Image.asset(
                "lib/assets/icons/logo_foreground.png",
                opacity: AlwaysStoppedAnimation(0.6),
              )),
          Text(
            messages[Random().nextInt(messages.length)],
            style: TextStyle(color: Colors.grey, fontFamily: "Rubik", fontWeight: FontWeight.bold),
          )
        ],
      ),
    );
  }
}

/**Format seconds to hour:min:sec format */
String getFormattedTime(int timeInSeconds) {
  String formatTime(int val) {
    return val.toString().padLeft(2, '0');
  }

  int hours = timeInSeconds ~/ 3600;
  int minutes = (timeInSeconds % 3600) ~/ 60;
  int seconds = timeInSeconds % 60;

  String formattedHours = hours == 0 ? '' : formatTime(hours);
  String formattedMins = formatTime(minutes);
  String formattedSeconds = formatTime(seconds);

  return "${formattedHours.length > 0 ? "$formattedHours:" : ''}$formattedMins:$formattedSeconds";
}
