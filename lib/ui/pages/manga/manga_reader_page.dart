import 'package:flutter/material.dart';
import '../../../core/extensions/models/manga_models.dart';
import '../../../core/manga/providers/manga_provider.dart';

enum ReadingMode {
  verticalContinuous,
  horizontalLtr,
  horizontalRtl,
}

class MangaReaderPage extends StatefulWidget {
  final String mangaTitle;
  final MangaChapter chapter;
  final List<MangaChapter> chapters;
  final MangaProvider provider;

  const MangaReaderPage({
    super.key,
    required this.mangaTitle,
    required this.chapter,
    required this.chapters,
    required this.provider,
  });

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  late MangaChapter _currentChapter;
  List<MangaPage> _pages = [];
  bool _isLoading = true;
  String? _error;
  int _currentPageIndex = 0;
  bool _showOverlays = true;
  ReadingMode _readingMode = ReadingMode.verticalContinuous;

  final PageController _pageController = PageController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentChapter = widget.chapter;
    _loadPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPages() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _currentPageIndex = 0;
    });

    try {
      final pages = await widget.provider.getChapterPages(_currentChapter.id);
      if (mounted) {
        setState(() {
          _pages = pages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load chapter pages: $e';
        });
      }
    }
  }

  void _goToPreviousChapter() {
    final idx = widget.chapters.indexWhere((c) => c.id == _currentChapter.id);
    if (idx > 0) {
      setState(() {
        _currentChapter = widget.chapters[idx - 1];
      });
      _loadPages();
    }
  }

  void _goToNextChapter() {
    final idx = widget.chapters.indexWhere((c) => c.id == _currentChapter.id);
    if (idx < widget.chapters.length - 1) {
      setState(() {
        _currentChapter = widget.chapters[idx + 1];
      });
      _loadPages();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main Reader Content Area
          GestureDetector(
            onTap: () => setState(() => _showOverlays = !_showOverlays),
            child: _buildReaderContent(),
          ),

          // Top App Bar Overlay
          if (_showOverlays)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top, bottom: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.mangaTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _currentChapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: _showSettingsSheet,
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Control Bar Overlay
          if (_showOverlays)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, top: 8, left: 16, right: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.9)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Page Progress Slider
                    if (_pages.isNotEmpty)
                      Row(
                        children: [
                          Text(
                            '${_currentPageIndex + 1}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          Expanded(
                            child: Slider(
                              value: _currentPageIndex.toDouble(),
                              min: 0,
                              max: (_pages.length - 1).toDouble().clamp(0.0, 999.0),
                              activeColor: const Color(0xFFF43F5E),
                              inactiveColor: Colors.white24,
                              onChanged: (val) {
                                final target = val.toInt();
                                setState(() => _currentPageIndex = target);
                                if (_readingMode == ReadingMode.verticalContinuous) {
                                  _scrollController.animateTo(
                                    target * 600.0,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  _pageController.jumpToPage(target);
                                }
                              },
                            ),
                          ),
                          Text(
                            '${_pages.length}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    // Chapter Nav Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton.icon(
                          onPressed: _goToPreviousChapter,
                          icon: const Icon(Icons.skip_previous, size: 18),
                          label: const Text('Prev Chapter'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                        ),
                        TextButton.icon(
                          onPressed: _goToNextChapter,
                          icon: const Icon(Icons.skip_next, size: 18),
                          label: const Text('Next Chapter'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFF43F5E), size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadPages,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
                child: const Text('Retry Chapter'),
              )
            ],
          ),
        ),
      );
    }

    if (_pages.isEmpty) {
      return const Center(
        child: Text('No pages found for this chapter.', style: TextStyle(color: Colors.white38)),
      );
    }

    switch (_readingMode) {
      case ReadingMode.verticalContinuous:
        return ListView.builder(
          controller: _scrollController,
          itemCount: _pages.length,
          itemBuilder: (context, index) {
            return _buildPageImage(_pages[index]);
          },
        );

      case ReadingMode.horizontalLtr:
      case ReadingMode.horizontalRtl:
        return PageView.builder(
          controller: _pageController,
          reverse: _readingMode == ReadingMode.horizontalRtl,
          itemCount: _pages.length,
          onPageChanged: (idx) => setState(() => _currentPageIndex = idx),
          itemBuilder: (context, index) {
            return Center(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.5,
                child: _buildPageImage(_pages[index]),
              ),
            );
          },
        );
    }
  }

  Widget _buildPageImage(MangaPage page) {
    return Image.network(
      page.imageUrl,
      headers: page.headers,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: 350,
          color: const Color(0xFF1E293B),
          child: Center(
            child: CircularProgressIndicator(
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
              color: const Color(0xFFF43F5E),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 250,
          color: const Color(0xFF1E293B),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image, color: Colors.white38, size: 40),
              const SizedBox(height: 8),
              Text(
                'Page ${page.index + 1} failed to load',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reader Settings',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('Reading Direction', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Vertical (Webtoon)'),
                        selected: _readingMode == ReadingMode.verticalContinuous,
                        selectedColor: const Color(0xFFF43F5E),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _readingMode = ReadingMode.verticalContinuous);
                            setSheetState(() {});
                            Navigator.pop(context);
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Paged (LTR)'),
                        selected: _readingMode == ReadingMode.horizontalLtr,
                        selectedColor: const Color(0xFFF43F5E),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _readingMode = ReadingMode.horizontalLtr);
                            setSheetState(() {});
                            Navigator.pop(context);
                          }
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Paged (RTL - Manga)'),
                        selected: _readingMode == ReadingMode.horizontalRtl,
                        selectedColor: const Color(0xFFF43F5E),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _readingMode = ReadingMode.horizontalRtl);
                            setSheetState(() {});
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
