// Compatibility layer for the playback code, which still uses the old names.
// Downloads and new code talk to HlsParser directly; both share one parser.
import 'package:animestream/core/commons/hlsParser/hlsMasterPlaylist.dart';
import 'package:animestream/core/commons/hlsParser/hlsParser.dart';

export 'package:animestream/core/commons/hlsParser/audioStream.dart';
export 'package:animestream/core/commons/hlsParser/hlsMasterPlaylist.dart';
export 'package:animestream/core/commons/hlsParser/qualityStream.dart';

typedef ParsedHlsMaster = HlsMasterPlaylist;

Future<HlsMasterPlaylist> parseMasterPlaylist(String url, {Map<String, String>? customHeader}) =>
    HlsParser.parseMasterPlaylist(url, customHeader: customHeader);

Future<bool> isM3u8Playlist(String url, {Map<String, String>? customHeader}) =>
    HlsParser.isM3u8Playlist(url, customHeader: customHeader);
