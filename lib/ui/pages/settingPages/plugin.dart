import 'package:animestream/core/anime/providers/providerCatalogService.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/anime/providers/providerManager.dart';
import 'package:animestream/core/anime/providers/providerRepository.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/data/providerRepositories.dart';
import 'package:animestream/core/data/settings.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/ui/models/sources.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:flutter/material.dart';

class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _providerManager = ProviderManager();
  final _repositoryPreferences = ProviderRepositoriesPreferences();
  final _catalogService = ProviderCatalogService();
  final Set<String> _busyProviderIds = <String>{};
  final Set<String> _busyRepositoryIds = <String>{};

  List<ProviderDetails> _installed = <ProviderDetails>[];
  List<ProviderRepository> _repositories = <ProviderRepository>[];
  Map<String, ProviderCatalog> _catalogs = <String, ProviderCatalog>{};
  Map<String, String> _repositoryErrors = <String, String>{};
  bool _loading = true;
  String? _pageError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _pageError = null;
      });
    }
    try {
      final repositories = await _repositoryPreferences.listRepositories();
      final installed = await _providerManager.getSavedProviders();
      final catalogs = <String, ProviderCatalog>{};
      final errors = <String, String>{};
      await Future.wait(
        repositories.map((repository) async {
          try {
            catalogs[repository.id] =
                await _catalogService.fetchCatalog(repository);
          } catch (error) {
            errors[repository.id] = _readableError(error);
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _repositories = repositories;
        _installed = installed;
        _catalogs = catalogs;
        _repositoryErrors = errors;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pageError = _readableError(error);
        _loading = false;
      });
    }
  }

  Future<void> _refreshRepository(ProviderRepository repository) async {
    setState(() => _busyRepositoryIds.add(repository.id));
    try {
      final catalog = await _catalogService.fetchCatalog(repository);
      if (!mounted) return;
      setState(() {
        _catalogs[repository.id] = catalog;
        _repositoryErrors.remove(repository.id);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _catalogs.remove(repository.id);
        _repositoryErrors[repository.id] = _readableError(error);
      });
      _showMessage('Could not refresh ${repository.name}: ${_readableError(error)}');
    } finally {
      if (mounted) setState(() => _busyRepositoryIds.remove(repository.id));
    }
  }

  Future<void> _addRepository() async {
    final controller = TextEditingController();
    final rawUrl = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: appTheme.backgroundSubColor,
        title: Text('Add provider repository', style: _titleStyle()),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: TextStyle(color: appTheme.textMainColor),
          decoration: InputDecoration(
            hintText: 'https://example.org/providers/index.json',
            hintStyle: TextStyle(color: appTheme.textSubColor),
            labelText: 'Catalog URL',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (rawUrl == null || rawUrl.trim().isEmpty) return;

    try {
      final repository = ProviderRepository.fromIndexUrl(rawUrl);
      if (_repositories.any((item) => item.id == repository.id)) {
        _showMessage('That repository is already added.');
        return;
      }
      await _repositoryPreferences.saveRepository(repository);
      setState(() {
        _repositories = [..._repositories, repository];
        _busyRepositoryIds.add(repository.id);
      });
      await _refreshRepository(repository);
    } catch (error) {
      _showMessage('Could not add repository: ${_readableError(error)}');
    }
  }

  Future<void> _removeRepository(ProviderRepository repository) async {
    final confirmed = await _confirm(
      title: 'Remove repository?',
      message:
          'This removes ${repository.name} from the catalog list. Providers already installed from it will stay installed.',
      action: 'Remove',
    );
    if (!confirmed) return;
    await _repositoryPreferences.removeRepository(repository.id);
    if (!mounted) return;
    setState(() {
      _repositories.removeWhere((item) => item.id == repository.id);
      _catalogs.remove(repository.id);
      _repositoryErrors.remove(repository.id);
    });
  }

  Future<void> _install(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    await _runProviderAction(manifest.identifier, () async {
      await _catalogService.install(repository, manifest);
      await _refreshInstalledSources();
      _showMessage(
        '${manifest.name} installed and disabled. Enable it from Installed.',
      );
    });
  }

  Future<void> _update(
    ProviderRepository repository,
    JsAnimeProviderManifest manifest,
  ) async {
    await _runProviderAction(manifest.identifier, () async {
      await _catalogService.update(repository, manifest);
      await SourceManager.instance.disposeProvider(manifest.identifier);
      await _refreshInstalledSources();
      _showMessage('${manifest.name} updated.');
    });
  }

  Future<void> _setEnabled(ProviderDetails provider, bool enabled) async {
    if (provider.scriptType.toLowerCase() != 'javascript') {
      _showMessage('Only JavaScript extensions can be enabled here.');
      return;
    }
    if (enabled) {
      final confirmed = await _confirm(
        title: 'Enable ${provider.name}?',
        message:
            'This runs third-party JavaScript in the app process, not a separate OS sandbox. It has no JavaScript filesystem, native-code, or direct-network APIs; execution is limited to 5 seconds and a 64 MiB heap, and HTTP is restricted to manifest-listed hosts. These limits are defense-in-depth, not a boundary against native runtime vulnerabilities. Continue only if you trust its repository.',
        action: 'Enable',
      );
      if (!confirmed) return;
    }
    await _runProviderAction(provider.identifier, () async {
      if (!enabled) {
        await SourceManager.instance.disposeProvider(provider.identifier);
      }
      await _providerManager.saveProvider(provider.copyWith(enabled: enabled));
      if (!enabled) await _fallbackDefaultProvider(provider.identifier);
      await _refreshInstalledSources();
    });
  }

  Future<void> _uninstall(ProviderDetails provider) async {
    final confirmed = await _confirm(
      title: 'Uninstall ${provider.name}?',
      message: 'Its downloaded provider code and settings will be removed.',
      action: 'Uninstall',
    );
    if (!confirmed) return;
    await _runProviderAction(provider.identifier, () async {
      await SourceManager.instance.disposeProvider(provider.identifier);
      await _providerManager.removeProvider(provider);
      await _fallbackDefaultProvider(provider.identifier);
      await _fallbackDefaultMangaProvider(provider.identifier);
      await _refreshInstalledSources();
    });
  }

  Future<void> _refreshInstalledSources() async {
    _installed = await _providerManager.getSavedProviders();
    await SourceManager.instance.refreshInstalledProviders();
    if (mounted) setState(() {});
  }

  Future<void> _fallbackDefaultProvider(String identifier) async {
    final settings = currentUserSettings ?? await Settings().getSettings();
    if (settings.preferredProvider != identifier) return;
    // The first *enabled* source other than the one being removed: the user
    // may have removed some built-ins in Built-in providers.
    final sources = SourceManager.instance.sources
        .where((source) => source.identifier != identifier)
        .toList(growable: false);
    if (sources.isEmpty) return;
    await Settings().writeSettings(
      SettingsModal(preferredProvider: sources.first.identifier),
    );
  }

  Future<void> _fallbackDefaultMangaProvider(String identifier) async {
    final prefs = await UserPreferences.getUserPreferences();
    final cleared = UserPreferencesModal(
      defaultMangaProviderId: prefs.defaultMangaProviderId == identifier ? '' : null,
      lastMangaProviderId: prefs.lastMangaProviderId == identifier ? '' : null,
    );
    if (cleared.defaultMangaProviderId == null && cleared.lastMangaProviderId == null) return;
    await UserPreferences.saveUserPreferences(cleared);
  }

  Future<void> _runProviderAction(
    String identifier,
    Future<void> Function() action,
  ) async {
    if (_busyProviderIds.contains(identifier)) return;
    setState(() => _busyProviderIds.add(identifier));
    try {
      await action();
    } catch (error) {
      _showMessage(_readableError(error));
    } finally {
      if (mounted) setState(() => _busyProviderIds.remove(identifier));
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: appTheme.backgroundSubColor,
            title: Text(title, style: _titleStyle()),
            content: Text(
              message,
              style: TextStyle(color: appTheme.textSubColor),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: appTheme.backgroundSubColor,
        ),
      );
  }

  String _readableError(Object error) {
    final message = error.toString();
    return message.startsWith('FormatException: ')
        ? message.substring('FormatException: '.length)
        : message.startsWith('Bad state: ')
            ? message.substring('Bad state: '.length)
            : message;
  }

  TextStyle _titleStyle() => TextStyle(
        color: appTheme.textMainColor,
        fontFamily: 'Rubik',
        fontWeight: FontWeight.bold,
      );

  ProviderDetails? _installedProvider(String identifier) {
    for (final provider in _installed) {
      if (provider.identifier == identifier) return provider;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: pagePadding(context, bottom: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              topRow(context, 'Manage Providers'),
              _securityNote(),
              TabBar(
                controller: _tabController,
                labelColor: appTheme.accentColor,
                unselectedLabelColor: appTheme.textSubColor,
                indicatorColor: appTheme.accentColor,
                tabs: const [
                  Tab(text: 'Installed'),
                  Tab(text: 'Catalog'),
                  Tab(text: 'Repositories'),
                ],
              ),
              if (_loading) ...[
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ] else if (_pageError != null) ...[
                Expanded(
                  child: _emptyState(
                    Icons.error_outline_rounded,
                    'Could not load providers',
                    _pageError!,
                    actionLabel: 'Retry',
                    onAction: _load,
                  ),
                ),
              ] else ...[
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _installedTab(),
                      _catalogTab(),
                      _repositoriesTab(),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _securityNote() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: appTheme.accentColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Only add repositories you trust. JavaScript has no file/native APIs; execution has 5-second and 64 MiB limits and HTTPS is restricted to manifest hosts. This is not a separate OS sandbox.',
              style: TextStyle(
                color: appTheme.textSubColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _installedTab() {
    if (_installed.isEmpty) {
      return _emptyState(
        Icons.extension_outlined,
        'No installed providers',
        'Browse a repository catalog to install an extension.',
        actionLabel: 'Browse catalog',
        onAction: () => _tabController.animateTo(1),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _installed.length,
      itemBuilder: (context, index) {
        final provider = _installed[index];
        final update = _updateFor(provider);
        final busy = _busyProviderIds.contains(provider.identifier);
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.extension_rounded,
                    color: appTheme.accentColor,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(provider.name, style: _titleStyle()),
                        Text(
                          'v${provider.version}  •  ${provider.identifier}',
                          style: TextStyle(
                            color: appTheme.textSubColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (provider.scriptType.toLowerCase() == 'javascript')
                    Switch(
                      value: provider.enabled,
                      activeThumbColor: appTheme.onAccent,
                      activeTrackColor: appTheme.accentColor,
                      onChanged: (value) => _setEnabled(provider, value),
                    )
                  else
                    Text(
                      'Legacy Dart',
                      style: TextStyle(
                        color: appTheme.textSubColor,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4),
                child: Text(
                  provider.scriptType.toLowerCase() != 'javascript'
                      ? 'Legacy provider record'
                      : _sourceLabel(provider.repositoryUrl),
                  style: TextStyle(color: appTheme.textSubColor, fontSize: 12),
                ),
              ),
              if (update != null)
                Padding(
                  padding: const EdgeInsets.only(left: 40, top: 6),
                  child: Text(
                    'Update available: v${update.manifest.version}',
                    style: TextStyle(color: appTheme.accentColor, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (update != null)
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => _update(
                                update.repository,
                                update.manifest,
                              ),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Update'),
                    ),
                  TextButton.icon(
                    onPressed: busy ? null : () => _uninstall(provider),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _sourceLabel(String? rawUrl) {
    if (rawUrl == null) return 'Installed locally';
    try {
      return 'Source: ${Uri.parse(rawUrl).host}';
    } on FormatException {
      return 'Installed from a saved repository';
    }
  }

  _CatalogEntry? _updateFor(ProviderDetails installed) {
    if (installed.scriptType.toLowerCase() != 'javascript') return null;
    for (final repository in _repositories) {
      if (repository.indexUrl != installed.repositoryUrl) continue;
      final catalog = _catalogs[repository.id];
      if (catalog == null) continue;
      for (final manifest in catalog.providers) {
        if (manifest.identifier == installed.identifier &&
            _isNewerVersion(manifest.version, installed.version)) {
          return _CatalogEntry(repository, manifest);
        }
      }
    }
    return null;
  }

  Widget _catalogTab() {
    final entries = <_CatalogEntry>[];
    for (final repository in _repositories) {
      final catalog = _catalogs[repository.id];
      if (catalog == null) continue;
      entries.addAll(
        catalog.providers.map(
          (provider) => _CatalogEntry(repository, provider),
        ),
      );
    }
    if (_repositories.isEmpty) {
      return _emptyState(
        Icons.travel_explore_rounded,
        'No repositories yet',
        'Add an HTTPS repository index to browse its JavaScript extensions.',
        actionLabel: 'Add repository',
        onAction: _addRepository,
      );
    }
    if (entries.isEmpty) {
      final failed = _repositoryErrors.isNotEmpty;
      return _emptyState(
        failed ? Icons.cloud_off_rounded : Icons.search_rounded,
        failed ? 'Catalogs could not be loaded' : 'No providers listed',
        failed
            ? 'Check the repository URL and connection in the Repositories tab.'
            : 'The added catalogs do not list any providers.',
        actionLabel: 'Refresh',
        onAction: _load,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: entries.length,
      itemBuilder: (context, index) => _catalogCard(entries[index]),
    );
  }

  Widget _catalogCard(_CatalogEntry entry) {
    final manifest = entry.manifest;
    final installed = _installedProvider(manifest.identifier);
    final busy = _busyProviderIds.contains(manifest.identifier);
    final sameRepository =
        installed?.scriptType.toLowerCase() == 'javascript' &&
            installed?.repositoryUrl == entry.repository.indexUrl;
    final canUpdate = installed != null &&
        sameRepository &&
        _isNewerVersion(manifest.version, installed.version);
    final upToDate = installed != null && sameRepository && !canUpdate;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.extension_outlined,
                color: appTheme.accentColor,
                size: 27,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(manifest.name, style: _titleStyle()),
                    Text(
                      'v${manifest.version}  •  ${manifest.identifier}',
                      style: TextStyle(
                        color: appTheme.textSubColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _catalogAction(
                  installed: installed,
                  canUpdate: canUpdate,
                  upToDate: upToDate,
                  entry: entry,
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 39, top: 8),
            child: Text(
              'Repository: ${entry.repository.name}'
              '${manifest.supportDownloads ? '  •  Downloads' : ''}',
              style: TextStyle(color: appTheme.textSubColor, fontSize: 12),
            ),
          ),
          if (installed != null && !sameRepository)
            Padding(
              padding: const EdgeInsets.only(left: 39, top: 4),
              child: Text(
                'This identifier is installed from another repository.',
                style: TextStyle(color: appTheme.textSubColor, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _catalogAction({
    required ProviderDetails? installed,
    required bool canUpdate,
    required bool upToDate,
    required _CatalogEntry entry,
  }) {
    if (installed == null) {
      return TextButton(
        onPressed: () => _install(entry.repository, entry.manifest),
        child: const Text('Install'),
      );
    }
    if (canUpdate) {
      return TextButton(
        onPressed: () => _update(entry.repository, entry.manifest),
        child: const Text('Update'),
      );
    }
    return TextButton(
      onPressed: null,
      child: Text(upToDate ? 'Installed' : 'Unavailable'),
    );
  }

  bool _isNewerVersion(String candidate, String installed) {
    try {
      return JsAnimeProviderManifest.compareVersions(candidate, installed) > 0;
    } on FormatException {
      return false;
    }
  }

  Widget _repositoriesTab() {
    if (_repositories.isEmpty) {
      return _emptyState(
        Icons.source_outlined,
        'No repositories added',
        'Repositories provide a versioned catalog. Installed providers remain available if a repository is removed.',
        actionLabel: 'Add repository',
        onAction: _addRepository,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addRepository,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add repository'),
          ),
        ),
        for (final repository in _repositories)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(repository.name, style: _titleStyle()),
                const SizedBox(height: 5),
                SelectableText(
                  repository.indexUrl,
                  style: TextStyle(
                    color: appTheme.textSubColor,
                    fontSize: 12,
                  ),
                ),
                if (_repositoryErrors[repository.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Catalog error: ${_repositoryErrors[repository.id]}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  )
                else if (_catalogs[repository.id] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_catalogs[repository.id]!.providers.length} extension(s)',
                      style: TextStyle(color: appTheme.textSubColor),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: _busyRepositoryIds.contains(repository.id)
                          ? null
                          : () => _refreshRepository(repository),
                      icon: _busyRepositoryIds.contains(repository.id)
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh'),
                    ),
                    TextButton.icon(
                      onPressed: () => _removeRepository(repository),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appTheme.backgroundSubColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: appTheme.textSubColor, size: 44),
            const SizedBox(height: 12),
            Text(title, style: _titleStyle()),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: appTheme.textSubColor),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogEntry {
  const _CatalogEntry(this.repository, this.manifest);

  final ProviderRepository repository;
  final JsAnimeProviderManifest manifest;
}
