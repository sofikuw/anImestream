# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the tags
the release workflow creates.

This file was created empty upstream, so the history below starts here rather
than pretending to cover the fork's earlier life. That history is in the git log.

## [Unreleased]

### Added
- **Built-in manga providers are switchable.** WeebCentral and MangaPill now
  appear under *Built-in providers* next to the built-in anime sources. Turning
  one off hides it from the reader, the source picker and the default-provider
  list; turning it back on restores it. If the disabled provider was the saved
  default (or the last used one), it is replaced with an available source
  instead of being left dangling.
- **Immersive manga reading.** The reader opens with the system bars and its
  own app bar hidden on Android and iOS, with a floating button to bring the
  chrome back (and an app-bar button to go fullscreen again). Desktop layouts
  keep their window chrome.

### Changed
- **Material 3 manga reader controls.** The reader's settings sheet now uses
  segmented buttons for layout and reading direction plus a switch for zoom
  (options that do not apply stay visible but disabled), and the bottom bar is
  a Material surface with a Material slider instead of the hand-painted dot
  track.
- **Zoom improvements.** Pinching now runs up to 5x with boundary margins,
  double-tapping zooms in around the tapped point (double-tap again to reset),
  and every page gets its own transformation so a zoomed page never leaks its
  scale onto the next one.

## [0.3.0] - 2026-10-29

### Added
- **MangaYomi JS extension support.** Full end-to-end support for MangaYomi JS
  extensions including a secure JS runtime bridge, manifest-based installation,
  and content filtering.
- **Manga downloads.** Persistent download support in the Android public Download
  directory with human-readable naming, download history tracking, and direct
  chapter-tapping deep links from the downloads list.
- **Inbuilt Manga providers.** Native Dart implementations of WeebCentral and
  MangaPill added as inbuilt providers, available out-of-the-box without
  requiring JS extension installation.
- **Default manga provider.** A new user preference allows setting a global
  default manga source; the app remembers your last-used provider and resolves
  chapter sources with a reliable priority chain (last used -> default -> first
  installed).
- **AniList rate-limit handling and wider request cache.** GraphQL queries now
  go through a shared rate limiter that reads `x-ratelimit-remaining` /
  `x-ratelimit-reset`, waits for the next slot before spending it, retries a
  429 twice, and then reports the remaining cooldown. Search results are cached
  for 30 minutes, the recently-updated feed for 20 minutes against a 15-minute
  window, list statistics for 4 hours and the signed-in `Viewer` query for 12
  hours.
- **Native audio tracks from the player.** The player now asks the backend
  (better_player, fvp or MDK) which audio tracks the decoder actually exposes
  instead of trusting the HLS playlist's renditions, keeps the previously
  chosen language when switching episodes, and prefers an English track for
  dub streams when "prefer dubs" is on.
