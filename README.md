<div align="center">

<img src="lib/assets/icons/logo.png" alt="anImestream" width="128" />

# anImestream

**Anime and manga, in one place.**

A fast, native Android client for streaming anime and reading manga, built with Flutter.

[![Flutter](https://img.shields.io/badge/Flutter-3.47.1-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-API%2024%2B-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Release](https://img.shields.io/github/v/release/sofikuw/anImestream?include_prereleases&label=release)](https://github.com/sofikuw/anImestream/releases)

[Download](#installation) · [Features](#features) · [Extensions](#extensions) · [Build](#building)

</div>

---

anImestream brings discovery, streaming, downloads, manga reading and list tracking into a single, focused app. It is built primarily for Android and ships as a standalone build with its own application ID, so it can be installed alongside other anImestream builds.

> iOS support is paused until a dedicated beta tester is available.

## Features

| | |
| --- | --- |
| **Discover** | Trending, airing, recent, seasonal and recommended anime, plus manga discovery and search. |
| **Stream** | Built-in streaming sources and installable JavaScript extensions, with a modern player: subtitles, gestures, speed control, wakelock, Picture-in-Picture. |
| **Read** | Manga chapters from built-in sources or extensions, with progress tracking and per-chapter downloads. |
| **Track** | AniList, MyAnimeList and Simkl, including progress updates and alternate-ID sync. |
| **Offline** | Download anime episodes and manga chapters for offline use. |
| **Resume** | Continue watching and reading from the home screen, with or without an account. |
| **Personalise** | Light and dark themes, dynamic colour, and title preferences. |
| **Connect** | Optional Discord Rich Presence, and App Links for one-tap extension installs. |

## Platform support

| Capability | Android | iOS |
| --- | :---: | :---: |
| Anime streaming | ✅ | ⏸️ |
| Manga reading and downloads | ✅ | ⏸️ |
| Search and discovery | ✅ | ⏸️ |
| AniList / MAL / Simkl tracking | ✅ | ⏸️ |
| Episode and chapter downloads | ✅ | ⏸️ |
| Picture-in-Picture | ✅ | ⏸️ |
| Android TV | ✅ | — |
| Desktop | — | — |

**Minimum version:** Android 7.0 (API 24).

## Installation

Builds are published on the [GitHub Releases](https://github.com/sofikuw/anImestream/releases) page.

1. Open the latest release.
2. Download the universal APK, or the per-ABI APK matching your device
   (`arm64-v8a` for most modern phones).
3. Allow installation from your browser or file manager when prompted.

The app is not distributed through Google Play. Release builds may be marked as
prereleases while a channel is being tested.

## Requirements

| Tool | Version |
| --- | --- |
| Flutter | `3.47.1` (pinned in `.fvmrc` and CI) |
| Dart | `>=3.12.0` |
| Android | JDK 17, Android SDK with API 24+ |

[FVM](https://fvm.app/) is optional. If it is installed, prefix Flutter commands
with `fvm`; otherwise use a matching Flutter SDK directly.

## Getting started

```bash
git clone https://github.com/sofikuw/anImestream.git
cd anImestream
git checkout divergent
flutter pub get
flutter run
```

Integrations that need build-time credentials read them from a JSON file passed
with `--dart-define-from-file`:

```bash
cp .env_example .env
# edit .env with your own values
flutter run --dart-define-from-file=.env
```

The app starts without this file; the affected integrations are simply
unavailable. Never commit `.env`.

## Building

```bash
# Universal APK
flutter build apk --release --dart-define-from-file=.env

# Smaller per-ABI APKs
flutter build apk --release --split-per-abi --dart-define-from-file=.env

# Google Play bundle
flutter build appbundle --release --dart-define-from-file=.env
```

Outputs land in `build/app/outputs/flutter-apk/` and
`build/app/outputs/bundle/release/`.

Release installs require a consistent signing key. Without the keystore secrets,
CI generates a throwaway key, and the resulting APK cannot upgrade an existing
install.

## Configuration

Values are supplied at build time with `--dart-define` or
`--dart-define-from-file`:

| Key | Purpose |
| --- | --- |
| `SIMKL_CLIENT_ID` | Simkl OAuth client ID |
| `SIMKL_CLIENT_SECRET` | Simkl OAuth client secret |
| `COMMENTUM_API_URL` | Commentum comments backend |
| `DISCORD_APP_ID` | Discord Rich Presence application ID |

For GitHub Actions, provide them as repository secrets:
`SIMKL_CLIENT_ID`, `SIMKL_CLIENT_SECRET`, `COMMENTUM_API_URL`, `DISCORD_APP_ID`.

Android release signing additionally uses `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` and `ANDROID_STORE_PASSWORD`.

## Extensions

Anime and manga providers are installable at runtime from versioned HTTPS
catalogs, through **Settings → Manage Providers**.

An extension is a catalog entry plus a JavaScript module:

- catalogs use the native `{ "schemaVersion": 1, "providers": [...] }` shape;
- each provider declares `identifier`, `version`, `contentTypes`, an
  `entrypointSha256` digest and an `allowedHosts` allowlist;
- code is verified against its digest and runs in an isolated JavaScript
  runtime with HTTPS-only, host-restricted network access.

Default catalog: `https://animestream-extensions.val.run/index.json`

The full format is documented in
[docs/provider-repository-format.md](docs/provider-repository-format.md).

> **Only anImestream's own manifest format is supported.** Tachiyomi, MangaYomi,
> Aniyomi and Mihon extensions are Kotlin APKs that require `DexClassLoader` and
> their own extension API; they cannot run here. There is no bridge.

Only install catalogs and providers you trust: extensions execute third-party
code inside the app. Extensions never receive app cookies, sessions or
filesystem access.

## Branches and builds

The repository keeps two installable identities on the same Dart source:

| | `divergent` (default) | `master` |
| --- | --- | --- |
| Purpose | Standalone build | Upstream-tracking build |
| Display name | `anImestream-divergent` | `anImestream` |
| Application ID | `divergent.sofikuw.anImestream` | `app.animestream` |

Because the identities differ, both builds can be installed side by side.

The identity is applied to the working tree at build time rather than committed:

```bash
bash branches/apply-identity.sh divergent
```

The script is idempotent. See [branches/README.md](branches/README.md) for the
descriptor schema.

## Continuous integration

| Workflow | Runner | Trigger tags | Artifacts |
| --- | --- | --- | --- |
| `Build and Release Android` | Ubuntu | `android-v*`, `divergent-android-v*` | Universal and per-ABI APKs |
| `Build and Release iOS` | macOS | `v*`, `divergent-v*` | Unsigned IPA |

Both can also be dispatched manually from **Actions → Run workflow**, choosing
the branch, release channel (`stable`, `prerelease`, `beta`, `alpha`), an
optional existing tag, and whether to create a GitHub Release. Manual runs use a
unique, random-suffixed tag so the same version can be released more than once
without editing `pubspec.yaml`.

## Project structure

```text
lib/
  core/       networking, storage, authentication, databases, providers
  ui/         pages, widgets, themes and view models
android/      Android platform project
ios/          iOS platform project
packages/     vendored packages (including the BetterPlayer fork)
branches/     per-branch identity descriptors and apply script
docs/         provider repository documentation
```

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

Keep pull requests focused. Run `flutter analyze` and `flutter test` before
opening one, and describe any platform-specific behaviour you could not verify.
Release history lives in [changelog.md](changelog.md).

## Credits

- **Original project:** [FrostNova / frostnova721](https://github.com/frostnova721/animestream)
- **iOS and standalone build:** [sofikuw](https://github.com/sofikuw)

Built with Flutter and community provider extensions. Thanks to their
maintainers.

## License

Licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

## Disclaimer

anImestream does not host, provide or distribute anime or manga content. It
accesses third-party sources and APIs chosen by the user. Users are responsible
for complying with applicable laws, terms of service and copyright
requirements.
