# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the tags
the release workflow creates.

This file was created empty upstream, so the history below starts here rather
than pretending to cover the fork's earlier life. That history is in the git log.

## [Unreleased]

### Added
- **Android, alongside iOS, from the same `android/` source.** The repository had
  no Android platform folder at all -- it was created as an iOS fork, and
  Flutter's platform folders are per-platform. It is now published by the staging
  val, fetched from `frostnova721/animestream` at request time
  (`androidPlatform.ts`) rather than staged, because it is ~60 files of mostly
  binary resources that upstream maintains. `/contents.txt` reports the upstream
  commit it came from, so drift is visible. `build-android.yml` builds release
  APKs -- universal and per-ABI -- on the same branch, tag and release-channel
  scheme `build-ios.yml` uses, with its own `android-` tag prefix so an APK tag
  can never be mistaken for an IPA tag.

  The Dart source needed no work for this, and that is worth recording: the fork
  never stripped Android from `lib/`. `Platform.isAndroid` is threaded through 25
  files -- the downloader, the updater, the player, the card grids, the
  navigation -- and `packages/better_player` keeps its Android controller. What
  was missing was the *build*, not the behaviour. Feature parity is therefore the
  default, not an achievement.



- **`stage-q`: the AniList half of Continue Reading.** A `mutateMangaList` in
  `core/database/handler/syncHandler.dart`, and the call to it from
  `storeReading`.

- **Configurable built-in providers and AniList metadata fallbacks.** Settings
  now has a "Built-in providers" page that hides the streaming providers that
  ship with the app and can disable metadata databases. AniList's anime and
  manga search/browse calls fall back to MyAnimeList and then Kitsu (the pair
  can be toggled per provider) when AniList is unavailable; fallback cards open
  a details page through the same providers. Fallback anime ids are negative
  and deterministic, so a saved reading/watching row still resolves after a
  restart. **Not verified on device** -- the SDK is not available here. MAL's
  anime *search* endpoint was also returning its own maintenance error during
  verification; the chain then uses Kitsu, whose search and browse endpoints
  were reachable.

### Fixed

- **Fallback ratings are rounded to one decimal.** Kitsu reports values like
  `84.37`, which the UI rendered as `8.437` instead of `8.4`; MAL can
  return two decimals as well. Anime and manga ratings from both
  providers are normalized before they reach the cards and detail pages.
- **Kitsu browse requests no longer ask for 25 items.** Kitsu rejects page
  sizes above 20 with HTTP 400, so every anime and manga browse fallback
  failed and Discover still reported AniList as unreachable while Kitsu
  was healthy. Browse limits are now 20; verified against Kitsu's API.
- **Discover and Search degrade honestly when AniList is unavailable.** AniList
  can return `403` with "The AniList API has been temporarily disabled due to
  severe stability issues." Discover used to keep its spinners running and
  re-run the failed load whenever the tab was reopened; Search used to present a
  failed lookup as "no matches". Discover now shows an error banner with Retry,
  Search says which half failed, and the four Discover rails load independently
  so one failure no longer discards the other three. **Not verified on device**
  -- the SDK is not available here, and the outage itself is server-side.
- **Android manga rails reserve room for the format label.** The rail is 220px
  on mobile, which is sized for a cover, margin and two title lines; a card with
  a `subText` needs one more line, so the label was clipped. Cards carrying a
  `subText` now get a 245px rail. The trending banner's text block also became
  `Flexible`, so it cannot overflow a narrow screen.
- **Removed a `setState()` from `MainNavigator.build`.** It rebuilt the Discover
  rails on every build while they were non-empty, which is both a build-phase
  `setState()` and a rebuild loop. The provider clears and refills its lists on
  refresh instead.

- **Continue Reading now reaches AniList.** `storeReading` wrote the local Hive
  row and nothing else, so reading progress never left the device. The new
  `mutateMangaList` is **AniList-only on purpose**: `mutateAnimeList` fans out
  over every database plus each of `otherIds`, so pointed at a manga it would
  post reading progress to MAL and Simkl, neither of which carries manga
  entries — those writes would fail, or worse, succeed against a colliding id.

  Two properties worth keeping: the local write stays unconditional and happens
  *first*, because the Home rail reads the local box for signed-in and
  signed-out users alike; and a chapter number is floored, because AniList's
  `progress` is an int while half chapters are real in manga.

  ⚠️ **Unverified on device.** The sync refuses a non-numeric id and logs the
  refusal rather than sending it, so if `storeReading` is handed a *provider* id
  (MangaDex's, Ragnarok's) instead of AniList's own manga id, nothing syncs and
  the app log is the only place that says so. Confirm by opening a chapter and
  reading the log.
- **The `Mangas/Novels arent supported` patch is gone, and so are the other
  three.** Upstream implemented all four of the `oversized.ts` edits to
  `lib/ui/pages/info/infoMobile.dart` themselves, which also fixes the archive
  route that had been 500ing since upstream moved. Keeping them would have been
  worse than useless: edit 1's anchor still matches upstream's import line, so
  applying it would have inserted a duplicate import.

### Changed

- **`oversized.ts` is now empty, on purpose.** The `/grep` evidence for why is
  recorded in the file, along with the rules for re-adding a target. The
  mechanism is kept — the size ceiling is real — but a derived file is only
  justified while it differs from upstream.
- **`pushToGithub.ts` pushes a list of stages** instead of one hardcoded stage,
  in the same merge order `main.ts` uses, so a new stage lands with the same Run.
  It writes to the **`divergent` branch only** — `master` is the
  upstream-tracking branch and stays that way.

### Known issues — not fixed yet

Carried forward deliberately. None of these are regressions from the changes
below; they were already true of the build this one replaces.

- **Chapter numbering starts from the source's own labels.** MangaDex leaves
  `chapter` empty for one-shots, so a row can render a bare `Chapter` with no
  number. Wanted format is `Chapter N: Name`, with N derived from sorted
  position so gaps do not leave holes.
- **A stray flat duplicate sits at the repository root** —
  `ui/models/widgets/cards/animeCardExtended.dart`, with no `lib/` prefix. Dart
  never compiles it because it is outside `lib/`, but it is stale copy of a file
  that has since changed. Remove it with `git rm -r ui/`.
- **A dead page is still in the tree** — `lib/ui/pages/manga.dart`, the removed
  manga tab. Nothing routes to it; its Trending/Popular rails now live on
  Discover.
- **Verified-provider coverage is thin.** The extension catalog's sources were
  each exercised against the live site through a harness enforcing the runtime's
  limits (exact host allowlist, HTTPS only, no redirects, 1 MiB response cap),
  but that is a snapshot: a source can change its markup at any time, and
  nothing here detects that.
- **Dart is not compiled in the staging val.** Type errors surface only in CI,
  so a change that looks complete may still fail the build.

## [0.1.0] — first divergent release

The build stops tracking upstream and ships as an app in its own right.

### Added

- **A `divergent` branch.** `master` keeps the build the repository already had;
  `divergent` is the standalone one. Its identity — display name, iOS bundle id
  — lives in `branches/divergent/identity.env` and is applied to the working tree
  by `branches/apply-identity.sh` at build time, rather than committing the
  bundle-id change into a ~90KB generated `project.pbxproj` that every upstream
  merge would conflict in. See `branches/README.md`.
- **A random tag and a GitHub Release on every manual run** of the build
  workflow, with a `release_channel` input (`stable`, `prerelease`, `beta`,
  `alpha`). The tag carries a random 8-hex-character suffix, so the workflow can
  be run repeatedly at one version. Non-stable channels publish as prereleases.
- **An icon for the divergent branch** — the original artwork with a crack
  overlay, rendered by the staging val at `/icon/divergent-logo.png`.
- **A branch-derived artifact name and tag prefix.** A `divergent` build uploads
  `anImestream-divergent-ios-unsigned` and tags `divergent-v…`; `master` keeps the
  names it already shipped. Both come from the branch name, so there is no second
  list to keep in step.

### Changed

- **The app is now `anImestream-divergent`.** The `divergent` branch sets the
  iOS display name to `anImestream-divergent` and the bundle id to
  `divergent.sofikuw.anImestream`, written into `ios/**/project.pbxproj` and
  `ios/**/Info.plist` at build time. `RunnerTests` keeps its `.RunnerTests`
  suffix.
- **`README.md`** rewritten around the standalone build: what the two branches
  are, how to trigger a release, what the release channels do.
- **The version's build number is optional again.** `pubspec.yaml` may carry
  `version: 1.0.6` with no `+build` suffix; the workflow used to fail the whole
  build over that missing display-only number, and now defaults it to 0.
- **The pushed-tag check is gone.** It asserted that a pushed tag equalled
  `v$VERSION` exactly, which stopped being true the moment tags gained a random
  suffix.

### Fixed

- **Manga, as a first-class content type.** Extension-backed manga reading,
  merged anime and manga search, manga rails on Discover, a vertical-scroll
  reader with layout/direction/zoom settings, and a Continue Reading rail on
  Home.
- **The `Mangas/Novels arent supported` refusal is gone.** Tapping a manga
  relation on an anime info page used to refuse instead of opening it.

### Notes

- The workflow does **not** run `flutter_launcher_icons` or
  `flutter_native_splash`; changing an icon in `branches/<name>/icon/` means
  regenerating the `AppIcon` set locally and committing it.
- Changing the bundle id does **not** change the app's OAuth redirect schemes,
  so AniList login keeps working. Changing those schemes would not, until the
  provider's registered redirect URI matched.
