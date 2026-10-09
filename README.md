# anImestream

**An iOS-focused fork of Animestream.**

anImestream is a Flutter application for streaming anime with AniList tracking, based on the original [Animestream](https://github.com/frostnova721/animestream) project by **FrostNova (frostnova721)**.

This fork is maintained by **sofikuw** and is focused on producing an iOS build while keeping the upstream application's core functionality intact.

> The original project is licensed under the GNU General Public License v3.0. This fork remains under GPL-3.0 and preserves the original author's attribution. See [LICENSE](LICENSE).

## Authors

- **Original author:** [FrostNova / frostnova721](https://github.com/frostnova721)
- **Fork author / iOS maintainer:** [sofikuw](https://github.com/sofikuw)

## iOS support status

The upstream application is multi-platform, but some parts of its implementation are Android-specific. This table lists the current availability in this iOS fork:

| Feature | iOS status | Notes |
| --- | --- | --- |
| Anime streaming | ✅ Supported | iOS and Android use the BetterPlayer backend; desktop uses FVP. |
| AniList tracking | ✅ Supported | Shared Flutter functionality. |
| Search / discovery / lists | ✅ Supported | Shared Flutter functionality. |
| Picture in Picture | ✅ Supported | iOS 15 and later; use the player PiP control or enable Auto Picture-in-Picture in player settings. |
| Double-tap-to-seek | ✅ Supported | Optional iOS and Android setting; double-tap the left or right side to seek. |
| Player gestures | ✅ Supported | Optional iOS and Android setting; swipe vertically on the left for brightness and right for volume. |
| Hold for 2× speed | ✅ Supported | Optional iOS and Android setting; hold the video to temporarily play at 2×, then release to restore the previous speed. |
| Old navbar | ❌ Android-only | The upstream implementation and navbar transparency are Android-specific. |
| Anime downloads | ✅ Supported  | This fork now can download animes in ios. |
| Android TV support | ❌ Android-only | TV detection and related storage handling use Android APIs. |
| Desktop window controls / RPC | ❌ Not applicable | Windows/Linux-specific functionality was removed from this fork's platform projects. |

### Important

The table describes the **current state of this fork**. Several limitations are inherited from Android-oriented upstream code and are not limitations of iOS itself.

This fork enables the native iOS Picture-in-Picture player path. The iOS deployment target is 15.0 to match Flutter 3.47.1's iOS minimum.

## What was removed for the iOS fork

The repository no longer carries platform projects/build tooling that are not required for the iOS build:

- Android project
- Windows project
- Linux project
- macOS project
- Web project
- Linux installer script
- Cross-platform `astrm` build scripts
- Android/Linux/Windows release-build workflow logic
- Windows installer configuration/tooling
- Release notification workflow from the upstream project

The shared Dart source remains largely intact so that the fork does not unnecessarily diverge from the original application.

## Building the unsigned iOS IPA

This fork uses GitHub Actions and Apple's macOS runner.

1. Fork/clone this repository.
2. Add the required repository secrets:
   - `SIMKL_CLIENT_SECRET`
   - `SIMKL_CLIENT_ID`
   - `COMMENTUM_API_URL`
   - `DISCORD_APP_ID`
3. Open **Actions → Build iOS Unsigned IPA → Run workflow**.
4. Download the generated `anImestream-*-ios-unsigned.ipa` artifact.

The workflow intentionally uses `--no-codesign`; signing/installing the IPA is a separate step.

## Project name

The iOS application display name is **anImestream**.

The internal Dart package name remains `animestream` because Dart package identifiers are conventionally lowercase and changing it would require a much larger source-wide refactor with no benefit to the iOS build.

## Upstream

This project is derived from:

**Animestream** — https://github.com/frostnova721/animestream

The upstream project is heavily inspired by Saikou and was originally built as a multi-platform Flutter application.

## License

This fork is licensed under the **GNU General Public License v3.0 (GPL-3.0)**, the same license as the original project.

GPLv3 permits modification and redistribution while requiring covered derivative works to preserve the license's copyleft terms.

See [LICENSE](LICENSE) for the complete license text.

## Disclaimer

This project does not host or provide anime content. It accesses third-party sources/APIs. Users are responsible for complying with applicable laws, terms of service, and copyright requirements when using the application.
