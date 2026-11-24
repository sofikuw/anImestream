import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:animestream/core/anime/downloader/downloaders/baseDownloader.dart';
import 'package:animestream/core/anime/downloader/types.dart';
import 'package:http/http.dart';

class VideoDownloader extends BaseDownloader {
  VideoDownloader(DownloadTaskIsolate task) : super(task);

  late IOSink sink;

  /// Ask for one byte to find the real total size. Unlike a HEAD probe this
  /// works on CDNs that only advertise ranges on GET.
  Future<int?> _probeTotalSize() async {
    try {
      final req = Request('GET', Uri.parse(task.url));
      req.headers.addAll(task.customHeaders);
      req.headers['Range'] = 'bytes=0-0';
      final res = await req.send().timeout(const Duration(seconds: 15));
      await res.stream.drain<List<int>>();
      if (res.statusCode == 206) {
        final range = res.headers['content-range'];
        if (range != null && range.contains('/')) return int.tryParse(range.split('/').last);
      }
    } catch (_) {}
    return null;
  }

  /// IDM-style download: eight byte ranges written into the same file at once.
  Future<void> _downloadChunked(String filepath, int total) async {
    const chunks = 8;
    final file = File(filepath);
    final raf = await file.open(mode: FileMode.write);
    await raf.truncate(total);
    final client = Client();
    final chunkSize = (total / chunks).ceil();
    final subscriptions = <StreamSubscription<List<int>>>[];
    final written = List<int>.filled(chunks, 0);
    int totalWritten = 0;
    int lastProgress = 0;

    // RandomAccessFile has one shared cursor, so seek+write must not overlap.
    Future<void> writeChain = Future.value();
    Future<void> writeAt(List<int> data, int offset) {
      final next = writeChain.then((_) async {
        await raf.seek(offset);
        await raf.writeFrom(data);
      });
      writeChain = next.catchError((_) {});
      return next;
    }

    Future<void> abort() async {
      for (final subscription in subscriptions) {
        try {
          await subscription.cancel();
        } catch (_) {}
      }
      try {
        await raf.close();
      } catch (_) {}
      try {
        client.close();
      } catch (_) {}
      if (await file.exists()) await file.delete();
    }

    final workers = <Future<void>>[];
    for (var i = 0; i < chunks; i++) {
      final start = i * chunkSize;
      if (start >= total) break;
      final end = min(start + chunkSize, total) - 1;
      workers.add(() async {
        final req = Request('GET', Uri.parse(task.url));
        req.headers.addAll(task.customHeaders);
        req.headers['Range'] = 'bytes=$start-$end';
        final res = await client.send(req);
        if (res.statusCode != 206) {
          throw Exception('Server refused byte range for chunk $i (${res.statusCode})');
        }
        final done = Completer<void>();
        StreamSubscription<List<int>>? subscription;
        subscription = res.stream.listen(
          (data) async {
            subscription!.pause();
            if (status == DownloadStatus.cancelled) {
              await abort();
              setCancelledStatus();
              if (!done.isCompleted) done.complete();
              return;
            }
            if (status == DownloadStatus.paused) {
              await waitForResume();
              if (status == DownloadStatus.cancelled) {
                await abort();
                setCancelledStatus();
                if (!done.isCompleted) done.complete();
                return;
              }
            }
            try {
              await writeAt(data, start + written[i]);
            } catch (_) {
              // A cancelled worker may have closed the file already.
            }
            written[i] += data.length;
            totalWritten += data.length;
            final progress = (totalWritten / total * 100).toInt();
            if (progress - lastProgress >= 2) {
              updateProgress(progress, filepath);
              lastProgress = progress;
            }
            subscription!.resume();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          onError: (err) {
            if (!done.isCompleted) done.completeError(err);
          },
          cancelOnError: true,
        );
        subscriptions.add(subscription);
        await done.future;
      }());
    }

    try {
      await Future.wait(workers);
      if (status == DownloadStatus.cancelled) return;
      await raf.close();
      client.close();
      setCompletedStatus(filepath, silent: false);
    } catch (err) {
      await abort();
      setFailedStatus(err.toString());
    }
  }

  @override
  Future<void> download() async {
    await setUpPorts(task);

    // Guess/Extract extension from link, otherwise give null and download as an mp4
    String? extensionGuess = helper.extractExtension(task.url);
    extensionGuess = ['mp4', 'mkv', 'avi', 'webm', 'flv'].contains(extensionGuess) ? extensionGuess : null;

    final filepath = await helper.makeDirectory(
      fileName: task.fileName,
      fileExtension: extensionGuess,
      downloadPath: task.downloadPath,
    );

    // Fresh downloads use eight parallel byte ranges when the server allows
    // it. Resume keeps the old single-stream path so its byte offset semantics
    // stay intact.
    if (task.resumeFrom == 0) {
      final total = await _probeTotalSize();
      if (total != null && total > 0) {
        await _downloadChunked(filepath, total);
        return;
      }
    }

    //we considering the file as mp4
    final req = Request("GET", Uri.parse(task.url));
    // add the headers
    req.headers.addAll(task.customHeaders);
    if (task.resumeFrom != 0) {
      final doesServerSupportRangeHeader = await helper.checkRangeSupport(Uri.parse(task.url));
      if (doesServerSupportRangeHeader) {
        req.headers.addAll({'Range': 'bytes=${task.resumeFrom}-'});
      } else {
        print("Server doesnt support ranges. Retrying download...");
        // start the download again
        task.sendPort?.send(DownloadMessage(status: 'retry', id: task.id));
        return;
      }
    }

    final file = File(filepath);

    sink = file.openWrite(mode: task.resumeFrom == 0 ? FileMode.write : FileMode.append);

    // just to catch any OS errors like file access
    try {
      final res = await req.send();
      if (!(res.statusCode >= 200 && res.statusCode < 300)) {
        throw Exception("Received response with status code ${res.statusCode}");
      }
      final totalSize = res.contentLength ?? -1;
      int downloadedBytes = task.resumeFrom;
      int lastProgress = 0;
      int lastPrintedProgress = 0; // to reduce console logs.

      StreamSubscription<List<int>>? subscription;

      final completer = Completer<void>();

      subscription = res.stream.listen(
          (chunk) async {
            // First, check if download is cancelled. if yes, flush the stuff
            if (status == DownloadStatus.cancelled) {
              await subscription?.cancel();
              await sink.close();
              file.deleteSync();

              completer.complete();

              setCancelledStatus();
              return;
            }
            // Write the data since its already fetched!
            sink.add(chunk);
            downloadedBytes += chunk.length;

            final progress = (downloadedBytes / totalSize * 100).toInt();

            // on pause command
            if (status == DownloadStatus.paused) {
              subscription?.pause();

              setPausedStatus(progress, downloadedBytes, filepath);

              super.completer = Completer();
              try {
                timer = Timer(Duration(minutes: 1), () => super.completer?.completeError(Exception("Timeout!")));
                await super.completer!.future;
                subscription?.resume();
                super.completer = null;
                timer?.cancel();
                timer = null;
              } catch (err) {
                print("Isolate Timeout! Error: ${err.toString()}");
                print("Self destructing isolate...");
                super.completer = null;
                timer?.cancel();
                timer = null;
                subscription?.cancel();
                task.sendPort?.send(DownloadMessage(status: 'isolate_timeout', id: task.id));
              }
            }

            // Only send progress every 2% to reduce isolate-to-main thread overhead
            if (progress > lastProgress && progress - lastProgress >= 2) {
              // just to reduce the logging from 100 to 10
              if (progress >= lastPrintedProgress) {
                print("[DOWNLOADER]<${task.id}> Progress: ${progress}%");
                lastPrintedProgress += 10;
              }
              updateProgress(progress, filepath);
              lastProgress = progress;
            }
          },
          onDone: () async {
            await sink.close();
            print("[DOWNLOADER] succesfully written the file to disk");
            completer.complete();
            return setCompletedStatus(filepath, silent: false);
          },
          onError: (err) async {
            print(err);
            print("From media url: ${task.url}");
            completer.completeError(err);
            await sink.close();
            await file.delete();
            return setFailedStatus(err.toString());
          });

      return await completer.future;
    } catch (err) {
      // same stuff as on error
      print(err);
      print("From media url: ${task.url}");
      await sink.close();
      await file.delete();
      setFailedStatus(err.toString());
    }
  }

  @override
  Future<void> onCancel() async {
    // The chunked path has no IOSink.
    try {
      await sink.close();
    } catch (_) {}
  }
}
