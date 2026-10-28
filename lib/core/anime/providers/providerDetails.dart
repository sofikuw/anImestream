// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

class ProviderDetails {
  final String name;
  final String identifier;
  final String version;
  final String? icon;
  final String? code;
  final bool supportDownloads;
  final String scriptType;
  final List<String> allowedHosts;
  final bool enabled;
  final String? repositoryUrl;
  final String? sourceSha256;

  /// Content types this provider serves: "anime" and/or "manga".
  ///
  /// Defaults to ["anime"] so records written before this field existed -- and
  /// the built-in Dart providers -- keep behaving as anime-only.
  final List<String> contentTypes;

  /// Runtime dialect the [code] is written against.
  ///
  /// `animestream` is the native module contract (`module.exports` with
  /// `search`/`getStreams`). `mangayomi` is a MangaYomi JavaScript extension
  /// (`class DefaultExtension extends MProvider`). Defaults to `animestream`
  /// so records written before this field existed keep loading.
  final String format;

  bool get isMangayomi => format == 'mangayomi';

  /// Catalog-declared source site metadata, used by the MangaYomi shim to
  /// populate `this.source`. All null for native providers.
  final String? baseUrl;
  final String? apiUrl;
  final String? lang;
  final String? dateFormat;
  final String? dateFormatLocale;

  ProviderDetails({
    required this.name,
    required this.identifier,
    required this.version,
    this.icon,
    this.code,
    this.supportDownloads = false,
    this.scriptType = 'dart',
    List<String> allowedHosts = const <String>[],
    this.enabled = true,
    this.repositoryUrl,
    this.sourceSha256,
    List<String> contentTypes = const <String>['anime'],
    this.format = 'animestream',
    this.baseUrl,
    this.apiUrl,
    this.lang,
    this.dateFormat,
    this.dateFormatLocale,
  })  : allowedHosts = List<String>.unmodifiable(allowedHosts),
        contentTypes = List<String>.unmodifiable(contentTypes);

  ProviderDetails copyWith({
    String? name,
    String? identifier,
    String? version,
    String? icon,
    String? code,
    bool? supportDownloads,
    String? scriptType,
    List<String>? allowedHosts,
    bool? enabled,
    String? repositoryUrl,
    String? sourceSha256,
    List<String>? contentTypes,
    String? format,
    String? baseUrl,
    String? apiUrl,
    String? lang,
    String? dateFormat,
    String? dateFormatLocale,
  }) {
    return ProviderDetails(
      name: name ?? this.name,
      identifier: identifier ?? this.identifier,
      version: version ?? this.version,
      icon: icon ?? this.icon,
      code: code ?? this.code,
      supportDownloads: supportDownloads ?? this.supportDownloads,
      scriptType: scriptType ?? this.scriptType,
      allowedHosts: allowedHosts ?? this.allowedHosts,
      enabled: enabled ?? this.enabled,
      repositoryUrl: repositoryUrl ?? this.repositoryUrl,
      sourceSha256: sourceSha256 ?? this.sourceSha256,
      contentTypes: contentTypes ?? this.contentTypes,
      format: format ?? this.format,
      baseUrl: baseUrl ?? this.baseUrl,
      apiUrl: apiUrl ?? this.apiUrl,
      lang: lang ?? this.lang,
      dateFormat: dateFormat ?? this.dateFormat,
      dateFormatLocale: dateFormatLocale ?? this.dateFormatLocale,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'identifier': identifier,
      'version': version,
      'icon': icon,
      'code': code,
      'supportDownloads': supportDownloads,
      'scriptType': scriptType,
      'allowedHosts': allowedHosts,
      'enabled': enabled,
      'repositoryUrl': repositoryUrl,
      'sourceSha256': sourceSha256,
      'contentTypes': contentTypes,
      'format': format,
      'baseUrl': baseUrl,
      'apiUrl': apiUrl,
      'lang': lang,
      'dateFormat': dateFormat,
      'dateFormatLocale': dateFormatLocale,
    };
  }

  factory ProviderDetails.fromMap(Map<String, dynamic> map) {
    return ProviderDetails(
      name: map['name'] as String,
      identifier: map['identifier'] as String,
      version: map['version'] as String,
      icon: map['icon'] != null ? map['icon'] as String : null,
      code: map['code'] != null ? map['code'] as String : null,
      supportDownloads: (map['supportDownloads'] ?? false) as bool,
      scriptType: (map['scriptType'] as String?) ?? 'dart',
      allowedHosts: map['allowedHosts'] is List
          ? (map['allowedHosts'] as List).whereType<String>().toList()
          : const <String>[],
      enabled: (map['enabled'] ?? true) as bool,
      repositoryUrl: map['repositoryUrl'] as String?,
      sourceSha256: map['sourceSha256'] as String?,
      contentTypes: map['contentTypes'] is List
          ? (map['contentTypes'] as List).whereType<String>().toList()
          : const <String>['anime'],
      format: (map['format'] as String?) ?? 'animestream',
      baseUrl: map['baseUrl'] as String?,
      apiUrl: map['apiUrl'] as String?,
      lang: map['lang'] as String?,
      dateFormat: map['dateFormat'] as String?,
      dateFormatLocale: map['dateFormatLocale'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory ProviderDetails.fromJson(String source) => ProviderDetails.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ProviderDetails(name: $name, identifier: $identifier, version: $version, icon: $icon, code: $code, supportDownloads: $supportDownloads, scriptType: $scriptType, allowedHosts: $allowedHosts, enabled: $enabled, repositoryUrl: $repositoryUrl, sourceSha256: $sourceSha256, contentTypes: $contentTypes, format: $format, baseUrl: $baseUrl, apiUrl: $apiUrl, lang: $lang, dateFormat: $dateFormat, dateFormatLocale: $dateFormatLocale)';
  }

  @override
  int get hashCode {
    return name.hashCode ^
      identifier.hashCode ^
      version.hashCode ^
      icon.hashCode ^
      code.hashCode ^
      supportDownloads.hashCode ^
      scriptType.hashCode ^
      Object.hashAll(allowedHosts) ^
      Object.hashAll(contentTypes) ^
      enabled.hashCode ^
      repositoryUrl.hashCode ^
      sourceSha256.hashCode ^
      format.hashCode ^
      baseUrl.hashCode ^
      apiUrl.hashCode ^
      lang.hashCode ^
      dateFormat.hashCode ^
      dateFormatLocale.hashCode;
  }

  @override
  bool operator ==(covariant ProviderDetails other) {
    if (identical(this, other)) return true;
  
    return 
      other.name == name &&
      other.identifier == identifier &&
      other.version == version &&
      other.icon == icon &&
      other.code == code &&
      other.supportDownloads == supportDownloads &&
      other.scriptType == scriptType &&
      _sameHosts(other.allowedHosts, allowedHosts) &&
      _sameHosts(other.contentTypes, contentTypes) &&
      other.enabled == enabled &&
      other.repositoryUrl == repositoryUrl &&
      other.sourceSha256 == sourceSha256 &&
      other.format == format &&
      other.baseUrl == baseUrl &&
      other.apiUrl == apiUrl &&
      other.lang == lang &&
      other.dateFormat == dateFormat &&
      other.dateFormatLocale == dateFormatLocale;
  }

  static bool _sameHosts(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
