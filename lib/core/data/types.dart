// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:animestream/core/commons/enums.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/ui/models/widgets/subtitles/subtitleSettings.dart';

class SettingsModal {
  /// Skip duration in seconds for the player [defaults to 10 seconds]
  final int? skipDuration;

  /// Mega skip duration in seconds for the player [defaults to 85 seconds]
  final int? megaSkipDuration;

  /// Error display errors as snackbars [defaults to false]
  final bool? showErrors;

  /// Enable pre-release update notifications [defaults to false]
  final bool? receivePreReleases;

  /// AMOLED background for dark mode [defaults to false]
  final bool? amoledBackground;

  /// Preferred quality for the player [defaults to 720p]
  final String? preferredQuality; // 1080p | 720p |480p | 360p as string

  /// The trasparency of the homescreen navbar
  final double? navbarTranslucency; //value from 0 to 1

  /// Enable faster downloads using increased batch size [defaults to false]
  final bool? fasterDownloads;

  /// Preferred source provider for playback [defaults to most stable provider available]
  final String? preferredProvider;

  /// App's dark mode state [defaults to true]
  final bool? darkMode;

  /// Use material you theming (just the pallette) [defaults to false]
  final bool? materialTheme;

  /// Dev access [defaults to false]
  final bool? isDev;

  /// The preferred download path for anime/banner downloads [defaults to the OS download path]
  final String? downloadPath;

  /// The preferred database provider (SIMKL/MAL/AL) [defaults to Anilist]
  final Databases? database;

  /// Identifiers of built-in streaming providers the user removed.
  ///
  /// Installed extensions are never in this list: removing those uninstalls
  /// them. These are the providers that ship with the app, which would
  /// otherwise reappear on every launch.
  final List<String>? disabledProviders;

  /// Metadata databases the user removed from search and browse.
  ///
  /// Disabling AniList keeps it as the router that forwards to the configured
  /// fallbacks; the other databases are not fallback providers themselves.
  final List<String>? disabledMetadataProviders;

  /// Ordered fallback database ids used when AniList is unavailable.
  ///
  /// Defaults to MAL then Kitsu. Empty means no fallback.
  final List<String>? metadataFallbacks;

  /// Enable extra speed options in player (4x,5x,8x,10x) [defaults to false]
  final bool? enableSuperSpeeds;

  /// Download items one by one instead of parallel downloads [defaults to false]
  final bool? useQueuedDownloads;

  /// Use frameless window (Windows only, not used rn)
  final bool? useFramelessWindow;

  /// Enable double tap to skip in player (Not available for desktops) [defaults to true]
  final bool? doubleTapToSkip;

  /// Use native titles (japanese/korean) when available instead of romaji/english [defaults to false]
  final bool? nativeTitle;

  /// Enable picture in picture mode on minimize (Not available for desktops) [defaults to true]
  final bool? enablePipOnMinimize;

  /// Automatically skip opening and ending themes [defaults to false]
  final bool? autoOpEdSkip;

  /// Enable logging throughout the app [defaults to false]
  final bool? enableLogging;

  /// Tap and Hold to speed up the player [defaults to true]
  final bool? enableHoldToSpeedUp;

  /// Enable volume and brightness gestures in player screen
  final bool? enablePlayerGestures;

  /// Use the old navbar instead of the new one (Not available for desktops) [defaults to false]
  final bool? useOldNavbar;

  /// Use experimental mkv video convertion
  final bool? useMkvRemuxer;

  /// Enable discord rich presence
  final bool? enableDiscordRichPresence;

  /// Write the subtitle track to video file (only works when using remuxer)
  final bool? writeSubtitleTrackToVideo;

  SettingsModal({
    this.megaSkipDuration,
    this.skipDuration,
    this.showErrors,
    this.receivePreReleases,
    this.amoledBackground,
    this.preferredQuality,
    this.navbarTranslucency,
    this.fasterDownloads,
    this.preferredProvider,
    this.darkMode,
    this.materialTheme,
    this.isDev,
    this.downloadPath,
    this.database,
    this.disabledProviders,
    this.disabledMetadataProviders,
    this.metadataFallbacks,
    this.enableSuperSpeeds,
    this.useQueuedDownloads,
    this.useFramelessWindow,
    this.doubleTapToSkip,
    this.nativeTitle,
    this.enablePipOnMinimize,
    this.autoOpEdSkip,
    this.enableLogging,
    this.enableHoldToSpeedUp,
    this.enablePlayerGestures,
    this.useOldNavbar,
    this.useMkvRemuxer,
    this.enableDiscordRichPresence,
    this.writeSubtitleTrackToVideo,
  });

  factory SettingsModal.fromMap(Map<dynamic, dynamic> map) {
    return SettingsModal(
      megaSkipDuration: map['megaSkipDuration'] ?? 85,
      skipDuration: map['skipDuration'] ?? 10,
      showErrors: map['showErrors'] ?? false,
      receivePreReleases: map['receivePreReleases'] ?? false,
      amoledBackground: map['amoledBackground'] ?? false,
      preferredQuality: map['preferredQuality'] ?? "720p",
      navbarTranslucency: map['navbarTranslucency'] ?? 1.0,
      fasterDownloads: map['fasterDownloads'] ?? false,
      preferredProvider: map['preferredProvider'] ?? null,
      darkMode: map['darkMode'] ?? true,
      materialTheme: map['materialTheme'] ?? false,
      isDev: map['isDev'] ?? false,
      downloadPath: map['downloadPath'], // No default value since we can assign them at runtime according to OS
      database: DatabaseFromString.getDb(map['database'] ?? "anilist"),
      disabledProviders: map['disabledProviders'] is List
          ? (map['disabledProviders'] as List).whereType<String>().toList()
          : const <String>[],
      disabledMetadataProviders: map['disabledMetadataProviders'] is List
          ? (map['disabledMetadataProviders'] as List).whereType<String>().toList()
          : const <String>[],
      metadataFallbacks: map['metadataFallbacks'] is List
          ? (map['metadataFallbacks'] as List).whereType<String>().toList()
          : const <String>['mal', 'kitsu'],
      enableSuperSpeeds: map['enableSuperSpeeds'] ?? false,
      useQueuedDownloads: map['useQueuedDownloads'] ?? false,
      useFramelessWindow: map['useFramelessWindow'] ?? false,
      doubleTapToSkip: map['doubleTapToSkip'] ?? true,
      nativeTitle: map['nativeTitle'] ?? false,
      enablePipOnMinimize: map['enablePipOnMinimize'] ?? true,
      autoOpEdSkip: map['autoOpEdSkip'] ?? false,
      enableLogging: map['enableLogging'] ?? false,
      enableHoldToSpeedUp: map['enableHoldToSpeedUp'] ?? true,
      enablePlayerGestures: map['enablePlayerGestures'] ?? false,
      useOldNavbar: map['useOldNavbar'] ?? false,
      useMkvRemuxer: map['useMkvRemuxer'] ?? true,
      enableDiscordRichPresence: map['enableDiscordRichPresence'] ?? false,
      writeSubtitleTrackToVideo: map['writeSubtitleTrackToVideo'] ?? false,
    );
  }

  Map<dynamic, dynamic> toMap() {
    return {
      'skipDuration': skipDuration,
      'megaSkipDuration': megaSkipDuration,
      'showErrors': showErrors,
      'receivePreReleases': receivePreReleases,
      'amoledBackground': amoledBackground,
      'preferredQuality': preferredQuality,
      'navbarTranslucency': navbarTranslucency,
      'fasterDownloads': fasterDownloads,
      'preferredProvider': preferredProvider,
      'darkMode': darkMode,
      'materialTheme': materialTheme,
      'isDev': isDev,
      'downloadPath': downloadPath,
      'database': database?.name,
      'disabledProviders': disabledProviders,
      'disabledMetadataProviders': disabledMetadataProviders,
      'metadataFallbacks': metadataFallbacks,
      'enableSuperSpeeds': enableSuperSpeeds,
      'useQueuedDownloads': useQueuedDownloads,
      'useFramelessWindow': useFramelessWindow,
      'doubleTapToSkip': doubleTapToSkip,
      'nativeTitle': nativeTitle,
      'enablePipOnMinimize': enablePipOnMinimize,
      'autoOpEdSkip': autoOpEdSkip,
      'enableLogging': enableLogging,
      'enableHoldToSpeedUp': enableHoldToSpeedUp,
      'enablePlayerGestures': enablePlayerGestures,
      'useOldNavbar': useOldNavbar,
      'useMkvRemuxer': useMkvRemuxer,
      'enableDiscordRichPresence': enableDiscordRichPresence,
      'writeSubtitleTrackToVideo': writeSubtitleTrackToVideo,
    };
  }
}

/// Strings rather than an enum, for the same reason [searchPageListMode] is a
/// bool and not an enum: these are written straight into the Hive map, and a
/// stored value that no longer maps to an enum constant would throw on read.
/// Unknown values fall back to the default in the getters below.
const String mangaReaderLayoutScroll = 'scroll';
const String mangaReaderLayoutPaged = 'paged';

/// Chapter list order: [mangaChapterSortDesc] (the default, newest first) or
/// [mangaChapterSortAsc]. Strings for the same reason the reader layout is:
/// these are written straight into the Hive map, and a stored value with no
/// matching enum constant would throw on read.
const String mangaChapterSortDesc = 'desc';
const String mangaChapterSortAsc = 'asc';

class UserPreferencesModal {
  final EpisodeViewModes? episodesViewMode;
  final SubtitleSettings? subtitleSettings;
  final bool? preferDubs;
  final bool? searchPageListMode;
  final bool? autoSelectPreviouslyUsedServer;

  /// How the manga reader lays a chapter out: [mangaReaderLayoutScroll] for a
  /// continuous webtoon-style strip (the default), [mangaReaderLayoutPaged] for
  /// one page at a time.
  final String? mangaReaderLayout;

  /// Page order in paged mode: "ltr" or "rtl". Meaningless while the layout is
  /// a vertical strip, which is why the reader's settings sheet disables it
  /// there rather than silently ignoring it.
  final String? mangaReaderDirection;

  /// Whether a page can be pinch-zoomed and panned. Paged mode only: a
  /// scale-claiming gesture detector inside the scrolling strip competes with
  /// the strip's own scroll gesture, and losing that fight mid-scroll is worse
  /// than not having zoom.
  final bool? mangaReaderZoom;

  /// Chapter list order on the manga details page: [mangaChapterSortDesc] for
  /// newest first (the default), [mangaChapterSortAsc] for oldest first.
  final String? mangaChapterSort;

  final String? defaultMangaProviderId;
  final String? lastMangaProviderId;

  UserPreferencesModal({
    this.episodesViewMode,
    this.subtitleSettings,
    this.preferDubs,
    this.searchPageListMode,
    this.autoSelectPreviouslyUsedServer,
    this.mangaReaderLayout,
    this.mangaReaderDirection,
    this.mangaReaderZoom,
    this.mangaChapterSort,
    this.defaultMangaProviderId,
    this.lastMangaProviderId,
  });

  factory UserPreferencesModal.fromMap(Map<dynamic, dynamic> map) {
    return UserPreferencesModal(
      episodesViewMode: getViewModeEnum(map['episodesViewMode'] ?? 0),
      subtitleSettings:
          map['subtitleSettings'] != null ? SubtitleSettings.fromMap(map['subtitleSettings']) : SubtitleSettings(),
      preferDubs: map['preferDubs'] ?? false,
      searchPageListMode: map['searchPageListMode'] ?? false,
      autoSelectPreviouslyUsedServer: map['autoSelectPreviouslyUsedServer'] ?? false,
      mangaReaderLayout: map['mangaReaderLayout'] as String?,
      mangaReaderDirection: map['mangaReaderDirection'] as String?,
      mangaReaderZoom: map['mangaReaderZoom'] ?? false,
      mangaChapterSort: map['mangaChapterSort'] as String?,
      defaultMangaProviderId: map['defaultMangaProviderId'] as String?,
      lastMangaProviderId: map['lastMangaProviderId'] as String?,
    );
  }

  factory UserPreferencesModal.defaults() {
    return UserPreferencesModal(
      episodesViewMode: EpisodeViewModes.list,
      preferDubs: false,
      searchPageListMode: false,
      subtitleSettings: SubtitleSettings(),
      autoSelectPreviouslyUsedServer: false,
      mangaReaderLayout: mangaReaderLayoutScroll,
      mangaReaderDirection: 'ltr',
      mangaReaderZoom: false,
      mangaChapterSort: mangaChapterSortDesc,
      defaultMangaProviderId: null,
      lastMangaProviderId: null,
    );
  }

  Map<dynamic, dynamic> toMap() {
    return {
      'episodesViewMode': episodesViewMode != null ? getViewModeIndex(episodesViewMode!) : null,
      'subtitleSettings': subtitleSettings?.toMap(),
      'preferDubs': preferDubs,
      'searchPageListMode': searchPageListMode,
      'autoSelectPreviouslyUsedServer': autoSelectPreviouslyUsedServer,
      'mangaReaderLayout': mangaReaderLayout,
      'mangaReaderDirection': mangaReaderDirection,
      'mangaReaderZoom': mangaReaderZoom,
      'mangaChapterSort': mangaChapterSort,
      'defaultMangaProviderId': defaultMangaProviderId,
      'lastMangaProviderId': lastMangaProviderId,
    };
  }

  /// Paged only when it was explicitly stored as paged. Anything else -- null
  /// on a fresh install, or a value written by a newer build -- reads as the
  /// scroll layout, which is what the reader did before this setting existed.
  bool get mangaReaderPaged => mangaReaderLayout == mangaReaderLayoutPaged;

  /// RTL only when explicitly stored; every other value is left-to-right.
  bool get mangaReaderRightToLeft => mangaReaderDirection == 'rtl';

  /// Ascending only when it was explicitly stored as such. Anything else -- null
  /// on a fresh install -- reads as newest first, which is what the list did
  /// before this setting existed.
  bool get mangaChapterAscending => mangaChapterSort == mangaChapterSortAsc;

  static EpisodeViewModes getViewModeEnum(int modeIndex) {
    switch (modeIndex) {
      case 0:
        return EpisodeViewModes.list;
      case 1:
        return EpisodeViewModes.grid;
      case 2:
        return EpisodeViewModes.tile;
      default:
        throw Exception("Unknown index for episode view mode enum");
    }
  }

  static int getViewModeIndex(EpisodeViewModes mode) {
    switch (mode) {
      case EpisodeViewModes.tile:
        return 2;
      case EpisodeViewModes.grid:
        return 1;
      case EpisodeViewModes.list:
        return 0;
    }
  }
}

class AnimeSpecificPreference {
  final Map? lastWatchDuration;
  final String? manualSearchQuery;
  final String? preferredProvider;
  final String? previouslyUsedServer;
  final String? previouslyUsedServerQuality;

  AnimeSpecificPreference(
      {this.lastWatchDuration,
      this.manualSearchQuery,
      this.preferredProvider,
      this.previouslyUsedServer,
      this.previouslyUsedServerQuality});

  @override
  String toString() =>
      'AnimeSpecificPreference(lastWatchDuration: $lastWatchDuration, manualSearchQuery: $manualSearchQuery, '
      'preferredProvider: $preferredProvider, previouslyUsedServer: $previouslyUsedServer, previouslyUsedServerQuality: $previouslyUsedServerQuality)';

  AnimeSpecificPreference copyWith({
    Map? lastWatchDuration,
    String? manualSearchQuery,
    String? preferredProvider,
    String? previouslyUsedServer,
    String? previouslyUsedServerQuality,
  }) {
    return AnimeSpecificPreference(
      lastWatchDuration: lastWatchDuration ?? this.lastWatchDuration,
      manualSearchQuery: manualSearchQuery ?? this.manualSearchQuery,
      preferredProvider: preferredProvider ?? this.preferredProvider,
      previouslyUsedServer: previouslyUsedServer ?? this.previouslyUsedServer,
      previouslyUsedServerQuality: previouslyUsedServerQuality ?? this.previouslyUsedServerQuality,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lastWatchDuration': lastWatchDuration,
      'manualSearchQuery': manualSearchQuery,
      'preferredProvider': preferredProvider,
      'previouslyUsedServer': previouslyUsedServer,
      'previouslyUsedServerQuality': previouslyUsedServerQuality,
    };
  }

  factory AnimeSpecificPreference.fromMap(Map<String, dynamic> map) {
    return AnimeSpecificPreference(
        lastWatchDuration:
            map['lastWatchDuration'] != null ? Map.from(map['lastWatchDuration'] as Map<dynamic, dynamic>) : null,
        manualSearchQuery: map['manualSearchQuery'] != null ? map['manualSearchQuery'] as String : null,
        preferredProvider: map['preferredProvider'] != null ? map['preferredProvider'] as String : null,
        previouslyUsedServer: map['previouslyUsedServer'] != null ? map['previouslyUsedServer'] as String : null,
        previouslyUsedServerQuality:
            map['previouslyUsedServerQuality'] != null ? map['previouslyUsedServerQuality'] as String : null);
  }

  String toJson() => json.encode(toMap());

  factory AnimeSpecificPreference.fromJson(String source) =>
      AnimeSpecificPreference.fromMap(json.decode(source) as Map<String, dynamic>);
}
