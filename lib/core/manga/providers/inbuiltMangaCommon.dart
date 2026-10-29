// Shared helpers for the manga sources compiled into the app.
//
// The inbuilt sources mirror the JavaScript extensions in
// anImestream-extensions (`weebcentral.js`, `mangapill.js`): both sites are
// server-rendered, so the work is the same -- search by title, score the
// candidates on their slug, then read the chapter and page anchors. Keeping
// that logic here means the two sources cannot drift apart on the parts that
// are not site-specific.

import 'package:html/dom.dart';

/// Lower-cases and drops everything that is not a letter or digit.
///
/// AniList titles and site slugs differ in punctuation, not wording:
/// "Kaguya-sama: Love Is War" and "kaguya-sama-love-is-war" normalise to the
/// same value, which is what makes an exact match a reliable signal.
String normalizeMangaTitle(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

/// Collapses runs of whitespace and trims, for anchor labels.
String collapseWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The `href` of [anchor], resolved against [base], or null when it is absent.
///
/// Absolute links and protocol-relative links both appear in the wild, so the
/// result is always an absolute https URL.
String? resolvedHref(Element anchor, String base) {
  final raw = anchor.attributes['href']?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('//')) return 'https:$raw';
  if (raw.startsWith('http')) return raw;
  if (raw.startsWith('/')) return '$base$raw';
  return '$base/$raw';
}

/// Splits [path] into its non-empty segments, so callers can match on
/// `/series/<id>/<slug>` without caring about a leading slash or a query.
List<String> pathSegments(String path) {
  return path.split('/').where((segment) => segment.isNotEmpty).toList();
}

/// Picks the candidate whose slug (or name) best matches [title].
///
/// Exact match first, then a containment match in either direction, then the
/// first candidate -- the same ranking the JavaScript extensions use, so the
/// inbuilt and installed variants resolve a title to the same series.
T? pickBestMangaMatch<T>(
  List<T> candidates,
  String title, {
  required String Function(T candidate) slugOf,
  required String Function(T candidate) nameOf,
}) {
  if (candidates.isEmpty) return null;
  final wanted = normalizeMangaTitle(title);
  if (wanted.isEmpty) return candidates.first;

  for (final candidate in candidates) {
    final slug = normalizeMangaTitle(slugOf(candidate));
    final name = normalizeMangaTitle(nameOf(candidate));
    if (slug == wanted || name == wanted) return candidate;
  }
  for (final candidate in candidates) {
    final slug = normalizeMangaTitle(slugOf(candidate));
    final name = normalizeMangaTitle(nameOf(candidate));
    if ((slug.isNotEmpty && (slug.contains(wanted) || wanted.contains(slug))) ||
        (name.isNotEmpty && (name.contains(wanted) || wanted.contains(name)))) {
      return candidate;
    }
  }
  return candidates.first;
}

/// The chapter number named in [label], if any ("Chapter 12.5" -> 12.5).
double? chapterNumberFromLabel(String label) {
  final match = RegExp(r'(?:chapter|episode|ch\.?)\s*([0-9]+(?:\.[0-9]+)?)', caseSensitive: false)
      .firstMatch(label);
  return _parsePositive(match?.group(1));
}

/// Same as [chapterNumberFromLabel], but falls back to a number embedded in the
/// chapter path (".../chapter-364.2/..."), which MangaPill uses.
double? chapterNumberFromPath(String path) {
  final match = RegExp(r'chapter-([0-9]+(?:\.[0-9]+)?)', caseSensitive: false).firstMatch(path);
  return _parsePositive(match?.group(1));
}

double? _parsePositive(String? raw) {
  if (raw == null) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

/// Sorts chapters by number ascending, with unnumbered entries last.
///
/// Sorting here rather than in the page keeps the picker's own ascending /
/// descending toggle the only ordering concern in the UI.
void sortChaptersByNumber<T>(List<T> chapters, double? Function(T chapter) numberOf) {
  chapters.sort((left, right) {
    final a = numberOf(left) ?? double.maxFinite;
    final b = numberOf(right) ?? double.maxFinite;
    return a.compareTo(b);
  });
}
