import 'package:flutter/material.dart';
import '../../../core/extensions/manager/extension_manager.dart';
import '../../../core/extensions/manager/repository_manager.dart';
import '../../../core/extensions/manager/safe_installer.dart';
import '../../../core/extensions/models/extension_catalog.dart';

class ManageExtensionsPage extends StatefulWidget {
  const ManageExtensionsPage({super.key});

  @override
  State<ManageExtensionsPage> createState() => _ManageExtensionsPageState();
}

class _ManageExtensionsPageState extends State<ManageExtensionsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ExtensionManager _extensionManager = ExtensionManager();
  final RepositoryManager _repoManager = RepositoryManager();
  final Map<String, InstallProgress> _installingState = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _extensionManager.addListener(_onStateChanged);
    _repoManager.addListener(_onStateChanged);
    _repoManager.refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _extensionManager.removeListener(_onStateChanged);
    _repoManager.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Manage Extensions', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Add Repository',
            onPressed: _showAddRepoDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Repositories',
            onPressed: () => _repoManager.refreshAll(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF43F5E),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: 'Installed (${_extensionManager.installedExtensions.length})'),
            const Tab(text: 'Available in Repos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInstalledTab(),
          _buildBrowseTab(),
        ],
      ),
    );
  }

  Widget _buildInstalledTab() {
    final installed = _extensionManager.installedExtensions.values.toList();
    if (installed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.extension_off_outlined, color: Colors.white24, size: 48),
              const SizedBox(height: 12),
              const Text('No dynamic extensions installed.', style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _tabController.animateTo(1),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
                child: const Text('Browse Extension Repos'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: installed.length,
      itemBuilder: (context, index) {
        final bundle = installed[index];
        final manifest = bundle.manifest;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 44,
                height: 44,
                color: const Color(0xFF334155),
                child: manifest.iconUrl.isNotEmpty
                    ? Image.network(manifest.iconUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.extension, color: Colors.white70))
                    : const Icon(Icons.extension, color: Colors.white70),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    manifest.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF43F5E).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    manifest.type.name.toUpperCase(),
                    style: const TextStyle(color: Color(0xFFF43F5E), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'v${manifest.version} • by ${manifest.author}',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: bundle.isEnabled,
                  activeColor: const Color(0xFFF43F5E),
                  onChanged: (val) => _extensionManager.toggleExtension(manifest.id, val),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                  onPressed: () => _confirmUninstall(manifest.id, manifest.name),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrowseTab() {
    final available = _repoManager.allAvailableExtensions;
    if (_repoManager.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFF43F5E)));
    }
    if (available.isEmpty) {
      return const Center(child: Text('No extensions found in configured repositories.', style: TextStyle(color: Colors.white38)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: available.length,
      itemBuilder: (context, index) {
        final item = available[index];
        final isInstalled = _extensionManager.isInstalled(item.id);
        final inProgress = _installingState[item.id];

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: const Color(0xFF334155),
                    child: item.iconUrl.isNotEmpty
                        ? Image.network(item.iconUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.extension, color: Colors.white70))
                        : const Icon(Icons.extension, color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.type.name.toUpperCase(),
                              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'v${item.version} • ${item.lang.toUpperCase()} • ${item.author}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (inProgress != null) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: inProgress.progress, color: const Color(0xFFF43F5E)),
                        const SizedBox(height: 4),
                        Text(inProgress.status, style: const TextStyle(color: Colors.white60, fontSize: 11)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (inProgress == null)
                  ElevatedButton(
                    onPressed: () => _installExtension(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isInstalled ? const Color(0xFF334155) : const Color(0xFFF43F5E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(isInstalled ? 'Update' : 'Install', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _installExtension(ExtensionCatalogItem item) async {
    setState(() {
      _installingState[item.id] = InstallProgress(extensionId: item.id, status: 'Starting install...');
    });

    await _extensionManager.installExtension(
      item,
      onProgress: (p) {
        if (mounted) setState(() => _installingState[item.id] = p);
      },
    );

    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() => _installingState.remove(item.id));
  }

  void _confirmUninstall(String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Uninstall $name?', style: const TextStyle(color: Colors.white)),
        content: const Text('This will delete the local extension bundle. You can reinstall it anytime.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              _extensionManager.uninstallExtension(id);
            },
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
  }

  void _showAddRepoDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Add Extension Repository', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the HTTPS raw URL hosting an index.json catalog.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'https://raw.githubusercontent.com/.../repo',
                hintStyle: TextStyle(color: Colors.white30),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF43F5E)),
            onPressed: () {
              Navigator.pop(ctx);
              _repoManager.addRepository(controller.text);
            },
            child: const Text('Add Repo'),
          ),
        ],
      ),
    );
  }
}
