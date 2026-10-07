<div align="center">

<img src="assets/icon.png" width="120" alt="anImestream icon">

# anImestream

An iOS-focused fork of **Animestream**, a Flutter-based anime streaming application.

**Original author:** [@frostnova721](https://github.com/frostnova721)  
**Fork / iOS maintainer:** [@sofikuw](https://github.com/sofikuw)

</div>

---

## Requirements

### iOS

- **Minimum iOS version:** iOS 13.0
- Internet connection required
- iPhone or iPad capable of running iOS 13+
- Releases are currently distributed as **unsigned IPAs**

---

## Installation

The released IPA is **unsigned**, so it cannot simply be opened and installed on a normal, non-jailbroken iPhone.

### AltStore / SideStore

1. Install AltStore or SideStore on your device.
2. Download the `anImestream-*.ipa` from GitHub Releases.
3. Import the IPA into AltStore/SideStore.
4. Sign and install the application.
5. Open anImestream.

The exact signing limits depend on the sideloading solution and Apple account being used.

### Sideloadly

1. Download the latest anImestream IPA.
2. Open Sideloadly on a supported computer.
3. Connect your iPhone/iPad.
4. Select the IPA.
5. Sign and install it with your Apple account.
6. Trust the developer profile on the device if required.
7. Launch anImestream.

Free Apple accounts may have Apple's normal sideloading limitations.

### Jailbroken devices

On a jailbroken device, the unsigned IPA can potentially be installed using a suitable jailbreak-side installation method.

The exact procedure depends on the jailbreak, iOS version, and installed signing/app-installation components.

---

## GitHub Releases

Releases are built automatically using GitHub Actions.

A version tag such as:

```text
v1.0.0
```

triggers the iOS build workflow.

The workflow:

1. Checks out the tagged source.
2. Sets up Flutter.
3. Builds the iOS application.
4. Creates an unsigned IPA.
5. Uploads the IPA as an Actions artifact.
6. Attaches the IPA to the GitHub Release.

Example:

```text
anImestream v1.0.0
└── anImestream-1.0.0-ios-unsigned.ipa
```

---

## iOS-specific limitations

Animestream was originally designed as a multi-platform application. Some features in the original project depend specifically on Android or desktop APIs.

The following features are unavailable or may behave differently on iOS:

- Android-specific download/storage functionality
- Android filesystem paths
- Android Picture-in-Picture implementation
- Android player gesture settings
- Android-specific navigation bar settings
- Android navigation bar transparency
- Android TV functionality
- Desktop Discord Rich Presence
- Desktop-specific functionality
- Android-specific update/installer functionality

These features are intentionally not part of the iOS build where they depend on unsupported platform APIs.

---

## Features

The iOS fork retains the main cross-platform functionality of Animestream, including:

- Anime discovery
- Anime search
- Anime information
- Streaming
- Episode selection
- AniList integration
- Watchlists / lists
- User preferences
- Dark mode
- Other functionality implemented through Flutter's shared code

Availability of individual features may depend on the upstream services used by the application.

---

## Why an iOS fork?

The original project contains support for multiple platforms.

This fork provides a cleaner iOS-focused codebase by removing unnecessary platform projects and build infrastructure while keeping the shared Flutter application code.

The goal is to make iOS development and automated IPA releases simpler.

---

## Building from source

### Requirements

- Flutter SDK
- Xcode
- macOS
- CocoaPods
- An Apple development environment for signed builds

Install dependencies:

```bash
flutter pub get
```

Build the iOS application:

```bash
flutter build ios --release --no-codesign
```

The resulting application is located under:

```text
build/ios/iphoneos/
```

The GitHub Actions workflow packages the `.app` into an IPA automatically.

---

## Versioning

The application version is defined in:

```text
pubspec.yaml
```

Example:

```yaml
version: 1.0.0+1
```

The Git tag should match the release version:

```text
v1.0.0
```

For a beta:

```text
v1.1.0-beta1
```

---

## License

This project is distributed under the **GNU General Public License v3.0 (GPL-3.0)**, following the original project's license.

See the `LICENSE` file for the complete license text.

---

## Credits

### Original project

**Animestream**  
Original author: **FrostNova / frostnova721**

The original project and its contributors retain credit for the original work.

### iOS fork

**anImestream**  
Fork / iOS maintainer: **sofikuw**

This fork focuses on adapting, maintaining, and distributing the project for iOS.

---

## Disclaimer

anImestream is an independent fork and is not affiliated with Apple, AniList, or any third-party streaming/content provider.

The availability and legality of content accessed through the application depend on the services and sources used by the user.
