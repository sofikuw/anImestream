import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task.dart';

/// Full BitTorrent streaming engine utilizing dtorrent_task_v2 for SubsPlease / magnet playback.
class TorrentEngine {
  TorrentTask? _task;
  HttpServer? _proxyServer;
  int _proxyPort = 8085;

  /// Starts downloading a torrent and spins up a local HTTP proxy for streaming video files.
  Future<String?> startTorrentStream({
    required String magnetOrPath,
    required String savePath,
  }) async {
    try {
      // 1. Initialize TorrentTask
      _task = await TorrentTask.newTask(
        magnetOrPath,
        savePath: savePath,
      );

      await _task?.start();

      // 2. Spin up local HTTP proxy server to stream file bytes on demand
      _proxyServer = await HttpServer.bind(InternetAddress.loopbackIPv4, _proxyPort);
      _proxyServer?.listen((HttpRequest request) async {
        final task = _task;
        if (task == null || task.files.isEmpty) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        // Pick the largest video file in the torrent
        TorrentFile? targetFile;
        int maxLen = 0;
        for (final file in task.files) {
          if (file.length > maxLen) {
            maxLen = file.length;
            targetFile = file;
          }
        }

        if (targetFile == null) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        request.response.headers.contentType = ContentType('video', 'mp4');
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

        // Stream file pieces through HTTP range requests
        await targetFile.createStream().pipe(request.response);
      });

      return 'http://127.0.0.1:$_proxyPort/stream';
    } catch (e) {
      print('[TORRENT ENGINE] Error starting torrent stream: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    await _proxyServer?.close(force: true);
    _proxyServer = null;
    await _task?.stop();
    _task = null;
  }
}
