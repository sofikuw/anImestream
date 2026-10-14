# anImestream-divergent

**A standalone iOS build of anImestream — no upstream tracking.**

This repository builds and releases its own iOS app. It is derived from
[sofikuw/anImestream](https://github.com/sofikuw/anImestream), itself an iOS
fork of [Animestream](https://github.com/frostnova721/animestream) by
**FrostNova (frostnova721)**, but it no longer follows either upstream: releases
are cut from this repository's own tags, under its own name, bundle id and icon.

Two branches come out of this repository. `divergent` is the standalone app;
`master` is the branch the repository already had, kept so the old build can
still be produced:

| | `divergent` (default) | `master` |
| --- | --- | --- |
| Display name | `anImestream-divergent` | `anImestream` |
| iOS bundle id | `divergent.sofikuw.anImestream` | unchanged from the project |
| Tags | `divergent-v1.0.6-4f2ab9` | `v1.0.6-4f2ab9` |
| IPA | `anImestream-divergent-1.0.6-ios-unsigned.ipa` | `anImestream-1.0.6-ios-unsigned.ipa` |
| Icon | its own, if `branches/divergent/icon/` holds one | unchanged |

Both install side by side on one device, because they are different bundle ids
and different display names; the tag prefix and the artifact name are derived
from the branch name, so there is no second list to keep in step. See
[branches/README.md](branches/README.md) for what a branch carries, how it is
created, and how to add another.

The internal Dart package name stays `animestream`. Dart package identifiers
cannot contain dots or capitals, so `divergent.sofikuw.anImestream` — a bundle
id — cannot live in `pubspec.yaml`, and renaming it would mean rewriting every
`package:animestream/...` import in `lib/` for no benefit.

## Authors

- **Original author:** [FrostNova / frostnova721](https://github.com/frostnova721)
- **iOS fork:** [sofikuw](https://github.com/sofikuw)
- **This repository:** [exurtys](https://github.com/exurtys)

## iOS support status

The upstream application is multi-platform, but some parts of its implementation
are Android-specific. This table lists the current availability in this iOS
build:

| Feature | iOS status | Notes |
| --- | --- | --- |
| Anime streaming | ✅ Supported | iOS and Android use the BetterPlayer backend; desktop uses FVP. |
| AniList tracking | ✅ Supported | Shared Flutter functionality. |
| Search / discovery / lists | ✅ Supported | Shared Flutter functionality. |
| Manga reading | ✅ Supported | Manga is a first-class content type here: MangaDex, MangaPill and Ragnarok Scanlation are installable from the extension catalog. |
| Continue Reading | ✅ Supported | Home rail under Continue Watching, backed by local storage. |
| Picture in Picture | ✅ Supported | iOS 15 and later; use the player PiP control or enable Auto Picture-in-Picture in player settings. |
| Double-tap-to-seek | ✅ Supported | Optional iOS and Android setting; double-tap the left or right side to seek. |
| Player gestures | ✅ Supported | Optional iOS and Android setting; swipe vertically on the left for brightness and right for volume. |
| Hold for 2× speed | ✅ Supported | Optional iOS and Android setting; hold the video to temporarily play at 2×, then release to restore the previous speed. |
| Anime downloads | ✅ Supported | |
| Old navbar | ❌ Android-only | The upstream implementation and navbar transparency are Android-specific. |
| Android TV support | ❌ Android-only | TV detection and related storage handling use Android APIs. |
| Desktop window controls / RPC | ❌ Not applicable | Windows/Linux-specific functionality was removed from the fork's platform projects. |

The iOS deployment target is 15.0, matching Flutter's iOS minimum.

## Building an unsigned IPA

The workflow uses GitHub Actions and Apple's macOS runner; the IPA is unsigned,
so installing and signing it is a separate step.

1. Add the required repository secrets: `SIMKL_CLIENT_SECRET`, `SIMKL_CLIENT_ID`,
   `COMMENTUM_API_URL`, `DISCORD_APP_ID`.
2. **Actions → Build and Release iOS → Run workflow**, and pick:
   - **branch** — `divergent` (default) or `master`. That ref is checked out and
     built; the identity below is then applied to it.
   - **release_channel** — `stable`, `prerelease`, `beta` or `alpha`. Anything
     other than `stable` publishes the GitHub Release as a prerelease.
   - **tag_name** — optional; build an existing tag instead of the branch you
     selected.
   - **create_release** — on by default.
3. Download the `anImestream-divergent-ios-unsigned` artifact from the run.

### Tags and releases

Every manual run creates its own tag and its own GitHub Release. The tag is

```
<prefix>v<version>-<channel>.<8 random hex chars>      e.g. divergent-v1.0.6-beta.4f2ab9
```

The version keeps the tag readable; the random characters are what make repeated
runs at the same version possible, so releasing does not require bumping
`pubspec.yaml` first. Stable tags omit the channel:
`divergent-v1.0.6-9c1de0`.

Pushing a tag that matches `v*` or `divergent-v*` builds and releases it too,
without the random suffix — and in that case the channel is inferred from the
version (`1.0.6-beta.1` publishes as a prerelease).

Builds made in this val's staging archive land as `stage-p/`, so:

```bash
curl -sSL https://animestream-manga.val.run/animestream-manga.zip -o manga.zip
unzip -o manga.zip          # from the repo root
git status                  # check what changed before committing
```

## Icons

`flutter_launcher_icons` and `flutter_native_splash` read their source images
from `lib/assets/icons/` (see `pubspec.yaml`). A branch that ships its own icon
keeps it in `branches/<name>/icon/`, and `branches/apply-identity.sh` copies any
PNG there over the same-named asset in `lib/assets/icons/` at build time.

The `divergent` icon is the original logo with a crack overlay drawn over it.
It is generated rather than hand-drawn: the val serving this archive can render
it from the upstream artwork at `/icon/divergent-logo.png`, so it can be
regenerated whenever upstream changes.

Regenerate the iOS `AppIcon` set after changing an icon:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

## JavaScript provider repositories

Manage Providers accepts versioned HTTPS catalogs for JavaScript providers. See
[the repository format and provider API](docs/provider-repository-format.md)
before adding a catalog.

The manga and anime sources used by this build are served from
`https://animestream-extensions.val.run/index.json`.

## Changelog

See [changelog.md](changelog.md). It was created empty; it now starts at the
first divergent release.

## License

**GNU General Public License v3.0 (GPL-3.0)** — the same license as the original
project. GPLv3 permits modification and redistribution while requiring covered
derivative works to preserve its copyleft terms.

[LICENSE](LICENSE) is deliberately **not** part of this stage. It is already
correct in the repository, and restaging a 35KB licence to say the same thing
only risks replacing it with a paraphrase.

## Disclaimer

This project does not host or provide anime or manga content. It accesses
third-party sources and APIs. Users are responsible for complying with
applicable laws, terms of service and copyright requirements when using the
application.
