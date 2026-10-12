import 'package:flutter/material.dart';
import '../../../core/extensions/manager/extension_manager.dart';
import '../../../core/extensions/models/manga_models.dart';
import '../../../core/manga/providers/js_manga_provider_adapter.dart';
import '../../../core/manga/providers/manga_provider.dart';
import 'manga_details_page.dart';
import 'manga_search_page.dart';

/// Manga Home screen adhering strictly to Animestream's visual theme and design language.
class MangaHomePage extends StatefulWidget {
  const MangaHomePage({super.key});

  @override
  State<MangaHomePage> createState() => _MangaHomePageState();
}

class _MangaHomePageState extends State<MangaHomePage> {
  final ExtensionManager _extensionManager = ExtensionManager();
  MangaProvider? _selectedProvider;
  List<MangaDetails> _popularManga = [];
  List<MangaDetails> _latestManga = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _extensionManager.addListener(_onExtensionsChanged);
    _initializeProviders();
  }

  @override
  void dispose() {
    _extensionManager.removeListener(_onExtensionsChanged);
    super.dispose();
  }

  void _onExtensionsChanged() {
    if (mounted) {
      _initializeProviders();
    }
  }

  void _initializeProviders() {
    final available = _extensionManager.mangaExtensions;
    if (available.isNotEmpty) {
      final firstBundle = available.first;
      _selectedProvider = JsMangaProviderAdapter(manifest: firstBundle.manifest);
      _loadContent();
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No manga extensions installed. Go to Settings > Manage Extensions to install sources.';
      });
    }
  }

  Future<void> _loadContent() async {
    if (_selectedProvider == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final popular = await _selectedProvider!.getPopularManga();
      final latest = await _selectedProvider!.getLatestManga();
      if (mounted) {
        setState(() {
          _popularManga = popular;
          _latestManga = latest;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load content from ${_selectedProvider?.name}: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Manga',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Provider Selector Dropdown
          if (_extensionManager.mangaExtensions.isNotEmpty)
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProvider?.id,
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                items: _extensionManager.mangaExtensions.map((ext) {
                  return DropdownMenuItem<String>(
                    value: ext.manifest.id,
                    child: Text(ext.manifest.name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val == null) return;
                  final match = _extensionManager.mangaExtensions.firstWhere((e) => e.manifest.id == val);
                  setState(() {
                    _selectedProvider = JsMangaProviderAdapter(manifest: match.manifest);
                  });
                  _loadContent();
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Manga',
            onPressed: () {
              if (_selectedProvider != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MangaSearchPage(initialProvider: _selectedProvider!),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF43F5E)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_outlined, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadContent,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF43F5E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFF43F5E),
      onRefresh: _loadContent,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Featured / Popular Section
          if (_popularManga.isNotEmpty) ...[
            _buildSectionHeader('Popular Manga', Icons.trending_up, onSeeAll: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MangaSearchPage(initialProvider: _selectedProvider!),
                ),
              );
            }),
            _buildHorizontalMangaList(_popularManga),
          ],

          const SizedBox(height: 24),

          // Latest Updates Section
          if (_latestManga.isNotEmpty) ...[
            _buildSectionHeader('Latest Releases', Icons.access_time_rounded, onSeeAll: () {}),
            _buildHorizontalMangaList(_latestManga),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFF43F5E)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                'See All',
                style: TextStyle(color: Color(0xFFF43F5E), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalMangaList(List<MangaDetails> list) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final manga = list[index];
          return Container(
            width: 130,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MangaDetailsPage(
                      mangaId: manga.id,
                      provider: _selectedProvider!,
                      initialDetails: manga,
                    ),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster Card
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        color: const Color(0xFF1E293B),
                        child: manga.coverUrl.isNotEmpty
                            ? Image.network(
                                manga.coverUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image, color: Colors.white30),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.menu_book, color: Colors.white30),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Title
                  Text(
                    manga.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
