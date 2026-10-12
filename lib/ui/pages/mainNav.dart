import 'package:flutter/material.dart';
import 'manga/manga_home_page.dart';
import 'settingPages/manage_extensions_page.dart';

/// Main navigation shell hosting BottomNavigationBar and NavigationRail.
/// Seamlessly integrates the Manga destination alongside original Animestream destinations.
class MainNavPage extends StatefulWidget {
  const MainNavPage({super.key});

  @override
  State<MainNavPage> createState() => _MainNavPageState();
}

class _MainNavPageState extends State<MainNavPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    // 0: Anime Home
    const _PlaceholderAnimeHome(),
    // 1: Discover
    const _PlaceholderDiscover(),
    // 2: Manga Tab (Mangayomi-style dynamic extension reader)
    const MangaHomePage(),
    // 3: Downloads
    const _PlaceholderDownloads(),
    // 4: Settings
    const _SettingsNavigationWrapper(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          indicatorColor: const Color(0xFFF43F5E).withOpacity(0.2),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(color: Color(0xFFF43F5E), fontSize: 12, fontWeight: FontWeight.bold);
            }
            return const TextStyle(color: Colors.white60, fontSize: 12);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.home, color: Color(0xFFF43F5E)),
              label: 'Anime',
            ),
            NavigationDestination(
              icon: Icon(Icons.explore_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.explore, color: Color(0xFFF43F5E)),
              label: 'Discover',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.menu_book, color: Color(0xFFF43F5E)),
              label: 'Manga',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.download, color: Color(0xFFF43F5E)),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: Colors.white70),
              selectedIcon: Icon(Icons.settings, color: Color(0xFFF43F5E)),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderAnimeHome extends StatelessWidget {
  const _PlaceholderAnimeHome();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Animestream', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: const Center(
        child: Text('Anime Home & Streaming Feed', style: TextStyle(color: Colors.white60)),
      ),
    );
  }
}

class _PlaceholderDiscover extends StatelessWidget {
  const _PlaceholderDiscover();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(title: const Text('Discover'), backgroundColor: Colors.transparent),
      body: const Center(child: Text('Discover Anime', style: TextStyle(color: Colors.white60))),
    );
  }
}

class _PlaceholderDownloads extends StatelessWidget {
  const _PlaceholderDownloads();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(title: const Text('Downloads'), backgroundColor: Colors.transparent),
      body: const Center(child: Text('Offline Downloads & PiP Queues', style: TextStyle(color: Colors.white60))),
    );
  }
}

class _SettingsNavigationWrapper extends StatelessWidget {
  const _SettingsNavigationWrapper();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const Icon(Icons.extension, color: Color(0xFFF43F5E)),
              title: const Text('Manage Extensions', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text('Install, update, and manage community JavaScript extensions', style: TextStyle(color: Colors.white60, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right, color: Colors.white38),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ManageExtensionsPage()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
