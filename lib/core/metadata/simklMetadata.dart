import 'package:animestream/core/database/simkl/simkl.dart';
import 'package:animestream/core/database/simkl/types.dart';
import 'package:animestream/core/metadata/metadataTypes.dart';

/// Simkl as a metadata provider.
///
/// Simkl exposes search and full details, but not the browse feeds the app
/// uses for Discover. Those calls throw so the router can move on to the next
/// configured fallback instead of showing an empty page.
class SimklAnimeMetadata implements AnimeMetadataProvider {
  @override
  String get id => 'simkl';

  @override
  String get name => 'Simkl';

  @override
  Future<List<AnimeMetadataSummary>> search(String query) async {
    final results = await Simkl().search(query);
    return results
        .map(
          (result) => AnimeMetadataSummary(
            source: 'simkl',
            providerId: result.id.toString(),
            title: result.title,
            cover: result.cover,
            totalEpisodes: result.totalEpisodes,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<AnimeMetadataSummary>> trending() => _noBrowseRail();

  @override
  Future<List<AnimeMetadataSummary>> popular() => _noBrowseRail();

  @override
  Future<List<AnimeMetadataSummary>> currentlyAiring() => _noBrowseRail();

  @override
  Future<List<AnimeMetadataSummary>> recentlyUpdated() => _noBrowseRail();

  @override
  Future<List<AnimeMetadataSummary>> recommended() => _noBrowseRail();

  Future<List<AnimeMetadataSummary>> _noBrowseRail() async {
    throw const MetadataUnavailableException(
      'Simkl has no browse feed for this section',
    );
  }

  @override
  Future<AnimeMetadataDetails> details(String providerId) async {
    final id = int.tryParse(providerId);
    if (id == null) {
      throw MetadataUnavailableException('Not a Simkl id: $providerId');
    }
    final info = await Simkl().getAnimeInfo(id);
    final genres = info.genres.whereType<String>().toList(growable: false);
    final summary = AnimeMetadataSummary(
      source: 'simkl',
      providerId: providerId,
      title: info.title,
      cover: info.cover,
      banner: info.banner,
      rating: info.rating == 0 ? null : info.rating,
      totalEpisodes: info.episodes,
      format: info.type,
      status: info.status,
      genres: genres,
    );

    return AnimeMetadataDetails(
      summary: summary,
      synopsis: info.synopsis,
      banner: info.banner,
      genres: genres,
      studios: info.studios.whereType<String>().toList(growable: false),
      duration: info.duration,
      episodes: info.episodes,
      status: info.status,
      type: info.type,
      startDate: info.aired['start'],
      endDate: info.aired['end'],
      rating: summary.rating,
      related: _related(info.related),
      recommended: _related(info.recommended),
      synonyms: info.synonyms.whereType<String>().toList(growable: false),
      characters: info.characters,
    );
  }

  static List<AnimeMetadataSummary> _related(
    List<SimklRelatedRecommendation> items,
  ) {
    return items
        .map(
          (item) => AnimeMetadataSummary(
            source: 'simkl',
            providerId: item.id.toString(),
            title: item.title,
            cover: item.cover,
            rating: item.rating,
            format: item.type,
            relationType: item.relationType,
          ),
        )
        .toList(growable: false);
  }
}
