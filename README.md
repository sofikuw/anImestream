# anImestream (v1.0.6)

> A modern anime streaming and manga reading client written in Flutter/Dart, featuring a **Mangayomi-inspired JavaScript Extension System**, full **Manga Reader**, and native **YouTube-style iOS Picture-in-Picture (PiP)**.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Flutter](https://img.shields.io/badge/flutter-v3.24.3-blue.svg)](https://flutter.dev)
[![iOS Target](https://img.shields.io/badge/iOS-15.0%2B-orange.svg)]()
[![Extension API](https://img.shields.io/badge/Extension%20API-v1.0.0-purple.svg)]()
[![License](https://img.shields.io/badge/license-GPLv3-green.svg)]()

---

## 🌟 What's New in v1.0.6

- 🧩 **Mangayomi-Inspired JavaScript Extension System**: Add and run third-party JavaScript extensions from custom GitHub repositories without rebuilding the iOS IPA whenever source scripts update.
- 📖 **Complete Manga Tab**: Integrated manga browsing, search with provider filters, details with chapter tracking, and a full-featured reader.
- 📜 **Versatile Manga Reader**: Supports **Vertical Continuous (Webtoon)** reading, **Horizontal Page-by-Page (LTR / RTL)** reading, page slider, chapter switching, and reading progress caching.
- 🛡️ **Safe Atomic Installer & Rollback**: Automatic sandbox testing, API validation (v1.x), and instant rollback to the last known-good version if an update fails.
- ⚡ **Zero-Dependency iOS Runtime**: Utilizes Apple's native `JavaScriptCore.framework` via Swift, requiring no external C++ binaries or CocoaPods, ensuring smooth unsigned IPA sideloading.
- 📺 **YouTube-Style iOS Picture-in-Picture**: Preserved seamless background transition with inline auto-start (`canStartPictureInPictureAutomaticallyFromInline`).

---

## 🏗️ Architecture Overview

```
anImestream Architecture
├── UI & Presentation Layer (Flutter Widgets)
│   ├── Anime Home, Discover & Video Player
│   ├── Manga Home, Search & Chapter Reader
│   └── Settings & Manage Extensions (Repository Browser)
│
├── Adapter & Provider Abstraction Layer
│   ├── JsAnimeProviderAdapter ───► Standard VideoSource & AnimeDetails
│   ├── JsMangaProviderAdapter ───► Standard MangaDetails & MangaPages
│   └── Built-in Providers (e.g., AniKoto) Coexist via ProviderRegistry
│
├── Extension Management & Security Layer
│   ├── RepositoryManager (HTTPS catalog fetch & index.json caching)
│   ├── SafeExtensionInstaller (atomic download, validation, dry-run, rollback)
│   └── ExtensionManager (persistence, activation, and context lifecycle)
│
└── Sandboxed Execution Engine
    ├── iOS: JavaScriptCoreBridge.swift (Native Apple JavaScriptCore)
    ├── Android / Desktop: QuickJS / Dart runtime bridge
    └── Strict 15s execution timeout & isolated memory contexts
```

---

## 🚀 Key Features

### 1. Dynamic JavaScript Extensions
- Interpreted inside an isolated `JSContext` at runtime.
- Supports independent capabilities: `searchAnime`, `popularAnime`, `latestAnime`, `animeDetails`, `videoSources`, `searchManga`, `popularManga`, `mangaDetails`, `chapters`, `mangaPages`.
- Safe host APIs: `http.get()`, `http.post()`, `console.log()`, `atob()`, `btoa()`.

### 2. Full Manga Support
- **Manga Home**: Trending carousels, latest releases, and continue reading tiles.
- **Search & Filter**: Search across multiple sources with genre and status filters.
- **Reader Engine**:
  - Vertical Continuous (infinite scroll webtoon mode).
  - Horizontal LTR & RTL paged modes.
  - InteractiveViewer pinch-to-zoom.
  - Page jump slider and chapter navigation drawer.
  - Progress persistence and chapter read indicators.

### 3. Repository-Based Extension Manager
- Browse configured remote extension repositories.
- One-click install and update.
- Enable/disable toggles to suspend sources without deleting files.
- Add custom GitHub Pages or Raw HTTPS repository URLs.

### 4. Native iOS Picture-in-Picture
- Supports inline automatic PiP transition when swiping to the iOS home screen.
- Configured with `AVAudioSessionCategoryPlayback` and background audio modes.

---

## 📂 Project Structure

```
animestream/
├── .github/workflows/
│   └── build-ios.yml               # GitHub Actions unsigned IPA build & release
├── ios/
│   └── Runner/
│       ├── AppDelegate.swift       # Registers PiP & JavaScriptCore bridges
│       ├── Info.plist              # Background audio & App Transport Security
│       ├── JavaScriptCoreBridge.swift # Native Apple JavaScriptCore Swift plugin
│       └── PiPManager.swift        # iOS 15+ inline auto-PiP controller
├── lib/
│   ├── core/
│   │   ├── extensions/
│   │   │   ├── manager/            # ExtensionManager, RepositoryManager, SafeInstaller
│   │   │   ├── models/             # ExtensionManifest, ExtensionCatalog, MangaModels
│   │   │   └── runtime/            # JsRuntimeBridge (Dart <-> JS execution engine)
│   │   ├── anime/providers/        # JsAnimeProviderAdapter & built-in providers
│   │   ├── manga/providers/        # MangaProvider interface & JsMangaProviderAdapter
│   │   └── app/                    # PiP service, logging, and environment settings
│   └── ui/
│       ├── pages/
│       │   ├── mainNav.dart        # Main navigation shell with new Manga tab
│       │   ├── manga/              # MangaHomePage, MangaSearchPage, MangaReaderPage
│       │   └── settingPages/       # ManageExtensionsPage (repo browser & installer)
│       └── models/playerControllers/
├── sample_repo/                    # Sample repository template
│   ├── index.json                  # Catalog index
│   └── extensions/
│       ├── gogoanime.js            # Sample anime streaming extension
│       └── mangadex.js             # Sample manga reader extension
├── test/
│   ├── extension_system_test.dart  # Unit tests for manifest, catalog, and JS runtime
│   └── manga_feature_test.dart     # Unit tests for manga models and progress tracking
├── EXTENSION_API.md                # Complete API v1.0.0 specification
├── GUIDE_CREATE_EXTENSION.md       # Developer guide for creating JS extensions
├── GUIDE_HOST_REPOSITORY.md        # Guide for hosting repositories on GitHub
└── GUIDE_INSTALLATION_MANAGEMENT.md # Guide for installing, updating, and disabling sources
```

---

## 🛠️ Building for iOS (Unsigned Sideloading IPA)

### Prerequisites
- macOS with Xcode 15+
- Flutter 3.24.3+

### Step-by-Step Build Commands
```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run test suites
flutter test test/extension_system_test.dart test/manga_feature_test.dart

# 3. Build release iOS app without codesigning
flutter build ios --no-codesign --release

# 4. Package into unsigned IPA
mkdir -p Payload
cp -r build/ios/iphoneos/Runner.app Payload/
zip -r animestream-unsigned.ipa Payload
```

### Sideloading onto iPhone / iPad
The resulting `animestream-unsigned.ipa` can be installed directly using any standard sideloading tool:
- **AltStore / AltServer**: Install via Mail plugin / AltServer sideload.
- **Sideloadly**: Drag and drop `animestream-unsigned.ipa` and sign with your free Apple ID.
- **TrollStore** (iOS 14.0 - 16.6.1): Direct install without 7-day expiration.
- **Scarlet / Feather / Esign**: Direct on-device signing.

---

## 🧪 Testing

Run static analysis and automated unit tests:
```bash
flutter analyze --no-fatal-infos
flutter test
```

---

## 📄 License
This project is licensed under the terms of the GNU General Public License v3.0.
All dynamic third-party extensions are executed client-side inside an isolated sandbox.
