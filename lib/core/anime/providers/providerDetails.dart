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
  }) : allowedHosts = List<String>.unmodifiable(allowedHosts);

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
    );
  }

  String toJson() => json.encode(toMap());

  factory ProviderDetails.fromJson(String source) => ProviderDetails.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ProviderDetails(name: $name, identifier: $identifier, version: $version, icon: $icon, code: $code, supportDownloads: $supportDownloads, scriptType: $scriptType, allowedHosts: $allowedHosts, enabled: $enabled, repositoryUrl: $repositoryUrl, sourceSha256: $sourceSha256)';
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
      enabled.hashCode ^
      repositoryUrl.hashCode ^
      sourceSha256.hashCode;
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
      other.enabled == enabled &&
      other.repositoryUrl == repositoryUrl &&
      other.sourceSha256 == sourceSha256;
  }

  static bool _sameHosts(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
