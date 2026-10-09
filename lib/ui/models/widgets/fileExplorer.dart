import 'dart:io';

import 'package:animestream/core/anime/downloader/downloaderHelper.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/data/downloadHistory.dart';
import 'package:animestream/ui/models/snackBar.dart';
import 'package:flutter/material.dart';

class FileExplorer extends StatefulWidget {
  final void Function(String) playVideo;
  const FileExplorer({super.key, required this.playVideo});

  @override
  State<FileExplorer> createState() => _FileExplorerState();
}

class _FileExplorerState extends State<FileExplorer> {
  @override
  void initState() {
    super.initState();
    _initializeRootDirectory();
  }

  Future<void> _initializeRootDirectory() async {
    try {
      final path = await DownloaderHelper().getDownloadsPath();
      final root = Directory(path);
      if (!mounted) return;

      setState(() {
        _rootDir = root.path;
        _currentDir = root;
      });
      await _readDir();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFiles = false;
        _loadError = "Could not open the downloads folder: $error";
      });
    }
  }

  Future<void> _deleteDownload(FileSystemEntity entity, int? id) async {
    if (id != null) await DownloadHistory.removeItem(id);
    if (await entity.exists()) {
      await entity.delete(recursive: true);
    }
  }

  String? _rootDir;
  Directory? _currentDir;
  String? _loadError;
  List<String> _currentDirPathSplit = [];

  String _getFileName(String path) {
    return path.split(Platform.pathSeparator).last;
  }

  void _navBack() {
    final directory = _currentDir;
    if (directory == null || !_canGoBack) return;
    _currentDir = directory.parent;
    _readDir();
  }

  bool get _canGoBack => _rootDir != null && _currentDir != null && _currentDir!.path != _rootDir;

  Future<void> _readDir() async {
    final directory = _currentDir;
    if (directory == null) return;

    setState(() {
      _currentDirPathSplit = directory.path.split(Platform.pathSeparator);
      _loadingFiles = true;
      _loadError = null;
    });

    try {
      final items = await directory.list().toList();
      if (!mounted) return;
      setState(() {
        entities = items;
        _loadingFiles = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        entities = [];
        _loadingFiles = false;
        _loadError = "Could not read this folder: $error";
      });
    }
  }

  List<FileSystemEntity> entities = [];

  bool _loadingFiles = true;

  IconData _getTypeIcon(String ext) {
    return switch (ext) {
      "mp4" => Icons.movie_rounded,
      "webm" => Icons.movie_rounded,
      "mkv" => Icons.movie_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (bool didPop, __) {
        if (didPop) return;
        _navBack();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentDirPathSplit.isNotEmpty) _currentPathAndFile(),
          Expanded(
            child: _loadingFiles
                ? Center(child: CircularProgressIndicator(color: appTheme.textSubColor))
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_loadError!, textAlign: TextAlign.center),
                        ),
                      )
                    : entities.isEmpty
                        ? Center(
                            child: Text(
                              "Empty folder!",
                              style: TextStyle(fontFamily: "NunitoSans"),
                            ),
                          )
                        : ListView.builder(
                            itemCount: entities.length,
                            itemBuilder: (context, index) {
                              final e = entities[index];
                              if (e is Directory) {
                                return _folderTile(e);
                              }
                              return _fileTile(e);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _currentPathAndFile() {
    return Container(
      decoration:
          BoxDecoration(color: appTheme.backgroundSubColor.withAlpha(100), borderRadius: BorderRadius.circular(10)),
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 13),
      margin: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentDirPathSplit.sublist(0, _currentDirPathSplit.length - 1).join('/') + "/",
                    style: TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _currentDirPathSplit.last,
                    style: _titleStyle().copyWith(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          // Spacer(),
          if (_loadingFiles)
            SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: appTheme.textSubColor,
              ),
            )
          else
            Text(
              "${entities.length} items",
              style: TextStyle(fontSize: 12, fontFamily: "NunitoSans", fontWeight: FontWeight.bold),
            )
        ],
      ),
    );
  }

  Container _folderTile(FileSystemEntity entity) {
    return _tappable(
      entity: entity,
      onTap: () {
        _currentDir = Directory(entity.path);
        _readDir();
      },
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.folder_rounded,
              size: 28,
            ),
          ),
          Expanded(
              child: Text(
            _getFileName(entity.path),
            style: _titleStyle(),
            overflow: TextOverflow.ellipsis,
          )),
          InkWell(
              onTapUp: (details) {
                final offset = details.globalPosition;
                showMenu(
                    context: context,
                    color: appTheme.backgroundSubColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    positionBuilder: (context, constraints) {
                      return RelativeRect.fromLTRB(
                        offset.dx,
                        offset.dy,
                        MediaQuery.of(context).size.width - offset.dx,
                        MediaQuery.of(context).size.height - offset.dy,
                      );
                    },
                    items: [
                      PopupMenuItem(
                          onTap: () {
                            _deleteDialog(entity, null).then((val) => _readDir());
                          },
                          child: Text(
                            "Delete",
                            style: TextStyle(fontFamily: "NotoSans", color: appTheme.textMainColor),
                          )),
                    ]);
              },
              child: Icon(Icons.more_vert_rounded))
        ],
      ),
    );
  }

  final _episodeNumRegex = RegExp(r'EP\s+(\d+)', caseSensitive: false);

  final _supportedFiles = ["mp4", "webm", "mkv", "avi", "m4a"];

  Container _fileTile(FileSystemEntity entity) {
    final ep = _episodeNumRegex.firstMatch(entity.path)?.group(1);
    final isSubtitleFile = entity.path.contains(RegExp(r'\.(ass|srt|vtt|txt)$', caseSensitive: false));
    return _tappable(
      entity: entity,
      onTap: () {
        // file should have an extension and be included in supported type! doesnt prevent the user from fw the extension
        final ext = entity.path.split(".").lastOrNull;
        if (ext != null && _supportedFiles.contains(ext)) {
          widget.playVideo(entity.path);
        } else {
          floatingSnackBar("Unsupported file type!");
        }
      },
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16), //12 means symmetrical to folder structure, but feels off here
            child: Icon(
              _getTypeIcon(entity.path.split(".").last),
              size: 28,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ep != null ? "Episode $ep ${isSubtitleFile ? "subtitles" : ""}" : _getFileName(entity.path),
                  style: _titleStyle(),
                  overflow: TextOverflow.ellipsis,
                ),
                if (ep != null)
                  Text(
                    "${_toMegs(File(entity.path).lengthSync())} MB",
                    style: TextStyle(color: appTheme.textSubColor, fontFamily: "NotoSans", fontSize: 13),
                  ),
              ],
            ),
          ),
          IconButton(
              onPressed: () {
                _deleteDialog(entity, null).then((val) => _readDir());
              },
              icon: Icon(Icons.delete)),
        ],
      ),
    );
  }

  Container _tappable({required Widget child, required FileSystemEntity entity, required void Function() onTap}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
      ),
      // decoration: BoxDecoration(
      // borderRadius: BorderRadius.circular(12),
      // ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: child,
        ),
      ),
    );
  }

  Future<T?> _deleteDialog<T>(FileSystemEntity entity, int? id) {
    return showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: Text("You Sure?"),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text("no"),
                ),
                TextButton(
                  onPressed: () async {
                    await _deleteDownload(entity, id);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: appTheme.accentColor,
                    foregroundColor: appTheme.onAccent,
                  ),
                  child: Text("Yes"),
                ),
              ],
              content: Padding(
                padding: const EdgeInsets.all(5),
                child: Text('Are you sure to delete "${_getFileName(entity.path)}" from your device?'),
              ),
            ));
  }

  String _toMegs(int sizeInBytes) => (sizeInBytes / (1024 * 1024)).toStringAsFixed(1);

  TextStyle _titleStyle() => TextStyle(fontFamily: "NunitoSans", fontWeight: FontWeight.bold, fontSize: 18);
}
