import 'package:flutter/material.dart';
import '../../../core/extensions/models/manga_models.dart';
import '../../../core/manga/providers/manga_provider.dart';
import 'manga_reader_page.dart';

class MangaDetailsPage extends StatefulWidget {
  final String mangaId;
  final MangaProvider provider;
  final MangaDetails? initialDetails;

  const MangaDetailsPage({
    super.key,
    required this.mangaId,
    required this.provider,
    this.initialDetails,
  });

  @override
  State<MangaDetailsPage> createState() => _MangaDetailsPageState();
}

class _MangaDetailsPageState extends State<MangaDetailsPage> {
  MangaDetails? _details;
  List<MangaChapter> _chapters = [];
  bool _isLoading = true;
  bool _isAscending = false;
  bool _isFavorite = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    _fetchFullDetails();
  }

  Future<void> _fetchFullDetails() async {
    try {
      final details = await widget.provider.getMangaDetails(widget.mangaId);
      final chapters = await widget.provider.getChapters(widget.mangaId);
      if (mounted) {
        setState(() {
          _details = details;
          _chapters = chapters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _details?.title ?? 'Manga Details';
    final cover = _details?.coverUrl ?? '';
    final sortedChapters = _isAscending ? _chapters : _chapters.reversed.toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: const Color(0xFF1E293B),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover.isNotEmpty)
                    Image.network(
                      cover,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFF0F172A).withOpacity(0.9),
                          const Color(0xFF0F172A),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isFavorite ? Icons.bookmark : Icons.bookmark_border,
                  color: _isFavorite ? const Color(0xFFF43F5E) : Colors.white,
                ),
                onPressed: () {
                  setState(() => _isFavorite = !_isFavorite);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_isFavorite ? 'Saved to Library' : 'Removed from Library'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status & Author
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF43F5E).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF43F5E).withOpacity(0.4)),
                        ),
                        child: Text(
                          _details?.status.toDisplayString() ?? 'Ongoing',
                          style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_details?.author != null)
                        Text(
                          'by ${_details!.author}',
                          style: const TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Action Button
                  if (_chapters.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.menu_book),
                        label: const Text('Start Reading'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF43F5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          _openChapter(_chapters.first);
                        },
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Synopsis
                  if (_details?.description != null && _details!.description.isNotEmpty) ...[
                    const Text('Synopsis', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text(
                      _details!.description,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Chapter Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Chapters (${_chapters.length})',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward, size: 18, color: Colors.white70),
                        tooltip: 'Sort Chapters',
                        onPressed: () => setState(() => _isAscending = !_isAscending),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(color: Color(0xFFF43F5E)),
                ),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                ),
              ),
            )
          else if (_chapters.isEmpty)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No chapters available for this title.', style: TextStyle(color: Colors.white38)),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = sortedChapters[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      title: Text(
                        chapter.title,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      subtitle: chapter.releaseDate != null
                          ? Text(chapter.releaseDate!, style: const TextStyle(color: Colors.white38, fontSize: 11))
                          : null,
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => _openChapter(chapter),
                    ),
                  );
                },
                childCount: sortedChapters.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _openChapter(MangaChapter chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MangaReaderPage(
          mangaTitle: _details?.title ?? 'Manga Reader',
          chapter: chapter,
          chapters: _chapters,
          provider: widget.provider,
        ),
      ),
    );
  }
}
