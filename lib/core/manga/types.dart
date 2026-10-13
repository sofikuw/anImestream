// Normalized manga models.
//
// Division of labour (see mangaProvider.dart):
//   * AniList supplies *metadata* -- titles, covers, synopsis, genres, and the
//     number of chapters.
//   * An installed manga extension supplies the chapter list and the page
//     images.
//
// AniList reports `chapters: 120` as an integer. It never reports a list of
// chapters. Chapter entries are therefore never synthesised from that count:
// with no chapter provider installed the chapter list is empty and the reader
// is unavailable. This is deliberate -- inventing chapter entries from a count
// would be fabricating data.

/// Compact manga record, used for cards in home sections and search results.
class MangaSummary {
  /// AniList media id, or a provider-scoped id. Kept as a String so both fit.
  final String id;

  final String title;
  final String? cover;

  /// 0..10, matching how the anime cards treat AniList averageScore.
  final double? rating;

  /// AniList MediaFormat: MANGA, ONE_SHOT or NOVEL.
  final String? format;

  /// RELEASING, FINISHED, NOT_YET_RELEASED, CANCELLED or HIATUS.
  final String? status;

  /// AniList's chapter *count* -- not a chapter list.
  final int? totalChapters;

  final List<String> genres;

  MangaSummary({
    required this.id,
    required this.title,
    this.cover,
    this.rating,
    this.format,
    this.status,
    this.totalChapters,
    List<String> genres = const <String>[],
  }) : genres = List<String>.unmodifiable(genres);

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'title': title,
        'cover': cover,
        'rating': rating,
        'format': format,
        'status': status,
        'totalChapters': totalChapters,
        'genres': genres,
      };

  factory MangaSummary.fromMap(Map<String, dynamic> map) => MangaSummary(
        id: map['id'].toString(),
        title: map['title'] as String,
        cover: map['cover'] as String?,
        rating: (map['rating'] as num?)?.toDouble(),
        format: map['format'] as String?,
        status: map['status'] as String?,
        totalChapters: (map['totalChapters'] as num?)?.toInt(),
        genres: map['genres'] is List
            ? (map['genres'] as List).whereType<String>().toList()
            : const <String>[],
      );

  @override
  String toString() => 'MangaSummary(id: $id, title: $title)';
}

class MangaCharacter {
  final String name;
  final String? role;
  final String? image;

  MangaCharacter({required this.name, this.role, this.image});
}

class MangaRelation {
  final String id;
  final String title;
  final String? cover;
  final String? type;
  final String? relationType;

  MangaRelation({
    required this.id,
    required this.title,
    this.cover,
    this.type,
    this.relationType,
  });
}

/// Full detail record for the manga details page.
class MangaDetails {
  final MangaSummary summary;
  final String? synopsis;
  final String? banner;

  /// AniList `staff` (manga has authors/artists where anime has studios).
  final List<String> authors;

  final List<MangaCharacter> characters;
  final List<MangaRelation> relations;

  final int? volumes;
  final String? startDate;
  final String? endDate;

  /// Present when the signed-in user has this manga on their AniList list.
  final String? mediaListStatus;
  final int? listId;

  MangaDetails({
    required this.summary,
    this.synopsis,
    this.banner,
    List<String> authors = const <String>[],
    List<MangaCharacter> characters = const <MangaCharacter>[],
    List<MangaRelation> relations = const <MangaRelation>[],
    this.volumes,
    this.startDate,
    this.endDate,
    this.mediaListStatus,
    this.listId,
  })  : authors = List<String>.unmodifiable(authors),
        characters = List<MangaCharacter>.unmodifiable(characters),
        relations = List<MangaRelation>.unmodifiable(relations);

  String get title => summary.title;
  String? get cover => summary.cover;
  int? get totalChapters => summary.totalChapters;
}

/// One readable chapter. Only a [MangaChapterProvider] can produce these.
class MangaChapter {
  /// Provider-scoped id used to resolve this chapter's pages.
  final String id;

  /// Display title, if the source provides one.
  final String? title;

  /// Chapter number. A double because sources use values like 12.5.
  final double? number;

  /// Source-provided scanlation group, when available.
  final String? scanlator;

  MangaChapter({
    required this.id,
    this.title,
    this.number,
    this.scanlator,
  });

  /// Prefers the source title, falling back to the chapter number.
  String get displayTitle {
    if (title != null && title!.trim().isNotEmpty) return title!;
    if (number != null) return 'Chapter ${formatNumber(number!)}';
    return 'Chapter';
  }

  /// Trims a trailing `.0` so 12.0 renders as "12" but 12.5 stays "12.5".
  static String formatNumber(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

/// One page image in a chapter.
class MangaPage {
  /// Zero-based position in the chapter.
  final int index;

  final String imageUrl;

  /// Headers the source requires to fetch the image, when any.
  final Map<String, String>? headers;

  MangaPage({required this.index, required this.imageUrl, this.headers});
}
