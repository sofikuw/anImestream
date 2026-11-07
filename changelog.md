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
- **Batch downloads.** Every episode can be queued at once from the info page,
  with a chosen quality and dub/sub audio track per episode.
- **Split audio downloads.** The downloader now fetches the video and the
  chosen audio rendition separately and muxes both into the MKV, so dub tracks
  are preserved instead of lost during remuxing.
- **Discord Rich Presence.** The current anime episode or manga chapter is
  shown on the Discord profile, with the app name and icon, an elapsed timer
  and a working sign-in flow.

### Changed
- **Reader chrome stays as 1.0 designed it.** The dot-track bottom bar and the
  always-available app bar were kept; only tap-to-toggle fullscreen and the
  paged pinch/double-tap zoom were added on top.
- **Zoom improvements.** Pinching now runs up to 5x with boundary margins,
  double-tapping zooms in around the tapped point (double-tap again to reset),
  and every page gets its own transformation so a zoomed page never leaks its
  scale onto the next one.
- **One HLS parser.** Playback extraction, batch quality detection and
  downloads share the new `hlsParser`; playlist URIs and attributes are
  resolved correctly instead of being string-patched.
- **Track switching no longer races the playlist.** Audio and quality changes
  wait (briefly) for the player to finish parsing the manifest, so the Android
  audio-track list is populated instead of permanently empty.
- **One metadata list.** *Metadata* and *Metadata fallbacks* are merged into a
  single section with AniList, MyAnimeList, Kitsu and Simkl. Every enabled
  source can answer search and details; when AniList is unavailable the app
  falls through the enabled sources automatically.

### Fixed
- **Metadata fallbacks stay usable without AniList.** Choosing MyAnimeList or
  Simkl as the database now routes search and details through that provider
  instead of hitting an unimplemented path, and the provider list can fall
  through MAL, Kitsu and Simkl in order.
- **Fallback related and recommended cards open the right page.** Fallback
  entries are marked as anime or manga instead of reusing the media format, so
  MAL/Kitsu recommendations no longer open the manga reader by mistake.
- **Kitsu details are complete.** The info page now shows characters, related
  adaptations (including the source manga) and recommendations, using Kitsu's
  mappings to fill the recommendation rail from MyAnimeList.
- **Anime and manga relations cross over.** MAL exposes `related_manga` on
  anime and `related_anime` on manga but always returns them empty; both types
  are now shown anyway, filling the missing half through Kitsu's MAL mapping.
  Tapping a relation opens the matching reader instead of a wrong-id page.
- **Manga recommendations exist.** MAL and Kitsu manga details now fill a
  recommendation rail (MAL directly, Kitsu through its MAL mapping), and
  AniList manga pages request recommendations as well. Cards with no rating
  hide the star badge instead of showing `??`.
- **Opening a manga no longer creates a Downloads folder.** The downloader
  builds the chapter path lazily, so the empty
  `Download/animestream/manga/<title>_<id>` tree appears only when a chapter is
  actually downloaded.
- **Unified Discord cards.** Anime and manga presence now use the same activity
  type and timestamp format, so both show an elapsed timer and the app icon.

### Removed
- **APK bridge.** The Aniyomi-style `ApkBridge` settings page and the bridge
  provider are gone; it never worked without a native extension loader.
- **MangaYomi extensions.** The MangaYomi catalog parser, JavaScript shim and
  runtime bridge were removed. Only anImestream's own manifest format is
  supported.
- **Seanime manga provider.** Unused provider implementation deleted.

### Changed
- **README rewritten.** Installation, extension rules and build instructions
  now describe the app as it actually ships, with a logo and badges.

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
