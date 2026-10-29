# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the tags
the release workflow creates.

This file was created empty upstream, so the history below starts here rather
than pretending to cover the fork's earlier life. That history is in the git log.

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
