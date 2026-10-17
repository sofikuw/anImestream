# anImestream manga reader patch

Two files in this archive are complete and can be dropped straight in:

| In the archive | Goes to |
| --- | --- |
| `patch/lib/core/manga/chapterSort.dart` | `lib/core/manga/chapterSort.dart` (new file) |
| `patch/lib/ui/pages/mangaReader.dart` | `lib/ui/pages/mangaReader.dart` (replaces the existing file) |

Two more files need small edits rather than replacement, because writing them
out in full would mean transcribing 50 KB of code you already have. Every edit is
listed below as an exact find-and-replace. `types.dart` is 8 edits, all one line
or less; `mangaDetails.dart` is 7, one of which is a two-line insert.

Paths are repo-relative on the `divergent` branch. Note the duplicate files at the
repository root (`mangaDetails.dart`, `types.dart`, `pubspec.yaml`) — the ones
that matter are all under `lib/`.

---

## 1. `lib/core/data/types.dart`

### 1a. Two constants, after `mangaReaderLayoutPaged`

```dart
const String mangaReaderLayoutScroll = 'scroll';
const String mangaReaderLayoutPaged = 'paged';
```

add:

```dart
/// Chapter list order: [mangaChapterSortDesc] (the default, newest first) or
/// [mangaChapterSortAsc]. Strings for the same reason the reader layout is:
/// these are written straight into the Hive map, and a stored value with no
/// matching enum constant would throw on read.
const String mangaChapterSortDesc = 'desc';
const String mangaChapterSortAsc = 'asc';
```

### 1b. A field in `UserPreferencesModal`, after `mangaReaderZoom`

```dart
  final bool? mangaReaderZoom;
```

add:

```dart
  /// Chapter list order on the manga details page: [mangaChapterSortDesc] for
  /// newest first (the default), [mangaChapterSortAsc] for oldest first.
  final String? mangaChapterSort;
```

### 1c. The constructor parameter, after `this.mangaReaderZoom,`

```dart
    this.mangaReaderZoom,
  });
```

becomes:

```dart
    this.mangaReaderZoom,
    this.mangaChapterSort,
  });
```

### 1d. `fromMap`, after `mangaReaderZoom`

```dart
      mangaReaderZoom: map['mangaReaderZoom'] ?? false,
```

becomes:

```dart
      mangaReaderZoom: map['mangaReaderZoom'] ?? false,
      mangaChapterSort: map['mangaChapterSort'] as String?,
```

### 1e. `defaults()`, after `mangaReaderZoom`

```dart
      mangaReaderZoom: false,
    );
```

becomes:

```dart
      mangaReaderZoom: false,
      mangaChapterSort: mangaChapterSortDesc,
    );
```

### 1f. `toMap`, after `mangaReaderZoom`

```dart
      'mangaReaderZoom': mangaReaderZoom,
    };
```

becomes:

```dart
      'mangaReaderZoom': mangaReaderZoom,
      'mangaChapterSort': mangaChapterSort,
    };
```

### 1g. A getter, after `mangaReaderRightToLeft`

```dart
  bool get mangaReaderRightToLeft => mangaReaderDirection == 'rtl';
```

add:

```dart
  /// Ascending only when it was explicitly stored as such. Anything else -- null
  /// on a fresh install -- reads as newest first, which is what the list did
  /// before this setting existed.
  bool get mangaChapterAscending => mangaChapterSort == mangaChapterSortAsc;
```

`UserPreferences` itself needs no change: `saveUserPreferences` merges only
non-null keys, so the toggle saves a one-field modal without disturbing anything
else.

---

## 2. `lib/ui/pages/mangaDetails.dart`

### 2a. Two imports, after the `flutter/material.dart` import

```dart
import 'package:flutter/material.dart';
```

add:

```dart
import 'package:animestream/core/data/preferences.dart';
import 'package:animestream/core/manga/chapterSort.dart';
```

### 2b. A state field, after `_lastReadChapter`

```dart
  double? _lastReadChapter;
```

add:

```dart
  /// Chapter list order, read from preferences once in [load] and flipped by the
  /// toggle in the section header. Held in state as well as in preferences so the
  /// list can be re-sorted without another round trip.
  bool _chaptersAscending = false;
```

### 2c. `load()` reads the preference, after the details call

```dart
      final details = await _source.getDetails(widget.id);
```

becomes:

```dart
      final details = await _source.getDetails(widget.id);
      final prefs = await UserPreferences.getUserPreferences();
```

and inside the existing `setState`:

```dart
        _details = details;
        _provider = provider;
```

becomes:

```dart
        _details = details;
        _chaptersAscending = prefs.mangaChapterAscending;
        _provider = provider;
```

### 2d. `loadChapters` sorts what it stores

```dart
        _chapters = chapters;
```

becomes:

```dart
        _chapters = sortChapters(chapters, ascending: _chaptersAscending);
```

### 2e. The toggle in the "Chapters" header row

```dart
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.only(left: 20),
                        child: Text(
                          "Chapters",
```

becomes:

```dart
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: EdgeInsets.only(left: 20),
                        child: Text(
                          "Chapters",
```

and after the closing `),` of that label `Container`, inside the same `children:`

```dart
                        ),
                      ),
                    ],
                  ),
```

becomes:

```dart
                        ),
                      ),
                      _chapterSortToggle(),
                    ],
                  ),
```

### 2f. Two new methods, under `_searchStatus`

```dart
  /// The anime page shows its matched source here; this shows the extension
  /// the chapters came from, or why there are none.
  Widget _searchStatus(MangaChapterProvider? provider, MangaDetails details) {
```

add immediately before it:

```dart
  /// Newest-first / oldest-first for the chapter list.
  ///
  /// At the top of the list rather than buried in the app's settings because it
  /// is as much a fact about *this* manga as about the user: a 900-chapter
  /// series wants newest first, a 40-chapter one you are reading from the start
  /// wants the chapter you are on within reach. The choice is still remembered
  /// globally, so it does not have to be re-made for every title.
  Widget _chapterSortToggle() {
    final ascending = _chaptersAscending;
    return Padding(
      padding: EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _toggleChapterSort,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ascending ? "Oldest first" : "Newest first",
                style: TextStyle(
                  fontFamily: "NotoSans",
                  fontSize: 13,
                  color: appTheme.textSubColor,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: appTheme.accentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Flips the order, remembering it.
  ///
  /// Re-sorted in place rather than re-fetched: the ordering is the only thing
  /// that changed, and a round trip to the source for the same list would make
  /// the toggle feel like a reload.
  Future<void> _toggleChapterSort() async {
    final ascending = !_chaptersAscending;
    setState(() {
      _chaptersAscending = ascending;
      _chapters = sortChapters(_chapters, ascending: ascending);
    });
    await UserPreferences.saveUserPreferences(
      UserPreferencesModal(
        mangaChapterSort:
            ascending ? mangaChapterSortAsc : mangaChapterSortDesc,
      ),
    );
  }

```

### 2g. Hand the reader the chapters, in the row's `onTap`

```dart
                            builder: (context) => MangaReaderPage(
                              manga: details,
                              chapter: chapter,
                              provider: _provider!,
                            ),
```

becomes:

```dart
                            builder: (context) => MangaReaderPage(
                              manga: details,
                              chapter: chapter,
                              provider: _provider!,
                              // Reading order, not the list's order: the reader's
                              // arrows must step through the story, so index + 1
                              // has to be the chapter after this one even when
                              // the list above is sorted newest first.
                              chapters: sortChapters(_chapters, ascending: true),
                            ),
```

---

## 3. Two behaviour changes in the replaced `mangaReader.dart`

Worth knowing, because they are not additions:

1. **Right-to-left now uses `PageView.reverse`** instead of reversing the page
   list. The old `_orderedPages` getter put the last page of the chapter at index
   0, so paged mode opened on the *last* page. Verify on a device with an RTL
   manga before trusting it.
2. **The old `"3 / 20"` overlay in paged mode is gone.** That readout now lives
   under the scrubber, so there is one page counter rather than two.

## Not in here

The Android half of the release workflow, and any change to `build-ios.yml` —
neither is touched by this patch. `lib/pubspec.yaml` is also untouched: it is a
byte-identical stray copy that nothing reads.
