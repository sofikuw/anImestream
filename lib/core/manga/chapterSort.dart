import 'package:animestream/core/manga/types.dart';

/// Chapter ordering, in one place.
///
/// Two screens depend on this agreeing with itself: the chapter list on the
/// manga details page, and the two chapter arrows in the reader. If the reader
/// ordered them differently from the list, "next chapter" would land on
/// something the user never saw next, so both call in here rather than each
/// sorting its own copy.
///
/// Sorted by chapter *number*, not by the order the source returned: a source's
/// order is not guaranteed, and is usually not stable between requests. A
/// chapter with no number -- a one-shot -- is always last in both directions,
/// because there is nothing to place it by and pinning it to one end of a
/// "newest first" list would be a guess dressed up as a decision.
///
/// Returns a copy, so an unmodifiable list from a provider is safe to pass in.
List<MangaChapter> sortChapters(
  List<MangaChapter> chapters, {
  required bool ascending,
}) {
  final sorted = List<MangaChapter>.of(chapters);
  sorted.sort((a, b) {
    final an = a.number;
    final bn = b.number;
    if (an == null && bn == null) return 0;
    if (an == null) return 1;
    if (bn == null) return -1;
    return ascending ? an.compareTo(bn) : bn.compareTo(an);
  });
  return sorted;
}
