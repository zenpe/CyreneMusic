
import '../services/audio_source_service.dart';

/// Audio Source Configuration Model
class AudioSourceConfig {
  /// Unique ID
  final String id;
  
  /// Source Type
  final AudioSourceType type;
  
  /// Display Name
  final String name;
  
  /// Base API URL
  final String url;
  
  /// API Key (optional)
  final String apiKey;
  
  /// 当前解析器支持的播放平台列表。
  /// 搜索平台由 SearchProviderCatalog 独立管理。
  /// 可选值: 'netease', 'apple', 'qq', 'kugou', 'kuwo', 'spotify'
  final List<String> supportedPlatforms;
  
  // --- LxMusic Specific Fields ---
  final String version;
  final String author;
  final String description;
  final String scriptSource;
  final String scriptContent;
  final String urlPathTemplate;

  AudioSourceConfig({
    required this.id,
    required this.type,
    required this.name,
    required this.url,
    this.apiKey = '',
    this.supportedPlatforms = const [],
    this.version = '',
    this.author = '',
    this.description = '',
    this.scriptSource = '',
    this.scriptContent = '',
    this.urlPathTemplate = '',
  });

  /// Create a copy with some fields updated
  AudioSourceConfig copyWith({
    AudioSourceType? type,
    String? name,
    String? url,
    String? apiKey,
    List<String>? supportedPlatforms,
    String? version,
    String? author,
    String? description,
    String? scriptSource,
    String? scriptContent,
    String? urlPathTemplate,
  }) {
    return AudioSourceConfig(
      id: id,
      type: type ?? this.type,
      name: name ?? this.name,
      url: url ?? this.url,
      apiKey: apiKey ?? this.apiKey,
      supportedPlatforms: supportedPlatforms ?? this.supportedPlatforms,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      scriptSource: scriptSource ?? this.scriptSource,
      scriptContent: scriptContent ?? this.scriptContent,
      urlPathTemplate: urlPathTemplate ?? this.urlPathTemplate,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'name': name,
      'url': url,
      'apiKey': apiKey,
      'supportedPlatforms': supportedPlatforms,
      'version': version,
      'author': author,
      'description': description,
      'scriptSource': scriptSource,
      'scriptContent': scriptContent,
      'urlPathTemplate': urlPathTemplate,
    };
  }

  /// Create from JSON
  factory AudioSourceConfig.fromJson(Map<String, dynamic> json) {
    return AudioSourceConfig(
      id: json['id'] as String,
      type: AudioSourceType.values[json['type'] as int],
      name: json['name'] as String,
      url: json['url'] as String,
      apiKey: json['apiKey'] as String? ?? '',
      supportedPlatforms: (json['supportedPlatforms'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ?? [],
      version: json['version'] as String? ?? '',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      scriptSource: json['scriptSource'] as String? ?? '',
      scriptContent: json['scriptContent'] as String? ?? '',
      urlPathTemplate: json['urlPathTemplate'] as String? ?? '',
    );
  }
}
