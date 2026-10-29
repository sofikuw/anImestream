import 'dart:io';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/data/settings.dart';
import 'package:animestream/core/data/types.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/core/anime/providers/providerDetails.dart';
import 'package:animestream/core/manga/javascriptMangaProvider.dart';
import 'package:animestream/ui/models/sources.dart';
import 'package:animestream/ui/models/widgets/clickableItem.dart';
import 'package:animestream/ui/models/widgets/toggleItem.dart';
import 'package:animestream/ui/pages/settingPages/cache.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';
import 'package:animestream/ui/pages/settingPages/plugin.dart';
import 'package:animestream/ui/pages/settingPages/providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GeneralSetting extends StatefulWidget {
  const GeneralSetting({super.key});

  @override
  State<GeneralSetting> createState() => _GeneralSettingState();
}

class _GeneralSettingState extends State<GeneralSetting> {
  @override
  initState() {
    readSettings().then((val) => setState(() {
          loaded = true;
        }));
    super.initState();
  }

  Future<void> readSettings() async {
    final settings = await Settings().getSettings();
    final installedManga = await JavaScriptMangaProvider.installedDetails();
    final prefs = await UserPreferences.getUserPreferences();
    setState(() {
      showErrorsButtonState = settings.showErrors!;
      receivePreReleases = settings.receivePreReleases!;
      fasterDownloads = settings.fasterDownloads!;
      useQueuedDownloads = settings.useQueuedDownloads!;
      enableLogging = settings.enableLogging!;
      mangaSources = installedManga;
      defaultMangaProviderId = prefs.defaultMangaProviderId;
    });
  }

  Future<void> writeSettings(SettingsModal settings) async {
    await Settings().writeSettings(settings);
    setState(() {
      readSettings();
    });
  }

  bool loaded = false;
  bool showErrorsButtonState = false;
  bool receivePreReleases = false;
  bool fasterDownloads = false;
  bool useQueuedDownloads = false;
  bool enableDiscordPresence = false;
  bool useDesktopNativeDiscordPresence = false;
  bool enableLogging = false;

  // A getter, not a field: removing a built-in provider from settings must be
  // reflected without recreating this page.
  List<ProviderDetails> get sources => SourceManager.instance.sources;
  List<ProviderDetails> mangaSources = [];
  String? defaultMangaProviderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: loaded
          ? SingleChildScrollView(
              child: Padding(
                padding: pagePadding(context, bottom: true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    settingPagesTitleHeader(context, "General"),
                    ToggleItem(
                      label: "Show errors",
                      value: showErrorsButtonState,
                      onTapFunction: () {
                        setState(() {
                          showErrorsButtonState = !showErrorsButtonState;
                        });
                        writeSettings(SettingsModal(showErrors: showErrorsButtonState));
                      },
                    ),
                    ToggleItem(
                      label: "Receive beta updates",
                      value: receivePreReleases,
                      onTapFunction: () {
                        setState(() {
                          receivePreReleases = !receivePreReleases;
                        });
                        writeSettings(SettingsModal(receivePreReleases: receivePreReleases));
                      },
                      description: "Beta builds check this channel automatically",
                    ),
                    ToggleItem(
                      label: "Quick play",
                      description: "Automatically play the episodes using the last server you used",
                      value: userPreferences?.autoSelectPreviouslyUsedServer ?? false,
                      onTapFunction: () async {
                        await UserPreferences.saveUserPreferences(UserPreferencesModal(
                          autoSelectPreviouslyUsedServer: !(userPreferences?.autoSelectPreviouslyUsedServer ?? false),
                        ));
                        setState(() {});
                      },
                    ),
                    if (Platform.isWindows || Platform.isLinux)
                      ToggleItem(
                        label: "Enable Discord Rich Presence",
                        value: currentUserSettings?.enableDiscordRichPresence ?? false,
                        onTapFunction: () async {
                          await writeSettings(SettingsModal(
                              enableDiscordRichPresence: !(currentUserSettings!.enableDiscordRichPresence ?? false)));
                          setState(() {});
                        },
                      ),
                    if (kDebugMode)
                      ClickableItem(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            showDragHandle: true,
                            isScrollControlled: true,
                            builder: (context) => _databaseSheet(context),
                          );
                        },
                        label: "Default database",
                        description: (currentUserSettings?.database?.name ?? Databases.anilist.name),
                        suffixIcon: Icon(Icons.arrow_drop_down),
                      ),
                    ClickableItem(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (context) => _providerSheet(context),
                        );
                      },
                      label: "Default provider",
                      description: (currentUserSettings?.preferredProvider ??
                              (sources.isEmpty ? '' : sources.first.identifier))
                          .replaceAll('_', ' '),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    ClickableItem(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          showDragHandle: true,
                          isScrollControlled: true,
                          builder: (context) => _mangaProviderSheet(context),
                        );
                      },
                      label: "Default manga provider",
                      description: _mangaProviderLabel(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    ClickableItem(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const BuiltInProvidersPage(),
                          ),
                        );
                      },
                      label: "Built-in providers",
                      description: "Remove defaults and choose metadata fallbacks",
                      suffixIcon: Icon(Icons.navigate_next_rounded),
                    ),
                    ClickableItem(
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => PluginPage()));
                      },
                      label: "Manage Providers",
                      description: "Add or remove providers",
                      suffixIcon: Icon(Icons.navigate_next_rounded),
                    ),
                    ClickableItem(
                      label: "Cache Manager",
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => CacheSetting())),
                      description: "Manage network & API cache",
                      suffixIcon: Icon(Icons.navigate_next_rounded),
                    ),
                    // Got clowned for this decision
                    // ClickableItem(
                    //   label: "Downloader",
                    //   onTap: () =>
                    //       Navigator.of(context).push(MaterialPageRoute(builder: (context) => DownloaderSettings())),
                    //   description: "Configure your downloads",
                    //   suffixIcon: Icon(Icons.navigate_next_rounded),
                    // ),
                    ToggleItem(
                      onTapFunction: () {
                        setState(() {
                          enableLogging = !enableLogging;
                        });
                        writeSettings(SettingsModal(enableLogging: enableLogging));
                      },
                      label: "Enable Logging",
                      description: "Helps with debugging issues",
                      value: enableLogging,
                    )
                  ],
                ),
              ),
            )
          : Container(),
    );
  }

  StatefulBuilder _databaseSheet(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setcState) => Container(
        padding: const EdgeInsets.only(
          top: 10,
          left: 20,
          right: 20,
        ),
        margin: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "Select Database",
                style: textStyle().copyWith(fontSize: 23),
                textAlign: TextAlign.left,
              ),
            ),
            Builder(
              builder: (context) {
                final disabled =
                    currentUserSettings?.disabledMetadataProviders ?? const <String>[];
                final databases = Databases.values
                    .where((database) => !disabled.contains(database.name))
                    .toList();
                return ListView.builder(
                    shrinkWrap: true,
                    itemCount: databases.length,
                    itemBuilder: (context, index) {
                      final activeDatabase =
                          currentUserSettings?.database?.name ?? Databases.anilist.name;
                      final database = databases[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: database.name == activeDatabase
                              ? appTheme.accentColor
                              : appTheme.backgroundSubColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              await writeSettings(SettingsModal(database: database));
                              setState(() {});
                              setcState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Text(
                                database.name,
                                style: textStyle().copyWith(
                                  color: database.name == activeDatabase
                                      ? appTheme.onAccent
                                      : appTheme.textMainColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    });
              },
            ),
          ],
        ),
      ),
    );
  }

  StatefulBuilder _providerSheet(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setcState) => Container(
        padding: const EdgeInsets.only(
          top: 10,
          left: 20,
          right: 20,
        ),
        margin: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "Select Provider",
                style: textStyle().copyWith(fontSize: 23),
                textAlign: TextAlign.left,
              ),
            ),
            ListView.builder(
                shrinkWrap: true,
                itemCount: sources.length,
                itemBuilder: (context, index) {
                  final activeProvider = currentUserSettings?.preferredProvider ??
                      (sources.isEmpty ? '' : sources.first.identifier);
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: sources[index].identifier == activeProvider
                          ? appTheme.accentColor
                          : appTheme.backgroundSubColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          await writeSettings(SettingsModal(preferredProvider: sources[index].identifier));
                          setState(() {});
                          setcState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          child: Text(
                            sources[index].name,
                            style: textStyle().copyWith(
                              color: sources[index].identifier == activeProvider
                                  ? appTheme.onAccent
                                  : appTheme.textMainColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
          ],
        ),
      ),
    );
  }

  String _mangaProviderLabel() {
    final id = defaultMangaProviderId;
    if (id == null || id.isEmpty) return 'None';
    final match = mangaSources.where((source) => source.identifier == id);
    if (match.isEmpty) return id.replaceAll('_', ' ');
    return match.first.name;
  }

  StatefulBuilder _mangaProviderSheet(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setcState) => Container(
        padding: const EdgeInsets.only(
          top: 10,
          left: 20,
          right: 20,
        ),
        margin: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "Select Default Manga Provider",
                style: textStyle().copyWith(fontSize: 23),
                textAlign: TextAlign.left,
              ),
            ),
            if (mangaSources.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  "No manga providers installed. Add a repository or extension first.",
                  style: textStyle(),
                ),
              )
            else
              ListView.builder(
                    shrinkWrap: true,
                    itemCount: mangaSources.length,
                    itemBuilder: (context, index) {
                      final activeProvider =
                          defaultMangaProviderId ?? (mangaSources.isEmpty ? '' : mangaSources.first.identifier);
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: mangaSources[index].identifier == activeProvider
                              ? appTheme.accentColor
                              : appTheme.backgroundSubColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () async {
                              await UserPreferences.saveUserPreferences(
                                UserPreferencesModal(defaultMangaProviderId: mangaSources[index].identifier),
                              );
                              if (!context.mounted) return;
                              setState(() {
                                defaultMangaProviderId = mangaSources[index].identifier;
                              });
                              setcState(() {});
                              Navigator.of(context).pop();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              child: Text(
                                mangaSources[index].name,
                                style: textStyle().copyWith(
                                  color: mangaSources[index].identifier == activeProvider
                                      ? appTheme.onAccent
                                      : appTheme.textMainColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
          ],
        ),
      ),
    );
  }
}
