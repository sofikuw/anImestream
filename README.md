# anImestream

![Flutter](https://img.shields.io/badge/Flutter-3.47.1-02569B?logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-API%2024%2B-3DDC84?logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-15.0%2B-000000?logo=apple&logoColor=white)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)

**A cross-platform anime and manga client for Android and iOS, built with Flutter.**

anImestream brings discovery, streaming, downloads, manga reading and list
tracking into one app. The Android and iOS builds share the same Dart codebase,
so features and fixes land on both platforms together.

> This repository is the standalone **`divergent`** build. It ships under its
> own display name and application identifiers, so it can be installed alongside
> a `master` build of the same project. See [Branches and builds](#branches-and-builds).

## Features

- **Anime discovery** — trending, currently airing, recently updated,
  recommendations, seasonal browsing and search.
- **Manga discovery** — trending and popular manga, search, and a dedicated
  reading flow with chapter tracking.
- **Streaming sources** — built-in providers plus installable JavaScript
  extensions managed from the app.
- **Manga extensions** — install MangaDex, MangaPill, Ragnarok Scanlation and
  other providers from the extension catalog.
- **List tracking** — AniList, MyAnimeList and Simkl integrations, including
  progress updates and alternate-ID sync.
- **Offline downloads** — save anime episodes for offline playback.
- **Modern player** — subtitles, playback speed, gesture controls, wakelock,
  Picture-in-Picture and optional auto-PiP.
- **Continue watching and reading** — resume from Home, with local history for
  signed-in and signed-out users.
- **Theming and personalisation** — light/dark themes, dynamic colour and title
  preferences.
- **Resilient metadata** — metadata reads are isolated from the UI, so one failing
  rail or provider does not take down the rest of the page.

## Platform support

| Capability | Android | iOS |
| --- | :---: | :---: |
| Anime streaming | ✅ | ✅ |
| Manga reading | ✅ | ✅ |
| Search and discovery | ✅ | ✅ |
| AniList / MAL / Simkl tracking | ✅ | ✅ |
| Downloads | ✅ | ✅ |
| Picture-in-Picture | ✅ | ✅ (iOS 15+) |
| Player gestures and speed controls | ✅ | ✅ |
| Android TV | ✅ | — |
| Desktop | — | — |

**Minimum versions:** Android 7.0 (API 24) and iOS 15.0.

## Installation

Prebuilt packages are published on the
[GitHub Releases](https://github.com/sofikuw/anImestream/releases) page by the
release workflows.

- **Android:** download the universal APK, or the APK matching your device ABI
  (`arm64-v8a` for most modern phones).
- **iOS:** download the unsigned IPA and sign it with your preferred sideloading
  tool. The project is not distributed through the App Store.

The app is not published on Google Play or the App Store. Release builds may be
marked as prereleases while a channel is being tested.

## Requirements

| Tool | Version |
| --- | --- |
| Flutter | `3.47.1` (pinned in `.fvmrc` and CI) |
| Dart | `>=3.12.0` |
| Android | JDK 17, Android SDK with API 24+ |
| iOS | macOS, Xcode, CocoaPods, iOS 15+ deployment target |

The project uses [FVM](https://fvm.app/) optionally. If FVM is installed, prefix
Flutter commands with `fvm`; otherwise use the matching Flutter SDK directly.

## Getting started

```bash
git clone https://github.com/sofikuw/anImestream.git
cd anImestream
git checkout divergent
flutter pub get
flutter run
```

To enable integrations that require build-time configuration, copy the template
and fill in your own credentials:

```bash
cp .env_example .env
# edit .env
flutter run --dart-define-from-file=.env
```

The file is JSON and is passed to Flutter with `--dart-define-from-file`. It must
not be committed. The app still starts without it; the affected integrations are
simply unavailable.

## Building

### Android

```bash
# Universal APK
flutter build apk --release --dart-define-from-file=.env

# Smaller per-ABI APKs
flutter build apk --release --split-per-abi \
  --dart-define-from-file=.env

# Google Play bundle
flutter build appbundle --release --dart-define-from-file=.env
```

Outputs are written to `build/app/outputs/flutter-apk/` and
`build/app/outputs/bundle/release/`.

The CI workflow produces a universal APK plus `arm64-v8a`, `armeabi-v7a` and
`x86_64` APKs. Release installs require a consistent signing key; without the
keystore secrets, CI generates a throwaway key and the resulting APK cannot
upgrade an existing install.

### iOS

Building for a physical device requires macOS, Xcode and an Apple signing
identity. For an unsigned build:

```bash
flutter build ios --release --no-codesign
```

The release workflow builds an **unsigned IPA** with `xcodebuild` and packages it
for sideloading. An unsigned IPA must be signed by the installer (for example
AltStore, Sideloadly or Xcode) before it can be installed on a device.

## Configuration

The following values are supplied at build time with `--dart-define` or
`--dart-define-from-file`:

| Key | Purpose |
| --- | --- |
| `SIMKL_CLIENT_ID` | Simkl OAuth client ID |
| `SIMKL_CLIENT_SECRET` | Simkl OAuth client secret |
| `COMMENTUM_API_URL` | Commentum comments backend |
| `DISCORD_APP_ID` | Discord Rich Presence application ID |

For GitHub Actions, add these as repository secrets:
`SIMKL_CLIENT_ID`, `SIMKL_CLIENT_SECRET`, `COMMENTUM_API_URL`,
`DISCORD_APP_ID`.

Android release signing additionally uses:

`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`,
`ANDROID_STORE_PASSWORD`.

## Branches and builds

The repository keeps two installable identities on the same Dart source:

| | `divergent` (default) | `master` |
| --- | --- | --- |
| Purpose | Standalone build | Upstream-tracking build |
| Display name | `anImestream-divergent` | `anImestream` |
| iOS bundle ID | `divergent.sofikuw.anImestream` | Project default |
| Android application ID | `divergent.sofikuw.anImestream` | `app.animestream` |
| iOS artifact | `anImestream-divergent-<version>-ios-unsigned.ipa` | `anImestream-<version>-ios-unsigned.ipa` |
| Android artifact | `anImestream-divergent-<version>-android.apk` | `anImestream-<version>-android.apk` |

Because the identities differ, both builds can be installed side by side.

The identity is applied to the working tree at build time rather than committed:

```bash
bash branches/apply-identity.sh divergent
git diff --stat
```

The script is idempotent. See [branches/README.md](branches/README.md) for the
full descriptor schema and instructions for adding another build identity.

## Continuous integration

Two GitHub Actions workflows build and publish releases:

| Workflow | Runner | Trigger tags | Artifacts |
| --- | --- | --- | --- |
| `Build and Release Android` | Ubuntu | `android-v*`, `divergent-android-v*` | Universal and per-ABI APKs |
| `Build and Release iOS` | macOS | `v*`, `divergent-v*` | Unsigned IPA |

Both can also be run manually with **Actions → Run workflow**, where you choose:

- the branch (`divergent` or `master`);
- the release channel (`stable`, `prerelease`, `beta` or `alpha`);
- an optional existing tag to rebuild;
- whether to create a GitHub Release.

Manual runs create a unique, random-suffixed tag so the same version can be
released more than once without editing `pubspec.yaml`. Stable tags omit the
channel suffix.

## Providers and extensions

Streaming and manga providers are pluggable. JavaScript providers are installed
from versioned HTTPS catalogs through **Settings → Manage Providers**.

- Default catalog: `https://animestream-extensions.val.run/index.json`
- Catalog and provider API: [docs/provider-repository-format.md](docs/provider-repository-format.md)

Only install catalogs and providers you trust. Extensions execute third-party
code inside the app.

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

Release history is documented in [changelog.md](changelog.md).

## Credits

- **Original project:** [FrostNova / frostnova721](https://github.com/frostnova721/animestream)
- **iOS fork:** [sofikuw](https://github.com/sofikuw)
- **This standalone build:** the anImestream contributors

anImestream is built with Flutter and relies on open-source packages and
community provider extensions. Thanks to their maintainers.

## License

This project is licensed under the **GNU General Public License v3.0**. See
[LICENSE](LICENSE).

## Disclaimer

anImestream does not host, provide or distribute anime or manga content. It
accesses third-party sources and APIs selected by the user. Users are responsible
for complying with applicable laws, terms of service and copyright requirements.
