import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/track.dart';

enum LxRuntimeFailureKind {
  notReady,
  timeout,
  scriptRejected,
  invalidTrackIdentifier,
  requestFailed,
}

class LxRuntimeFailure {
  final LxRuntimeFailureKind kind;
  final String message;

  const LxRuntimeFailure({required this.kind, required this.message});
}

LxRuntimeFailure classifyLxRuntimeFailure(Object error) {
  final message = error.toString();
  final kind = error is TimeoutException
      ? LxRuntimeFailureKind.timeout
      : error is MissingTrackSourceIdentifierException
      ? LxRuntimeFailureKind.invalidTrackIdentifier
      : message.contains('完整性验证失败')
      ? LxRuntimeFailureKind.scriptRejected
      : message.contains('未就绪') || message.contains('无法初始化')
      ? LxRuntimeFailureKind.notReady
      : LxRuntimeFailureKind.requestFailed;
  return LxRuntimeFailure(kind: kind, message: message);
}

abstract class LxRuntime {
  bool get isInitialized;
  bool get isScriptReady;
  bool get isAvailable;
  LxScriptInfo? get currentScript;
  LxRuntimeFailure? get lastFailure;

  Future<void> initialize();
  Future<LxScriptInfo?> loadScript(String scriptContent);
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
  });
  Future<void> dispose();
}

class LxScriptParser {
  static LxScriptInfo parse(String script) {
    String name = '未知音源';
    String version = '1.0.0';
    String author = '';
    String description = '';
    String homepage = '';

    final commentMatch = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(script);
    if (commentMatch != null) {
      final comment = commentMatch.group(0)!;

      final nameMatch = RegExp(r'@name\s+(.+)').firstMatch(comment);
      if (nameMatch != null) name = nameMatch.group(1)!.trim();

      final versionMatch = RegExp(r'@version\s+(.+)').firstMatch(comment);
      if (versionMatch != null) version = versionMatch.group(1)!.trim();

      final authorMatch = RegExp(r'@author\s+(.+)').firstMatch(comment);
      if (authorMatch != null) author = authorMatch.group(1)!.trim();

      final descMatch = RegExp(r'@description\s+(.+)').firstMatch(comment);
      if (descMatch != null) description = descMatch.group(1)!.trim();

      final homeMatch = RegExp(r'@homepage\s+(.+)').firstMatch(comment);
      if (homeMatch != null) homepage = homeMatch.group(1)!.trim();
    }

    return LxScriptInfo(
      name: name,
      version: version,
      author: author,
      description: description,
      homepage: homepage,
      script: script,
    );
  }
}

@immutable
class LxScriptInfo {
  final String name;
  final String version;
  final String author;
  final String description;
  final String homepage;
  final String script;

  /// 洛雪格式的支持音源列表 (wy, tx, kg, kw, mg)
  final List<String> supportedSources;

  /// 脚本支持的音质列表 (128k, 320k, flac, flac24bit)
  /// 这是所有平台支持音质的并集
  final List<String> supportedQualities;

  /// 每个平台支持的音质映射 { 'wy': ['128k', '320k', 'flac'], ... }
  final Map<String, List<String>> platformQualities;

  const LxScriptInfo({
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.homepage = '',
    required this.script,
    this.supportedSources = const [],
    this.supportedQualities = const [],
    this.platformQualities = const {},
  });

  static String? _lxToInternalPlatform(String lxSource) {
    switch (lxSource) {
      case 'wy':
        return 'netease';
      case 'tx':
        return 'qq';
      case 'kg':
        return 'kugou';
      case 'kw':
        return 'kuwo';
      case 'mg':
        return null;
      default:
        return null;
    }
  }

  List<String> get supportedPlatforms {
    return supportedSources
        .map((s) => _lxToInternalPlatform(s))
        .where((p) => p != null)
        .cast<String>()
        .toList();
  }

  List<String> getQualitiesForPlatform(String lxSource) {
    return platformQualities[lxSource] ?? supportedQualities;
  }

  @override
  String toString() {
    return 'LxScriptInfo(name: $name, version: $version, sources: $supportedSources, qualities: $supportedQualities)';
  }
}
