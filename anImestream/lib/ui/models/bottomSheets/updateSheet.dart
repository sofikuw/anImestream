import 'dart:async';
import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/app/update.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateSheet extends StatefulWidget {
  final UpdateCheckResult data;
  const UpdateSheet({
    required this.data,
    super.key,
  });

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  http.Client? _downloadClient;
  bool _isUpdating = false;
  bool _cancelled = false;
  Completer<void>? _downloadCompleter;

  final ValueNotifier<double> progress = ValueNotifier(0);

  DownloadState downloadState = DownloadState.idle;

  Future<bool> verifyFileHash(File file, String expectedDigest) async {
    final parts = expectedDigest.trim().toLowerCase().split(':');

    if (parts.length != 2 || parts[0] != 'sha256' || !RegExp(r'^[0-9a-f]{64}$').hasMatch(parts[1])) {
      throw FormatException('Missing or invalid SHA-256 digest');
    }

    final actualDigest = await sha256.bind(file.openRead()).first;
    return actualDigest.toString() == parts[1];
  }

  Future<void> downloadAndInstallUpdate() async {
    if (Platform.isLinux) return;
    if (_isUpdating || !mounted) return;
    _isUpdating = true;
    _cancelled = false;
    progress.value = 0;
    setState(() => downloadState = DownloadState.downloading);

    File? partFile;
    bool installerReady = false;
    String failureMessage = "There was an issue downloading the update.";
    bool isCancelled() => _cancelled || !mounted;

    try {
      final extension = Platform.isWindows ? "exe" : "apk";
      final tempPath = await getTemporaryDirectory();
      if (isCancelled()) return;
      final finalFile = File("${tempPath.path}/animestream_${widget.data.latestVersion}.$extension");
      bool isAlreadyDownloaded = false;
      if (await finalFile.exists()) {
        try {
          isAlreadyDownloaded = await verifyFileHash(finalFile, widget.data.hash);
        } catch (e) {
          Logs.app.log("Hash verification failed for existing file: $e");
        }
      }
      if (isCancelled()) return;

      if (!isAlreadyDownloaded) {
        Logs.app.log("Downloading patch ${widget.data.latestVersion}...");
        final client = http.Client();
        _downloadClient = client;
        try {
          final res = await client.send(http.Request("GET", Uri.parse(widget.data.downloadLink)));
          if (isCancelled()) return;
          if (res.statusCode != HttpStatus.ok) {
            throw HttpException("Update download returned HTTP ${res.statusCode}");
          }

          partFile = File("${tempPath.path}/animestream_${widget.data.latestVersion}.part");
          final buffer = partFile.openWrite();
          final completer = Completer<void>();
          _downloadCompleter = completer;
          Object? transferError;
          void finish([Object? error]) {
            transferError ??= error;
            if (!completer.isCompleted) completer.complete();
          }

          // Observe disk errors immediately, even while waiting for network data.
          final sinkDone = buffer.done.then<void>((_) {}, onError: (Object error) {
            finish(error);
          });
          StreamSubscription<List<int>>? subscription;
          try {
            int downloadedBytes = 0;
            final totalBytes = res.contentLength ?? 0;
            subscription = res.stream.listen((chunk) {
              if (isCancelled() || completer.isCompleted) return;
              try {
                buffer.add(chunk);
                downloadedBytes += chunk.length;
                progress.value = totalBytes <= 0 ? 0 : (downloadedBytes / totalBytes).clamp(0.0, 1.0);
              } catch (e) {
                finish(e);
              }
            }, onError: (Object error) => finish(error), onDone: finish, cancelOnError: true);
            await completer.future;
          } finally {
            _downloadCompleter = null;
            try {
              await subscription?.cancel();
            } catch (e) {
              finish(e);
            }
            try {
              await buffer.flush();
            } catch (e) {
              finish(e);
            } finally {
              try {
                await buffer.close();
              } catch (e) {
                finish(e);
              }
              await sinkDone;
            }
          }
          if (isCancelled()) return;
          if (transferError != null) throw transferError!;
        } finally {
          client.close();
          _downloadClient = null;
        }

        failureMessage = "File verification failed. Please try again.";
        final verified = await verifyFileHash(partFile, widget.data.hash);
        if (isCancelled()) return;
        if (!verified) throw Exception("Update file hash mismatch");

        failureMessage = "Could not save the update installer. Please try again.";
        await partFile.rename(finalFile.path);
        partFile = null;
        if (isCancelled()) return;
      }

      installerReady = true;
      progress.value = 1;
      setState(() => downloadState = DownloadState.completed);

      // Cache cleanup must not prevent opening a verified installer.
      try {
        final version = (await PackageInfo.fromPlatform()).version;
        if (isCancelled()) return;
        for (final oldVersion in {version, 'v$version'}) {
          final oldFile = File("${tempPath.path}/animestream_$oldVersion.$extension");
          if (oldFile.path != finalFile.path && await oldFile.exists()) {
            await oldFile.delete();
          }
        }
      } catch (e) {
        Logs.app.log("Could not remove the previous update installer: $e");
      }

      if (isCancelled()) return;
      failureMessage = "Could not open the update installer. Please try again.";
      var openRes = await OpenFile.open(finalFile.path);
      if (isCancelled()) return;
      if (Platform.isAndroid && openRes.type == ResultType.permissionDenied) {
        final status = await Permission.requestInstallPackages.request();
        if (isCancelled()) return;
        if (status.isGranted) {
          openRes = await OpenFile.open(finalFile.path);
          if (isCancelled()) return;
        }
      }
      if (openRes.type == ResultType.done) {
        Logs.app.log("Update dialog invoked successfully.");
      } else {
        Logs.app.log("Could not open update installer: ${openRes.type}: ${openRes.message}");
        floatingSnackBar(openRes.type == ResultType.permissionDenied
            ? "Allow installation from this app, then tap Install again."
            : failureMessage);
      }
    } catch (e) {
      if (!isCancelled()) {
        Logs.app.log("Update failed: $e");
        floatingSnackBar(failureMessage);
      }
    } finally {
      // Only partial downloads are removed; verified installers remain reusable.
      try {
        if (partFile != null && await partFile.exists()) await partFile.delete();
      } catch (e) {
        Logs.app.log("Could not remove partial update download: $e");
      }
      _isUpdating = false;
      if (!isCancelled() && !installerReady) {
        progress.value = 0;
        setState(() => downloadState = DownloadState.idle);
      }
    }
  }

  void _cancelDownload() {
    _cancelled = true;
    final completer = _downloadCompleter;
    if (completer != null && !completer.isCompleted) completer.complete();
    _downloadClient?.close();
  }

  @override
  void dispose() {
    _cancelDownload();
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom, left: 15, right: 15, top: 10),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Update Available",
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),

                      // Padding(
                      // padding: const EdgeInsets.only(left: 14, bottom: 12),
                      // child:
                      Row(
                        // mainAxisAlignment: ,
                        children: [
                          Text(
                            widget.data.latestVersion,
                            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                          ),
                          Container(
                              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                              margin: EdgeInsets.only(left: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(100),
                                color: appTheme.accentColor,
                              ),
                              child: Text(
                                widget.data.preRelease ? "beta" : "stable",
                                style: TextStyle(
                                  color: appTheme.onAccent,
                                  fontSize: 15,
                                  fontFamily: "NunitoSans",
                                ),
                              )),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () async {
                      await launchUrl(
                        Uri.parse("https://github.com/sofikuw/anImestream/releases/latest"),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: Icon(
                      Icons.launch_rounded,
                      size: 28,
                    ),
                    tooltip: "Open In Browser",
                  ),
                ],
              ),
            ),
            Container(
              height: 400,
              decoration: BoxDecoration(color: appTheme.backgroundSubColor, borderRadius: BorderRadius.circular(25)),
              padding: EdgeInsets.all(14),
              child: ListView(
                shrinkWrap: true,
                children: [
                  MarkdownBody(
                    data: widget.data.description,
                    styleSheet: MarkdownStyleSheet(
                      h1: style(bold: true),
                      h2: style(bold: true),
                      listBullet: style(),
                      h3: style(),
                      h4: style(),
                      h5: style(),
                      h6: style(),
                      p: style(),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              margin: EdgeInsets.only(top: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: ValueListenableBuilder(
                        valueListenable: progress,
                        builder: (ctx, val, child) {
                          return LiquidDownloadButton(
                            state: downloadState,
                            progress: val,
                            onPressed: () {
                              // if the update is downloaded and state is install, it automatically opens
                              // the available update file
                              if (downloadState != DownloadState.downloading) {
                                unawaited(downloadAndInstallUpdate());
                              }
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: IconButton.outlined(
                      onPressed: () {
                        _cancelDownload();
                        Navigator.pop(context);
                      },
                      color: appTheme.accentColor,
                      style: IconButton.styleFrom(
                        side: BorderSide(color: appTheme.accentColor),
                        fixedSize: Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      icon: Icon(Icons.close),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle style({bool bold = false}) {
    return TextStyle(
      color: appTheme.textMainColor,
      fontFamily: "NotoSans",
      fontWeight: bold ? FontWeight.bold : null,
    );
  }
}

enum DownloadState { idle, downloading, completed }

class LiquidDownloadButton extends StatelessWidget {
  final DownloadState state;
  final double progress; // 0.0 to 1.0
  final VoidCallback onPressed;

  const LiquidDownloadButton({
    super.key,
    required this.state,
    required this.progress,
    required this.onPressed,
  }) : assert(progress >= 0 && progress <= 1, "Progress value must be between 0.0 and 1.0!");

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 50,
          width: double.infinity,
          color: state == DownloadState.idle ? appTheme.accentColor : appTheme.backgroundSubColor,
          child: Stack(
            children: [
              if (state != DownloadState.idle)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: constraints.maxWidth * progress,
                      height: constraints.maxHeight,
                      color: appTheme.accentColor,
                    );
                  },
                ),
              Center(
                child: Text(
                  _getButtonText(),
                  style: TextStyle(
                    color: appTheme.onAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    switch (state) {
      case DownloadState.idle:
        return "Download";
      case DownloadState.downloading:
        return "Downloading... ${progress == 0 ? "" : "${(progress * 100).toInt()}%"}";
      case DownloadState.completed:
        return "Install";
    }
  }
}
