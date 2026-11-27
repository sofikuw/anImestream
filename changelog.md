# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the tags
the release workflow creates.

This file was created empty upstream, so the history below starts here rather
than pretending to cover the fork's earlier life. That history is in the git log.

## [Unreleased]

### Added
- **Faster downloads.** HLS streams now keep eight video segments and four
  audio segments in flight, and direct files are downloaded with eight
  parallel byte ranges written into one file.
- **Batch manga downloads.** The chapters header has a batch button that opens
  a chapter picker: select individual chapters (or all, not-yet-downloaded, or
  inverted) and queue them through the same downloader as the per-chapter
  button.
- **System PiP controls (Android).** Backported upstream's custom PiP actions:
  rewind, play/pause and forward buttons in the system window, auto-enter on
  supported Android versions, and play-state sync. Auto-enter from the mini
  window first swaps in a full-screen video surface, so the system window
  shows the video instead of the floating overlay. The in-app mini window also
  renders subtitles at a smaller size.
- **Background downloads.** An Android foreground service keeps the download
  queue running when you leave the app or close the activity, with a persistent
  notification while files are being fetched.
- **In-app mini player.** Leaving the video page shrinks the episode into a
  floating window, so the rest of the app can be browsed while it keeps
  playing. The window starts larger, pinch-resizes, moves freely up to the top
  of the screen, and settles against the nearest left/right edge when released.
  Only play/pause and close buttons appear, and only after a tap (a second tap
  on the video returns to the full player). Drag more than half of it off a
  side to pause and slide it away; a small, faded arrow at that height brings
  it back when swiped inward. Only the X closes it. Subtitles render inside
  the mini window at a smaller size when enabled. Works for online streams and
  downloaded files.
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
- **Continue Watching opens the episode list.** A card in the Continue Watching
  row now lands on the watch section of the info page instead of the synopsis,
  so resuming takes one tap instead of two. Every other row still opens on the
  synopsis.

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
- **Mini window polish.** The progress bar is no longer tinted by the theme
  accent, mini subtitles scale from the user's subtitle setting, and system PiP
  no longer auto-enters while the mini window is showing (which captured the
  overlay background instead of the video).
- **Downloaded manga shows up on iOS.** Chapters now live under the same
  Downloads root the in-app browser scans, with old `<Documents>/manga`
  chapters still recognised.
- **Mini window stays on screen.** Resizing is clamped to the display width so
  it cannot grow larger than the screen.
- **Manga batch picker labels chapters by number.** Tiles no longer show list
  positions, so a newest-first list cannot make "chapter 1" mean the last
  chapter in the series.
- **Anime info survives a MAL 404.** When MAL has no entry (often an AniList
  id), Kitsu's MAL mapping and Simkl are tried before failing.
- **Upstream beta fixes backported.** The compact episode grid's Watch action
  now uses the real episode index on later pages, Continue Watching stays on
  the last episode after a show is finished, callback notifications are
  ignored after a provider is disposed, concurrent downloads are capped at
  two, and subtitle files are saved with a format detected from their content.
- **ReAnime servers actually play and download.** The MKV file hint is back in
  the download URL, duplicate servers are deduplicated, and the player is
  told the container extension instead of guessing from a HEAD request.
- **Anime details load with MyAnimeList selected.** MAL is a list database, not
  a metadata source, so its positive ids are now resolved through the metadata
  fallback instead of hitting an unimplemented MAL details method.
- **The preferred provider is remembered.** Picking a source on an anime's page
  now records it; the cached value was never updated, so the same preference was
  rewritten on every later visit and readers of it kept seeing the old provider.
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
- **Lower memory use.** The network-response cache is now a lazy Hive box (50
  MB instead of up to 1 GB loaded into RAM), decoded image cache is capped at
  48 MB, card thumbnails are decoded at display size, and metadata caches are
  bounded.
- **iOS beta builds.** The same version is now dispatched for iOS as an
  unsigned IPA, with serial `divergent-ios-v<version>-beta.<build>` tags and
  `#<build>` release titles like Android. The README lists what does not carry
  over: background downloads (Android foreground service), file-intent imports
  and TV/desktop features.
- **README rewritten.** Installation, extension rules and build instructions
  now describe the app as it actually ships, with a logo and badges.
- **Divergence meter.** Every release description opens with how far this fork
  has moved from upstream (`1.<lines moved>%`, Steins;Gate style), and the README
  carries the same number as a badge under the app name. The value is computed
  from git at build time by `scripts/divergence.sh`, and the release workflow
  writes it back into the badge.

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
