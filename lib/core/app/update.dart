import 'dart:convert';
import 'dart:io';

import 'package:animestream/core/app/logging.dart';
import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/commons/utils.dart';
import 'package:animestream/ui/models/bottomSheets/updateSheet.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The tag and channel are baked into the APK by the Android workflow. They let
/// a beta install recognise the exact release it came from, even when several
/// releases share the same pubspec version.
const String _buildTag = String.fromEnvironment('BUILD_TAG');
const String _buildChannel = String.fromEnvironment('APP_CHANNEL');

class UpdateCheckResult {
  /// A short label for the latest release, e.g. `v1.0.7-beta.2ef57230`.
  final String latestVersion;

  /// The full GitHub tag, used for the release page and the cached APK name.
  final String tagName;

  /// The version code of the current package
  final String currentVersion;

  /// Whether the release is a pre-release (beta versions)
  final bool preRelease;

  /// The release channel: stable, alpha, beta, rc or prerelease.
  final String channel;

  /// The direct download link for the asset
  final String downloadLink;

  /// The description markdown of the release
  final String description;

  /// The hash of the asset in the [downloadLink]
  final String hash;

  UpdateCheckResult({
    required this.latestVersion,
    required this.tagName,
    required this.currentVersion,
    required this.preRelease,
    required this.channel,
    required this.downloadLink,
    required this.description,
    required this.hash,
  });

  @override
  String toString() {
    return 'UpdateCheckResult(latestVersion: $latestVersion, tagName: $tagName, currentVersion: $currentVersion, preRelease: $preRelease, channel: $channel, downloadLink: $downloadLink, description: $description)';
  }
}

class _ReleaseInfo {
  final String tag;
  final List<int> version;
  final String stage;
  final bool preRelease;
  final DateTime publishedAt;
  final Map<String, dynamic> raw;

  _ReleaseInfo({
    required this.tag,
    required this.version,
    required this.stage,
    required this.preRelease,
    required this.publishedAt,
    required this.raw,
  });

  String get versionLabel {
    final base = 'v${version.join('.')}';
    if (!preRelease) return base;
    final build = RegExp(r'\.([0-9A-Za-z]+)$').firstMatch(tag)?.group(1);
    return build == null ? '$base-$stage' : '$base-$stage.$build';
  }
}

/// Checks the fork's GitHub releases for a newer stable or beta build.
///
/// Unlike the upstream implementation this does not rely on GitHub's release
/// order (which is not chronological), understands this repository's
/// `divergent-android-v...` tags, and selects an installable APK for the
/// device's ABI instead of looking for Flutter's internal `app-release.apk`.
Future<UpdateCheckResult?> checkForUpdates() async {
  // iOS builds are distributed as manually installed/sideloaded IPAs in this fork.
  if (Platform.isIOS) return null;

  try {
    final releasesUrl = 'https://api.github.com/repos/sofikuw/anImestream/releases?per_page=100';
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final packageName = packageInfo.packageName;
    final rawReleases = json.decode(await fetch(releasesUrl)) as List<dynamic>;

    // Builds made before BUILD_TAG existed cannot identify their channel. Let
    // them see the beta channel once so the first post-update install can opt
    // into (or out of) betas like any other tagged build.
    final legacyBuild = _buildTag.isEmpty;
    final allowPrereleases =
        canReceivePreReleaseUpdates() || _stageFromText(currentVersion) != null || legacyBuild;
    final candidates = <_ReleaseInfo>[];

    for (final raw in rawReleases) {
      if (raw is! Map) continue;
      final release = Map<String, dynamic>.from(raw);
      if (release['draft'] == true) continue;
      if (!_isSameBranchTag(release['tag_name'] as String? ?? '', packageName)) continue;
      if (!_hasInstallableAsset(release)) continue;

      final parsed = _parseRelease(release);
      if (parsed == null) continue;
      if (parsed.preRelease && !allowPrereleases) continue;
      candidates.add(parsed);
    }

    if (candidates.isEmpty) {
      Logs.app.log('<UPDATE-CHECK> No installable release found.');
      return null;
    }

    // Newest semantic version first; releases published at the same version
    // prefer stable, then the later publication.
    candidates.sort((a, b) => _compareReleases(b, a));
    final latest = candidates.first;
    Logs.app.log(
        '<UPDATE-CHECK> current ver: $currentVersion, build tag: ${_buildTag.isEmpty ? '<none>' : _buildTag}, latest ver: ${latest.tag}');

    if (!_isAnUpgrade(latest, currentVersion)) {
      Logs.app.log('<UPDATE-CHECK> APP IS ALREADY UP-TO-DATE!');
      return null;
    }

    final asset = await _selectAsset(latest.raw['assets'] as List<dynamic>? ?? const []);
    if (asset == null) {
      Logs.app.log('<UPDATE-CHECK> Release ${latest.tag} has no asset for this platform.');
      return null;
    }

    final downloadLink = asset['browser_download_url'] as String? ?? '';
    if (downloadLink.isEmpty) return null;
    final digest = asset['digest'];

    Logs.app.log('<UPDATE-CHECK> UPDATE AVAILABLE: ${latest.tag}');
    return UpdateCheckResult(
      latestVersion: latest.versionLabel,
      tagName: latest.tag,
      currentVersion: currentVersion,
      preRelease: latest.preRelease,
      channel: latest.stage,
      downloadLink: downloadLink,
      description: latest.raw['body'] as String? ?? '',
      hash: digest is String ? digest : '',
    );
  } catch (err) {
    Logs.app.log('<UPDATE-CHECK> Update check failed. \n$err');
    return null;
  }
}

bool canReceivePreReleaseUpdates() {
  final channel = _normalizedChannel(_buildChannel);
  return (currentUserSettings?.receivePreReleases ?? false) ||
      channel == 'alpha' ||
      channel == 'beta' ||
      channel == 'rc' ||
      channel == 'prerelease';
}

_ReleaseInfo? _parseRelease(Map<String, dynamic> release) {
  final tag = release['tag_name'] as String? ?? '';
  final version = _parseCore(tag);
  if (version == null) return null;

  final stageMatch =
      RegExp(r'-(alpha|beta|rc|prerelease)(?:[.\-]|$)', caseSensitive: false).firstMatch(tag);
  final stage = stageMatch?.group(1)?.toLowerCase() ?? (release['prerelease'] == true ? 'prerelease' : 'stable');
  final published = DateTime.tryParse(
        release['published_at']?.toString() ?? release['created_at']?.toString() ?? '',
      ) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  return _ReleaseInfo(
    tag: tag,
    version: version,
    stage: stage,
    preRelease: release['prerelease'] == true || stage != 'stable',
    publishedAt: published,
    raw: release,
  );
}

List<int>? _parseCore(String value) {
  final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(value);
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  ];
}

String? _stageFromText(String value) {
  final match = RegExp(r'-(alpha|beta|rc|prerelease)(?:[.\-]|$)', caseSensitive: false).firstMatch(value);
  return match?.group(1)?.toLowerCase();
}

String _normalizedChannel(String value) {
  final channel = value.trim().toLowerCase();
  if (channel == 'stable' || channel == 'alpha' || channel == 'beta' || channel == 'rc') return channel;
  if (channel.isNotEmpty) return 'prerelease';
  return '';
}

int _stageWeight(String stage) {
  switch (stage) {
    case 'alpha':
    case 'prerelease':
      return 1;
    case 'beta':
      return 2;
    case 'rc':
      return 3;
    case 'stable':
      return 4;
    default:
      return 0;
  }
}

int _compareCore(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final diff = a[i].compareTo(b[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

int _compareReleases(_ReleaseInfo a, _ReleaseInfo b) {
  final core = _compareCore(a.version, b.version);
  if (core != 0) return core;
  if (a.preRelease != b.preRelease) return a.preRelease ? -1 : 1;
  final stage = _stageWeight(a.stage).compareTo(_stageWeight(b.stage));
  if (stage != 0) return stage;
  return a.publishedAt.compareTo(b.publishedAt);
}

bool _isAnUpgrade(_ReleaseInfo latest, String currentVersion) {
  if (_buildTag.isNotEmpty && latest.tag == _buildTag) return false;

  final currentCore = _parseCore(currentVersion);
  if (currentCore == null) return false;

  final core = _compareCore(latest.version, currentCore);
  if (core != 0) return core > 0;

  final buildChannel = _normalizedChannel(_buildChannel);
  final currentStage = buildChannel.isNotEmpty ? buildChannel : (_stageFromText(currentVersion) ?? 'stable');
  final currentIsPreRelease = currentStage != 'stable';

  if (!latest.preRelease) {
    // A stable release at the same core version is a graduation from beta/rc.
    return currentIsPreRelease;
  }

  if (_buildTag.isNotEmpty && !canReceivePreReleaseUpdates() && _stageFromText(currentVersion) == null) {
    return false;
  }
  if (!currentIsPreRelease) {
    // A stable build never downgrades to a beta of the same core version. A
    // beta install made before BUILD_TAG existed cannot identify its snapshot,
    // so allow the first same-version beta update for it.
    if (buildChannel == 'stable') return false;
    return _buildTag.isEmpty;
  }

  final latestWeight = _stageWeight(latest.stage);
  final currentWeight = _stageWeight(currentStage);
  if (latestWeight != currentWeight) return latestWeight > currentWeight;

  // Same channel and version: a different build tag is a newer snapshot.
  return true;
}

bool _isSameBranchTag(String tag, String packageName) {
  // Divergent and master produce APKs with different application ids, so an
  // update across those tags would download an APK that cannot be installed
  // over the running app.
  if (packageName.contains('divergent')) return tag.startsWith('divergent-android-');
  return tag.startsWith('android-');
}

bool _hasInstallableAsset(Map<String, dynamic> release) {
  final assets = release['assets'] as List<dynamic>? ?? const [];
  return assets.any((asset) => _isInstallableName(_assetName(asset)));
}

String _assetName(dynamic asset) {
  return asset is Map ? asset['name']?.toString() ?? '' : '';
}

bool _isInstallableName(String name) {
  final lower = name.toLowerCase();
  if (Platform.isAndroid) return lower.endsWith('.apk');
  if (Platform.isLinux) return lower.endsWith('.zip');
  if (Platform.isWindows) return lower.endsWith('.exe');
  return false;
}

Future<Map<String, dynamic>?> _selectAsset(List<dynamic> assets) async {
  final installable = assets.where((asset) => _isInstallableName(_assetName(asset))).toList();
  if (installable.isEmpty) return null;

  if (Platform.isAndroid) {
    final abis = await _deviceAbis();
    for (final abi in abis) {
      final suffix = '-${abi.toLowerCase()}.apk';
      for (final asset in installable) {
        if (_assetName(asset).toLowerCase().endsWith(suffix)) {
          return Map<String, dynamic>.from(asset as Map);
        }
      }
    }

    // The workflow also publishes a universal APK. Prefer it over guessing an
    // ABI when the device did not report one.
    final abiSuffix = RegExp(r'-(arm64-v8a|armeabi-v7a|x86_64|x86)\.apk$');
    for (final asset in installable) {
      if (!abiSuffix.hasMatch(_assetName(asset).toLowerCase())) {
        return Map<String, dynamic>.from(asset as Map);
      }
    }
    installable.sort((a, b) => _assetName(a).length.compareTo(_assetName(b).length));
    return Map<String, dynamic>.from(installable.first as Map);
  }

  return Map<String, dynamic>.from(installable.first as Map);
}

Future<List<String>> _deviceAbis() async {
  if (!Platform.isAndroid) return const [];
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return info.supportedAbis;
  } catch (err) {
    Logs.app.log('<UPDATE-CHECK> Could not read device ABIs: $err');
    return const [];
  }
}

// Naming Conventions?
bool _checkIfTheNewVersionIsActuallyAnUpgrade(String newVersion, String oldVersion) {
  final oldSplit = oldVersion.split('-');
  final newSplit = newVersion.split('-');

  final oldParts = oldSplit.first.split('.');
  final newParts = newSplit.first.split('.');

  if (oldParts.length < 3 || newParts.length < 3) {
    return false;
  }

  // Parse the version parts to integers
  final (oldMajor, oldMinor, oldPatch) =
      (int.tryParse(oldParts[0]), int.tryParse(oldParts[1]), int.tryParse(oldParts[2]));
  final (newMajor, newMinor, newPatch) =
      (int.tryParse(newParts[0]), int.tryParse(newParts[1]), int.tryParse(newParts[2]));

  // probably redundant but yeah!
  if (oldMajor == null ||
      oldMinor == null ||
      oldPatch == null ||
      newMajor == null ||
      newMinor == null ||
      newPatch == null) {
    return false;
  }

  // Compare by the parts
  if (newMajor > oldMajor) return true;
  if (newMajor < oldMajor) return false;

  // condition where the majors are same
  if (newMinor > oldMinor) return true;
  if (newMinor < oldMinor) return false;

  // condition where minors are same
  if (newPatch > oldPatch) return true;
  if (newPatch < oldPatch) return false;

  // condition where the versions are def equal. Time for stage check!

  final isTheOldOneStable = oldSplit.length == 1;
  final isTheNewOneStable = newSplit.length == 1;

  if (isTheNewOneStable && isTheOldOneStable) return false;

  // check if the the old ver is non-stable and new ver is stable
  if (!isTheOldOneStable && isTheNewOneStable) {
    return true; // new stable is always prefered than old unstables
  }

  if (isTheOldOneStable && !isTheNewOneStable) {
    return false; // prevent from downgrading to a beta of same version
  }

  final oldStage = oldSplit[1];
  final newStage = newSplit[1];

  final stageRegex = RegExp(r"([a-z]+)(\d+)?");

  final oldVerMatches = stageRegex.allMatches(oldStage);
  final newVerMatches = stageRegex.allMatches(newStage);

  if (oldVerMatches.isEmpty || newVerMatches.isEmpty) {
    return false;
  }

  final oldStageName = oldVerMatches.firstOrNull?.group(1) ?? '';
  final newStageName = newVerMatches.firstOrNull?.group(1) ?? '';
  final oldStageNum = int.tryParse(oldVerMatches.firstOrNull?.group(2) ?? '') ?? 0;
  final newStageNum = int.tryParse(newVerMatches.firstOrNull?.group(2) ?? '') ?? 0;

  // weights for stages, higher weight means newer stage. if the stage is not recognized, it gets 0 weight by default
  final stageWeights = {
    'alpha': 1,
    'beta': 2,
    // 'stable': 3,
    'rc': 3, // release candidate
  };

  final oldStageWeight = stageWeights[oldStageName] ?? 0;
  final newStageWeight = stageWeights[newStageName] ?? 0;

  if (newStageWeight > oldStageWeight) return true;

  if (newStageWeight < oldStageWeight) return false;

  return newStageNum > oldStageNum;
}

showUpdateSheet(BuildContext context, UpdateCheckResult data, {bool forceTrigger = false}) async {
  // trigger if forced for debug
  if (kDebugMode && !forceTrigger) {
    return;
  }

  if (Platform.isWindows || Platform.isLinux || await isTv()) {
    return showDialog(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        content: Container(
          width: MediaQuery.sizeOf(context).width / 3,
          child: UpdateSheet(
            data: data,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    showDragHandle: true,
    backgroundColor: appTheme.modalSheetBackgroundColor,
    isScrollControlled: true,
    context: context,
    builder: (context) {
      return UpdateSheet(
        data: data,
      );
    },
  );
}

// just for testing while development. Not used else where in prod
// ignore: unused_element
void _testVersionCheck() {
  print("--- STANDARD UPGRADES (Expected: true) ---");
  print("1.0.1 > 1.0.0: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.1", "1.0.0")}");
  print("1.1.0 > 1.0.9: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.1.0", "1.0.9")}");
  print("2.0.0 > 1.9.9: ${_checkIfTheNewVersionIsActuallyAnUpgrade("2.0.0", "1.9.9")}");

  print("\n--- STAGE UPGRADES (Expected: true) ---");
  print("1.0.0-beta > 1.0.0-alpha: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta", "1.0.0-alpha")}");
  print("1.0.0-rc > 1.0.0-beta:    ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-rc", "1.0.0-beta")}");
  print("1.0.0-beta2 > 1.0.0-beta1: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta2", "1.0.0-beta1")}");
  print(
      "1.0.0-beta10 > 1.0.0-beta2: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta10", "1.0.0-beta2")}"); // Numeric check

  print("\n--- GRADUATION (Expected: true) ---");
  print("1.0.0 > 1.0.0-rc:    ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0", "1.0.0-rc")}");
  print("1.0.0 > 1.0.0-beta:  ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0", "1.0.0-beta")}");
  print("1.0.0 > 1.0.0-alpha: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0", "1.0.0-alpha")}");

  print("\n--- NO CHANGE / EQUAL (Expected: false) ---");
  print("1.0.0 vs 1.0.0:       ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0", "1.0.0")}");
  print("1.0.0-beta vs 1.0.0-beta: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta", "1.0.0-beta")}");
  print("1.0.5 vs 1.0.5:       ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.5", "1.0.5")}");

  print("\n--- DOWNGRADES (Expected: false) ---");
  print("1.0.0 < 1.0.1:       ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0", "1.0.1")}");
  print("0.9.9 < 1.0.0:       ${_checkIfTheNewVersionIsActuallyAnUpgrade("0.9.9", "1.0.0")}");
  print("1.0.0-alpha < 1.0.0-beta: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-alpha", "1.0.0-beta")}");
  print("1.0.0-beta1 < 1.0.0-beta2: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta1", "1.0.0-beta2")}");

  print("\n--- STABILITY DOWNGRADES (Expected: false) ---");
  print("1.0.0-beta < 1.0.0:  ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta", "1.0.0")}");
  print("1.0.0-rc < 1.0.0:    ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-rc", "1.0.0")}");

  print("\n--- EDGE CASES (Expected: varies) ---");
  print(
      "1.0.0-beta (implicit 0) < 1.0.0-beta1: ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.0-beta1", "1.0.0-beta")}"); // True
  print(
      "1.0.1-alpha > 1.0.0 (Version > Stage): ${_checkIfTheNewVersionIsActuallyAnUpgrade("1.0.1-alpha", "1.0.0")}"); // True (Core version is higher)
}
