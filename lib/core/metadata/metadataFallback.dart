import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/database/anilist/types.dart';
import 'package:animestream/core/database/database.dart';
import 'package:animestream/core/database/types.dart';
import 'package:animestream/core/manga/types.dart';
import 'package:animestream/core/metadata/kitsuMetadata.dart';
import 'package:animestream/core/metadata/malMetadata.dart';
import 'package:animestream/core/metadata/metadataTypes.dart';

/// Reads the provider-related settings once per call so a settings change takes
/// effect on the next request without a restart.
class MetadataSettings {
  const MetadataSettings._();

  static List<String> get _disabled =>
      currentUserSettings?.disabledMetadataProviders ?? const <String>[];

  static bool isEnabled(String source) => !_disabled.contains(source);

  static bool get anilistEnabled => isEnabled('anilist');

  /// The user's fallback order, filtered to providers that still exist and are
  /// still enabled. An empty list means "no fallback".
  static List<String> get fallbackOrder {
    final configured = currentUserSettings?.metadataFallbacks;
    final order = configured ?? const <String>['mal', 'kitsu'];
    return order.where(isEnabled).toList(growable: false);
  }
}

class _AnimeFallbackEntry {
  final String source;
  final String providerId;

  const _AnimeFallbackEntry(this.source, this.providerId);
}

/// Routes anime metadata to AniList's fallbacks and owns the app-local ids
/// that let fallback results travel through the existing int-id UI.
///
/// AniList ids are positive; fallback ids are negative. For MAL and Kitsu the
/// negative id is a deterministic encoding of the provider id, so a local
/// watch-history row still resolves after a restart. A registry covers any
/// provider id that is not numeric, though both current providers use numbers.
class AnimeMetadataRouter {
  AnimeMetadataRouter._();

  static final AnimeMetadataRouter instance = AnimeMetadataRouter._();

  final Map<String, AnimeMetadataProvider> _providers =
      <String, AnimeMetadataProvider>{
    'mal': MalAnimeMetadata(),
    'kitsu': KitsuAnimeMetadata(),
  };

  /// Kitsu ids are packed below this offset so a negative id can be decoded
  /// after a restart. MAL ids are simply negated: AniList ids are positive, so
  /// the two ranges cannot collide.
  static const int _kitsuOffset = 1000000000;

  final Map<int, _AnimeFallbackEntry> _entries = <int, _AnimeFallbackEntry>{};
  final Map<String, int> _ids = <String, int>{};
  int _nextId = -2000000000;

  List<AnimeMetadataProvider> get _enabled {
    final found = <AnimeMetadataProvider>[];
    for (final source in MetadataSettings.fallbackOrder) {
      final provider = _providers[source];
      if (provider != null) found.add(provider);
    }
    return found;
  }

  bool get anilistEnabled => MetadataSettings.anilistEnabled;

  /// Negative ids are fallback ids. They are deterministic for numeric
  /// provider ids, which matters because a local watch-history row outlives the
  /// in-memory registry.
  bool isFallbackId(int id) => id < 0;

  int _idFor(AnimeMetadataSummary summary) {
    final raw = int.tryParse(summary.providerId);
    if (raw != null && raw > 0) {
      return summary.source == 'mal' ? -raw : -_kitsuOffset - raw;
    }

    final key = '${summary.source}:${summary.providerId}';
    final existing = _ids[key];
    if (existing != null) return existing;
    final id = _nextId--;
    _ids[key] = id;
    _entries[id] = _AnimeFallbackEntry(summary.source, summary.providerId);
    return id;
  }

  Future<List<AnimeMetadataSummary>> _firstList(
    Future<List<AnimeMetadataSummary>> Function(AnimeMetadataProvider provider)
        fetch,
  ) async {
    Object? lastError;
    var sawEmpty = false;
    for (final provider in _enabled) {
      try {
        final result = await fetch(provider);
        if (result.isNotEmpty) return result;
        // An empty rail is not an answer: try the next provider before giving
        // up. A genuinely empty search still returns [] below.
        sawEmpty = true;
      } catch (err) {
        lastError = err;
        Logs.app.log('[metadata] ${provider.id} request failed: $err');
      }
    }
    if (sawEmpty) return const <AnimeMetadataSummary>[];
    throw MetadataUnavailableException(
      'AniList is unavailable and no metadata fallback answered.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }

  Future<List<AnilistSearchResult>> search(String query) async {
    final list = await _firstList((provider) => provider.search(query));
    return list.map(_toSearchResult).toList(growable: false);
  }

  Future<List<TrendingResult>> trending() async {
    final list = await _firstList((provider) => provider.trending());
    return list
        .map(
          (summary) => TrendingResult(
            id: _idFor(summary),
            banner: summary.banner,
            cover: summary.cover,
            genres: summary.genres,
            rating:
                summary.rating == null ? null : (summary.rating! * 10).round(),
            title: summary.title,
          ),
        )
        .toList(growable: false);
  }

  Future<List<CurrentlyAiringResult>> currentlyAiring() async {
    final list = await _firstList((provider) => provider.currentlyAiring());
    return list
        .map(
          (summary) => CurrentlyAiringResult(
            cover: summary.cover,
            id: _idFor(summary),
            status: summary.status ?? '',
            title: summary.title,
            rating: summary.rating,
            episodes: summary.totalEpisodes,
            watchProgress: null,
          ),
        )
        .toList(growable: false);
  }

  Future<List<RecentlyUpdatedResult>> recentlyUpdated() async {
    final list = await _firstList((provider) => provider.recentlyUpdated());
    return list
        .map(
          (summary) => RecentlyUpdatedResult(
            episode: 0,
            title: summary.title,
            id: _idFor(summary),
            type: summary.format ?? 'ANIME',
            banner: summary.banner,
            cover: summary.cover,
            genres: summary.genres,
            releaseStatus: summary.status ?? '',
            rating:
                summary.rating == null ? null : (summary.rating! * 10).round(),
          ),
        )
        .toList(growable: false);
  }

  Future<List<AnilistRecommendations>> recommended() async {
    final list = await _firstList((provider) => provider.recommended());
    return list
        .map(
          (summary) => AnilistRecommendations(
            cover: summary.cover,
            id: _idFor(summary),
            title: summary.title,
            rating: summary.rating,
          ),
        )
        .toList(growable: false);
  }

  AnilistSearchResult _toSearchResult(AnimeMetadataSummary summary) {
    return AnilistSearchResult(
      cover: summary.cover,
      id: _idFor(summary),
      idMal:
          summary.source == 'mal' ? int.tryParse(summary.providerId) : null,
      title: summary.title,
      rating: summary.rating,
      totalEpisodes: summary.totalEpisodes,
    );
  }

  Future<AnilistInfo> info(int id) async {
    String? source;
    String? providerId;

    // Registry entries first: a non-numeric provider id uses a synthetic slot
    // that must not be decoded as a MAL id.
    final entry = _entries[id];
    if (entry != null) {
      source = entry.source;
      providerId = entry.providerId;
    } else if (id <= -_kitsuOffset) {
      source = 'kitsu';
      providerId = (-(id + _kitsuOffset)).toString();
    } else if (id < 0) {
      source = 'mal';
      providerId = (-id).toString();
    }

    if (source == null || providerId == null) {
      throw MetadataUnavailableException('Unknown fallback id: $id');
    }
    final provider = _providers[source];
    if (provider == null) {
      throw MetadataUnavailableException('Unknown fallback provider: $source');
    }
    return _toInfo(await provider.details(providerId));
  }

  AnilistInfo _toInfo(AnimeMetadataDetails details) {
    final summary = details.summary;
    final alternate = <AlternateDatabaseId>[];
    if (summary.source == 'mal') {
      final malId = int.tryParse(summary.providerId);
      if (malId != null) {
        alternate.add(AlternateDatabaseId(database: Databases.mal, id: malId));
      }
    }

    return AnilistInfo(
      aired: <String, String>{
        'start': details.startDate ?? '',
        'end': details.endDate ?? '',
      },
      banner: details.banner ?? summary.banner,
      characters: const <Map<String, dynamic>>[],
      cover: summary.cover,
      duration: details.duration ?? '??',
      episodes: details.episodes ?? summary.totalEpisodes,
      genres: details.genres,
      mediaListStatus: null,
      nextAiringEpisode: (airingAt: '', timeLeft: '', episode: ''),
      rating: details.rating ?? summary.rating,
      recommended: _toRelated(details.recommended),
      related: _toRelated(details.related),
      status: details.status ?? summary.status,
      studios: details.studios,
      synonyms: details.synonyms,
      synopsis: details.synopsis,
      tags: const <String>[],
      title: summary.title,
      type: details.type ?? summary.format ?? 'ANIME',
      alternateDatabases: alternate,
      listId: null,
    );
  }

  List<AnilistAnimeRelatedRecommendation> _toRelated(
    List<AnimeMetadataSummary> list,
  ) {
    return list
        .map(
          (summary) => AnilistAnimeRelatedRecommendation(
            cover: summary.cover,
            id: _idFor(summary),
            rating: summary.rating,
            title: summary.title,
            type: summary.format ?? 'ANIME',
          ),
        )
        .toList(growable: false);
  }
}

/// Routes manga metadata to the same fallback providers.
///
/// Manga ids are already strings, so the prefix is the id: "mal:123" and
/// "kitsu:456". No registry is needed, and a fallback manga id stays readable
/// in a Hive row after a restart.
class MangaMetadataRouter {
  MangaMetadataRouter._();

  static final MangaMetadataRouter instance = MangaMetadataRouter._();

  final Map<String, MangaMetadataProvider> _providers =
      <String, MangaMetadataProvider>{
    'mal': MalMangaMetadata(),
    'kitsu': KitsuMangaMetadata(),
  };

  bool get anilistEnabled => MetadataSettings.anilistEnabled;

  List<MangaMetadataProvider> get _enabled {
    final found = <MangaMetadataProvider>[];
    for (final source in MetadataSettings.fallbackOrder) {
      final provider = _providers[source];
      if (provider != null) found.add(provider);
    }
    return found;
  }

  Future<List<MangaSummary>> _firstList(
    Future<List<MangaSummary>> Function(MangaMetadataProvider provider) fetch,
  ) async {
    Object? lastError;
    var sawEmpty = false;
    for (final provider in _enabled) {
      try {
        final result = await fetch(provider);
        if (result.isNotEmpty) return result;
        sawEmpty = true;
      } catch (err) {
        lastError = err;
        Logs.app.log('[metadata] ${provider.id} manga request failed: $err');
      }
    }
    if (sawEmpty) return const <MangaSummary>[];
    throw MetadataUnavailableException(
      'AniList is unavailable and no manga metadata fallback answered.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }

  Future<List<MangaSummary>> search(String query) =>
      _firstList((provider) => provider.search(query));

  Future<List<MangaSummary>> trending() =>
      _firstList((provider) => provider.trending());

  Future<List<MangaSummary>> popular() =>
      _firstList((provider) => provider.popular());

  Future<List<MangaSummary>> latest() async {
    final enabled = _enabled;
    final kitsu = <MangaMetadataProvider>[];
    final rest = <MangaMetadataProvider>[];
    for (final provider in enabled) {
      if (provider.id == 'kitsu') {
        kitsu.add(provider);
      } else {
        rest.add(provider);
      }
    }
    Object? lastError;
    var sawEmpty = false;
    for (final provider in <MangaMetadataProvider>[...kitsu, ...rest]) {
      try {
        final result = await provider.latest();
        if (result.isNotEmpty) return result;
        sawEmpty = true;
      } catch (err) {
        lastError = err;
        Logs.app.log('[metadata] ${provider.id} manga latest failed: $err');
      }
    }
    if (sawEmpty) return const <MangaSummary>[];
    throw MetadataUnavailableException(
      'AniList is unavailable and no manga metadata fallback answered.'
      '${lastError == null ? '' : ' Last error: $lastError'}',
    );
  }

  Future<MangaDetails> details(String id) async {
    final separator = id.indexOf(':');
    if (separator <= 0 || separator == id.length - 1) {
      throw MetadataUnavailableException('Not a fallback manga id: $id');
    }
    final source = id.substring(0, separator);
    final providerId = id.substring(separator + 1);
    final provider = _providers[source];
    if (provider == null) {
      throw MetadataUnavailableException('Unknown fallback provider: $source');
    }
    return provider.details(providerId);
  }
}
