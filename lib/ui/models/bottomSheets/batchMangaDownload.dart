import 'package:flutter/material.dart';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/manga/mangaDownloader.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/ui/models/snackBar.dart';

/// Chapter picker for manga batch downloads, mirroring the anime episode
/// grid: select chapters, then queue them through MangaDownloader.
class BatchMangaDownloadSheet extends StatefulWidget {
  final String mangaId;
  final String mangaTitle;
  final List<MangaChapter> chapters;
  final Set<String> downloaded;
  final MangaChapterProvider provider;
  final Future<void> Function() onFinished;

  const BatchMangaDownloadSheet({
    super.key,
    required this.mangaId,
    required this.mangaTitle,
    required this.chapters,
    required this.downloaded,
    required this.provider,
    required this.onFinished,
  });

  @override
  State<BatchMangaDownloadSheet> createState() => _BatchMangaDownloadSheetState();
}

class _BatchMangaDownloadSheetState extends State<BatchMangaDownloadSheet> {
  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {
      for (var i = 0; i < widget.chapters.length; i++)
        if (!widget.downloaded.contains(widget.chapters[i].id)) i,
    };
  }

  void _selectAll() => setState(() {
        _selected = _selected.length == widget.chapters.length
            ? <int>{}
            : {for (var i = 0; i < widget.chapters.length; i++) i};
      });

  void _selectUndownloaded() => setState(() {
        _selected = {
          for (var i = 0; i < widget.chapters.length; i++)
            if (!widget.downloaded.contains(widget.chapters[i].id)) i,
        };
      });

  void _invert() => setState(() {
        _selected = {
          for (var i = 0; i < widget.chapters.length; i++)
            if (!_selected.contains(i)) i,
        };
      });

  Future<void> _start() async {
    final indices = _selected.toList()..sort();
    Navigator.pop(context);

    var ok = 0;
    var failed = 0;
    for (final index in indices) {
      final chapter = widget.chapters[index];
      if (await MangaDownloader.download(
        mangaId: widget.mangaId,
        mangaTitle: widget.mangaTitle,
        chapter: chapter,
        provider: widget.provider,
      )) {
        ok++;
      } else {
        failed++;
      }
    }
    await widget.onFinished();
    floatingSnackBar('Downloaded $ok chapters${failed == 0 ? '' : ', $failed failed'}');
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.chapters.length;
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Batch Download",
            style: TextStyle(
              color: appTheme.textMainColor,
              fontFamily: "Rubik",
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "${_selected.length}/$total chapters selected",
            style: TextStyle(color: appTheme.textSubColor, fontFamily: "Rubik", fontSize: 13),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ActionChip(
                  label: Text(
                    _selected.length == total ? "Clear All" : "Select All",
                    style: TextStyle(fontFamily: "Rubik", fontSize: 12, color: appTheme.textMainColor),
                  ),
                  backgroundColor: appTheme.backgroundSubColor,
                  onPressed: _selectAll,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(
                    "Not downloaded",
                    style: TextStyle(fontFamily: "Rubik", fontSize: 12, color: appTheme.textMainColor),
                  ),
                  backgroundColor: appTheme.backgroundSubColor,
                  onPressed: _selectUndownloaded,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(
                    "Invert",
                    style: TextStyle(fontFamily: "Rubik", fontSize: 12, color: appTheme.textMainColor),
                  ),
                  backgroundColor: appTheme.backgroundSubColor,
                  onPressed: _invert,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.45),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: total,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.35,
              ),
              itemBuilder: (context, index) {
                final selected = _selected.contains(index);
                final isDownloaded = widget.downloaded.contains(widget.chapters[index].id);
                return Material(
                  color: selected ? appTheme.accentColor : appTheme.backgroundSubColor,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      selected ? _selected.remove(index) : _selected.add(index);
                    }),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          widget.chapters[index].number != null
                              ? MangaChapter.formatNumber(widget.chapters[index].number!)
                              : '${index + 1}',
                          style: TextStyle(
                            fontFamily: "Rubik",
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: selected ? appTheme.onAccent : appTheme.textMainColor,
                          ),
                        ),
                        if (isDownloaded)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: selected ? appTheme.onAccent.withAlpha(180) : appTheme.textSubColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _selected.isEmpty ? null : _start,
              icon: const Icon(Icons.download_rounded, size: 20),
              label: Text(
                "Download ${_selected.length} chapters",
                style: const TextStyle(fontFamily: "Rubik", fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: appTheme.accentColor,
                foregroundColor: appTheme.onAccent,
                disabledBackgroundColor: appTheme.backgroundSubColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
