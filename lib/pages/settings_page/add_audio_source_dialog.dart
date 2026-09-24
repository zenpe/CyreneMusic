import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../features/audio_source/audio_source_feature.dart';
import '../../models/audio_source_config.dart';
import '../../services/app_config_service.dart';
import '../../services/audio_source_service.dart';
import '../../services/lx_music_source_parser.dart';
import '../../utils/theme_manager.dart';

class AddAudioSourceDialog extends StatefulWidget {
  final AudioSourceConfig? existingConfig;

  const AddAudioSourceDialog({super.key, this.existingConfig});

  @override
  State<AddAudioSourceDialog> createState() => _AddAudioSourceDialogState();
}

class _AddAudioSourceDialogState extends State<AddAudioSourceDialog> {
  static const List<String> _defaultQuickScriptUrls = [
    'https://zenn.cc.cd/pub/lx.js',
  ];

  final TextEditingController _scriptUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final LxMusicSourceParser _parser = LxMusicSourceParser();
  final AudioSourceController _controller = AudioSourceController();

  List<String> _quickScriptUrls = List<String>.from(_defaultQuickScriptUrls);
  bool _isProcessing = false;
  bool _needsApiKey = false;
  bool _isError = false;
  String? _statusMessage;
  LxMusicSourceConfig? _pendingConfig;
  String? _pendingSource;

  bool get _isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingConfig;
    if (existing != null) {
      _scriptUrlController.text = existing.scriptSource;
      _apiKeyController.text = existing.apiKey;
    }
    _loadQuickScriptPresets();
  }

  @override
  void dispose() {
    _scriptUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadQuickScriptPresets() async {
    try {
      final config = await AppConfigService().fetchPublicConfig();
      if (!mounted) return;
      final urls = config.lxScriptPresets
          .where(AudioSourceService.isValidUrl)
          .toSet()
          .toList();
      if (urls.isNotEmpty) setState(() => _quickScriptUrls = urls);
    } catch (_) {
      // Keep the bundled preset when remote configuration is unavailable.
    }
  }

  String _presetLabel(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final file = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return file.isEmpty ? uri.host : '${uri.host}/$file';
  }

  void _selectPreset(String url) {
    setState(() {
      _scriptUrlController.text = url;
      _scriptUrlController.selection = TextSelection.collapsed(
        offset: url.length,
      );
      _resetDraft();
    });
  }

  void _resetDraft() {
    _needsApiKey = false;
    _pendingConfig = null;
    _pendingSource = null;
    _statusMessage = null;
    _isError = false;
  }

  Future<void> _importFromUrl() async {
    final url = _scriptUrlController.text.trim();
    if (!AudioSourceService.isValidUrl(url)) {
      _setStatus('请输入有效的脚本链接', isError: true);
      return;
    }
    await _run(() async {
      final config = await _parser.parseFromUrl(url);
      if (config == null || !config.isValid) {
        _setStatus('无法解析该洛雪脚本', isError: true);
        return;
      }
      await _handleConfig(config, url);
    }, progress: '正在获取脚本...');
  }

  Future<void> _importFromFile() async {
    await _run(() async {
      final config = await _parser.parseFromFile();
      if (config == null) {
        _setStatus(null);
        return;
      }
      if (!config.isValid) {
        _setStatus('无法解析该洛雪脚本', isError: true);
        return;
      }
      await _handleConfig(config, config.source);
    }, progress: '正在读取脚本...');
  }

  Future<void> _handleConfig(LxMusicSourceConfig config, String source) async {
    if (config.apiKey.isEmpty && config.scriptContent.isEmpty) {
      setState(() {
        _pendingConfig = config;
        _pendingSource = source;
        _needsApiKey = true;
        _statusMessage = '请输入该音源所需的 API Key';
        _isError = false;
      });
      return;
    }
    await _save(config, source, config.apiKey);
  }

  Future<void> _confirmApiKey() async {
    final config = _pendingConfig;
    final source = _pendingSource;
    if (config == null || source == null) return;
    await _run(
      () => _save(config, source, _apiKeyController.text.trim()),
      progress: '正在保存...',
    );
  }

  Future<void> _save(
    LxMusicSourceConfig parsed,
    String source,
    String apiKey,
  ) async {
    final config = _isEditing
        ? widget.existingConfig!.copyWith(
            type: AudioSourceType.lxmusic,
            name: parsed.name,
            version: parsed.version,
            url: parsed.apiUrl,
            apiKey: apiKey,
            scriptSource: source,
            scriptContent: parsed.scriptContent,
            author: parsed.author,
            description: parsed.description,
            urlPathTemplate: parsed.urlPathTemplate,
          )
        : AudioSourceConfig(
            id: _controller.createSourceId(),
            type: AudioSourceType.lxmusic,
            name: parsed.name,
            version: parsed.version,
            url: parsed.apiUrl,
            apiKey: apiKey,
            scriptSource: source,
            scriptContent: parsed.scriptContent,
            author: parsed.author,
            description: parsed.description,
            urlPathTemplate: parsed.urlPathTemplate,
          );
    final result = await _controller.saveSource(config, isEditing: _isEditing);
    if (!result.isSuccess) {
      throw Exception(result.errorMessage ?? '保存音源失败');
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String progress,
  }) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
      _resetDraft();
      _statusMessage = progress;
    });
    try {
      await action();
    } catch (error) {
      _setStatus(_formatError(error), isError: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _formatError(Object error) {
    final message = error.toString();
    return message.startsWith('Exception: ')
        ? message.substring('Exception: '.length)
        : message;
  }

  void _setStatus(String? message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _isError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      return _buildFluentDialog(context);
    }
    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      return _buildCupertinoDialog(context);
    }
    return _buildMaterialDialog(context);
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(_isEditing ? '替换洛雪音源' : '导入洛雪音源'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue:
                    _quickScriptUrls.contains(_scriptUrlController.text)
                    ? _scriptUrlController.text
                    : null,
                decoration: const InputDecoration(labelText: '预设'),
                items: _quickScriptUrls
                    .map(
                      (url) => DropdownMenuItem(
                        value: url,
                        child: Text(_presetLabel(url)),
                      ),
                    )
                    .toList(),
                onChanged: _isProcessing
                    ? null
                    : (url) {
                        if (url != null) _selectPreset(url);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _scriptUrlController,
                enabled: !_isProcessing,
                decoration: const InputDecoration(
                  labelText: '脚本链接',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _importFromUrl,
                      icon: const Icon(Icons.download),
                      label: Text(_isEditing ? '下载并替换' : '从链接导入'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _importFromFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择文件'),
                    ),
                  ),
                ],
              ),
              if (_needsApiKey) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKeyController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isProcessing ? null : _confirmApiKey,
                  child: const Text('确认并保存'),
                ),
              ],
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _isError ? colors.error : colors.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }

  Widget _buildCupertinoDialog(BuildContext context) {
    final statusColor = _isError
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.activeBlue.resolveFrom(context);
    return CupertinoPopupSurface(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 480,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? '替换洛雪音源' : '导入洛雪音源',
                        style: CupertinoTheme.of(
                          context,
                        ).textTheme.navTitleTextStyle,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: _isProcessing
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Icon(CupertinoIcons.xmark),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView(
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: _isProcessing
                            ? null
                            : () => _selectPreset(_quickScriptUrls.first),
                        child: Text(_presetLabel(_quickScriptUrls.first)),
                      ),
                      CupertinoTextField(
                        controller: _scriptUrlController,
                        enabled: !_isProcessing,
                        placeholder: '脚本链接',
                        prefix: const Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Icon(CupertinoIcons.link),
                        ),
                      ),
                      const SizedBox(height: 16),
                      CupertinoButton.filled(
                        onPressed: _isProcessing ? null : _importFromUrl,
                        child: Text(_isEditing ? '下载并替换' : '从链接导入'),
                      ),
                      CupertinoButton(
                        onPressed: _isProcessing ? null : _importFromFile,
                        child: const Text('选择本地文件'),
                      ),
                      if (_needsApiKey) ...[
                        CupertinoTextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          placeholder: 'API Key',
                        ),
                        const SizedBox(height: 12),
                        CupertinoButton.filled(
                          onPressed: _isProcessing ? null : _confirmApiKey,
                          child: const Text('确认并保存'),
                        ),
                      ],
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _statusMessage!,
                          style: TextStyle(color: statusColor),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFluentDialog(BuildContext context) {
    return fluent.ContentDialog(
      title: Text(_isEditing ? '替换洛雪音源' : '导入洛雪音源'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            fluent.ComboBox<String>(
              placeholder: const Text('选择预设'),
              items: _quickScriptUrls
                  .map(
                    (url) => fluent.ComboBoxItem(
                      value: url,
                      child: Text(_presetLabel(url)),
                    ),
                  )
                  .toList(),
              onChanged: _isProcessing
                  ? null
                  : (url) {
                      if (url != null) _selectPreset(url);
                    },
            ),
            const SizedBox(height: 12),
            fluent.TextBox(
              controller: _scriptUrlController,
              enabled: !_isProcessing,
              placeholder: '脚本链接',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.link),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: fluent.FilledButton(
                    onPressed: _isProcessing ? null : _importFromUrl,
                    child: Text(_isEditing ? '下载并替换' : '从链接导入'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: fluent.Button(
                    onPressed: _isProcessing ? null : _importFromFile,
                    child: const Text('选择文件'),
                  ),
                ),
              ],
            ),
            if (_needsApiKey) ...[
              const SizedBox(height: 16),
              fluent.PasswordBox(
                controller: _apiKeyController,
                placeholder: 'API Key',
              ),
              const SizedBox(height: 12),
              fluent.FilledButton(
                onPressed: _isProcessing ? null : _confirmApiKey,
                child: const Text('确认并保存'),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Text(_statusMessage!),
            ],
          ],
        ),
      ),
      actions: [
        fluent.Button(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
