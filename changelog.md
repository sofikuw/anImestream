# Changelog

All notable changes to this repository. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are the tags
the release workflow creates.

This file was created empty upstream, so the history below starts here rather
than pretending to cover the fork's earlier life. That history is in the git log.

## [Unreleased]

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
