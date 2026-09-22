import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../features/audio_source/audio_source_feature.dart';
import '../../models/audio_source_config.dart';
import '../../services/app_config_service.dart';
import '../../services/audio_source_service.dart';
import '../../services/cyrene_config_service.dart';
import '../../services/lx_music_source_parser.dart';
import '../../utils/theme_manager.dart';

/// 添加/编辑音源对话框
class AddAudioSourceDialog extends StatefulWidget {
  final AudioSourceConfig? existingConfig;

  const AddAudioSourceDialog({super.key, this.existingConfig});

  @override
  State<AddAudioSourceDialog> createState() => _AddAudioSourceDialogState();
}

class _AddAudioSourceDialogState extends State<AddAudioSourceDialog> {
  static const List<String> _defaultLxQuickScriptUrls = [
    'https://zenn.cc.cd/pub/lx.js',
  ];
  late AudioSourceType _selectedType;
  List<String> _lxQuickScriptUrls = List<String>.from(
    _defaultLxQuickScriptUrls,
  );

  // Controllers
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _lxScriptUrlController = TextEditingController();
  final TextEditingController _lxApiKeyController = TextEditingController();
  final TextEditingController _tuneHubApiKeyController =
      TextEditingController();
  final TextEditingController _omniParseApiKeyController =
      TextEditingController();

  // Services
  final LxMusicSourceParser _lxParser = LxMusicSourceParser();
  final AudioSourceController _audioSourceController = AudioSourceController();

  // State
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isError = false;

  // LxMusic specific
  bool _needsApiKeyInput = false;
  LxMusicSourceConfig? _pendingLxConfig;
  String? _pendingScriptSource;

  List<AudioSourceType> get _availableTypes => AudioSourceType.values
      .where((t) => t != AudioSourceType.navidrome)
      .toList();

  bool get _isEditing => widget.existingConfig != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final config = widget.existingConfig!;
      _selectedType = config.type;
      _nameController.text = config.name;
      _urlController.text = config.url;
      if (config.type == AudioSourceType.lxmusic) {
        _lxScriptUrlController.text = config.scriptSource;
        _lxApiKeyController.text = config.apiKey;
      } else if (config.type == AudioSourceType.tunehub) {
        _tuneHubApiKeyController.text = config.apiKey;
      } else if (config.type == AudioSourceType.omniparse) {
        _omniParseApiKeyController.text = config.apiKey;
      }
    } else {
      _selectedType = AudioSourceType.lxmusic;
    }
    _loadLxQuickScriptPresets();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _lxScriptUrlController.dispose();
    _lxApiKeyController.dispose();
    _tuneHubApiKeyController.dispose();
    _omniParseApiKeyController.dispose();
    super.dispose();
  }

  // --- Logic ---

  Future<void> _loadLxQuickScriptPresets() async {
    try {
      final config = await AppConfigService().fetchPublicConfig();
      if (!mounted) return;
      final normalized = config.lxScriptPresets
          .where((item) => AudioSourceService.isValidUrl(item))
          .toSet()
          .toList();
      if (normalized.isEmpty) return;
      setState(() {
        _lxQuickScriptUrls = normalized;
      });
    } catch (_) {
      // 使用本地默认预设
    }
  }

  String _lxQuickPresetLabel(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    final fileName = (uri?.pathSegments.isNotEmpty ?? false)
        ? uri!.pathSegments.last
        : url;
    if (host.isEmpty) return fileName;
    return '$host/$fileName';
  }

  void _applyLxQuickScriptUrl(String url) {
    setState(() {
      _lxScriptUrlController.text = url;
      _lxScriptUrlController.selection = TextSelection.collapsed(
        offset: url.length,
      );
      _statusMessage = null;
      _isError = false;
      _needsApiKeyInput = false;
      _pendingLxConfig = null;
      _pendingScriptSource = null;
    });
  }

  Future<void> _importLxScriptFromUrl() async {
    final scriptUrl = _lxScriptUrlController.text.trim();
    if (scriptUrl.isEmpty) {
      _setStatus('请输入脚本链接', isError: true);
      return;
    }

    await _runWithProcessing(
      () async {
      final config = await _lxParser.parseFromUrl(scriptUrl);
      if (config == null || !config.isValid) {
        _setStatus('解析失败：无法从脚本中提取 API 地址', isError: true);
        return;
      }

      await _handleLxConfig(config, scriptUrl);
    },
      statusMessage: '正在获取脚本...',
      resetLxDraft: true,
      onError: (e) {
      _setErrorFromException('导入失败', e, onRetry: _importLxScriptFromUrl);
    });
  }

  Future<void> _importLxScriptFromFile() async {
    await _runWithProcessing(
      () async {
      final config = await _lxParser.parseFromFile();
      if (config == null) {
        _setStatus(null);
        return;
      }

      if (!config.isValid) {
        _setStatus('解析失败：文件无效', isError: true);
        return;
      }

      await _handleLxConfig(config, config.source);
    },
      statusMessage: '正在读取文件...',
      resetLxDraft: true,
      onError: (e) {
      _setErrorFromException('导入失败', e, onRetry: _importLxScriptFromFile);
    });
  }

  Future<void> _handleLxConfig(
    LxMusicSourceConfig config,
    String sourcePath,
  ) async {
    // 检查是否需要 API Key
    final needsKey = config.apiKey.isEmpty && config.scriptContent.isEmpty;

    if (needsKey) {
      if (!mounted) return;
      setState(() {
        _pendingLxConfig = config;
        _pendingScriptSource = sourcePath;
        _needsApiKeyInput = true;
        _statusMessage = '此脚本需要手动输入 API Key';
        _isError = false;
      });
    } else {
      await _saveLxSource(config, sourcePath, config.apiKey);
    }
  }

  Future<void> _confirmLxApiKey() async {
    if (_pendingLxConfig == null) return;
    final apiKey = _lxApiKeyController.text.trim();
    await _runWithProcessing(
      () async {
        await _saveLxSource(_pendingLxConfig!, _pendingScriptSource!, apiKey);
      },
      onError: (e) {
        _setErrorFromException('保存失败', e, onRetry: _confirmLxApiKey);
      },
    );
  }

  Future<void> _saveLxSource(
    LxMusicSourceConfig config,
    String sourcePath,
    String apiKey,
  ) async {
    final sourceConfig = _isEditing
        ? widget.existingConfig!.copyWith(
            name: config.name,
            version: config.version,
            url: config.apiUrl,
            apiKey: apiKey,
            scriptSource: sourcePath,
            scriptContent: config.scriptContent,
            author: config.author,
            description: config.description,
            urlPathTemplate: config.urlPathTemplate,
          )
        : AudioSourceConfig(
            id: _audioSourceController.createSourceId(),
            type: AudioSourceType.lxmusic,
            name: config.name,
            version: config.version,
            url: config.apiUrl,
            apiKey: apiKey,
            scriptSource: sourcePath,
            scriptContent: config.scriptContent,
            author: config.author,
            description: config.description,
            urlPathTemplate: config.urlPathTemplate,
          );
    await _persistSource(sourceConfig);
    _completeSaveAndClose(sourceConfig.name);
  }

  Future<void> _saveTuneHubSource() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !AudioSourceService.isValidUrl(url)) {
      _setStatus('请输入有效的 URL', isError: true);
      return;
    }

    final apiKey = _tuneHubApiKeyController.text.trim();

    await _runWithProcessing(
      () async {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode >= 200 && response.statusCode < 400) {
        final sourceConfig = _isEditing
            ? widget.existingConfig!.copyWith(
                name: _nameController.text.isEmpty
                    ? 'TuneHub'
                    : _nameController.text,
                url: url,
                apiKey: apiKey,
              )
            : AudioSourceConfig(
                id: _audioSourceController.createSourceId(),
                type: AudioSourceType.tunehub,
                name: _nameController.text.isEmpty
                    ? 'TuneHub'
                    : _nameController.text,
                url: url,
                apiKey: apiKey,
              );
        await _persistSource(sourceConfig);
        _completeSaveAndClose(sourceConfig.name);
      } else {
        _setStatus(
          '连接测试失败：HTTP ${response.statusCode}',
          isError: true,
          showGlobal: true,
          onRetry: _saveTuneHubSource,
        );
      }
    },
      onError: (e) {
      _setErrorFromException(
        '连接测试失败',
        e,
        onRetry: _saveTuneHubSource,
      );
    });
  }

  Future<void> _saveOmniParseSource() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !AudioSourceService.isValidUrl(url)) {
      _setStatus('请输入有效的 URL', isError: true);
      return;
    }

    final apiKey = _omniParseApiKeyController.text.trim();

    final sourceConfig = _isEditing
        ? widget.existingConfig!.copyWith(
            name: _nameController.text.isEmpty ? 'OmniParse' : _nameController.text,
            url: url,
            apiKey: apiKey,
          )
        : AudioSourceConfig(
            id: _audioSourceController.createSourceId(),
            type: AudioSourceType.omniparse,
            name: _nameController.text.isEmpty ? 'OmniParse' : _nameController.text,
            url: url,
            apiKey: apiKey,
          );
    await _runWithProcessing(
      () async {
        await _persistSource(sourceConfig);
        _completeSaveAndClose(sourceConfig.name);
      },
      onError: (e) {
        _setErrorFromException('保存失败', e, onRetry: _saveOmniParseSource);
      },
    );
  }

  Future<void> _persistSource(AudioSourceConfig sourceConfig) async {
    final result = await _audioSourceController.saveSource(
      sourceConfig,
      isEditing: _isEditing,
    );
    if (!result.isSuccess) {
      throw Exception(result.errorMessage ?? (_isEditing ? '保存音源失败' : '添加音源失败'));
    }
  }

  Future<void> _runWithProcessing(
    Future<void> Function() action, {
    String? statusMessage,
    bool resetLxDraft = false,
    void Function(Object error)? onError,
  }) async {
    if (_isProcessing) return;
    if (mounted) {
      setState(() {
        _isProcessing = true;
        if (statusMessage != null) {
          _statusMessage = statusMessage;
          _isError = false;
        }
        if (resetLxDraft) {
          _needsApiKeyInput = false;
          _pendingLxConfig = null;
          _pendingScriptSource = null;
        }
      });
    }

    try {
      await action();
    } catch (error) {
      if (onError != null) {
        onError(error);
      } else {
        rethrow;
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _closeDialogIfMounted() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _formatErrorText(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return '未知错误';
    if (raw.startsWith('Exception:')) {
      return raw.substring('Exception:'.length).trim();
    }
    return raw;
  }

  void _setErrorFromException(
    String prefix,
    Object error, {
    Future<void> Function()? onRetry,
  }) {
    _setStatus(
      '$prefix：${_formatErrorText(error)}',
      isError: true,
      showGlobal: true,
      onRetry: onRetry,
    );
  }

  String _buildSaveSuccessMessage(String sourceName) {
    final label = sourceName.trim().isEmpty
        ? (_isEditing ? '音源' : '新音源')
        : sourceName.trim();
    return _isEditing ? '$label 已保存' : '$label 已添加';
  }

  void _completeSaveAndClose(String sourceName) {
    final successMessage = _buildSaveSuccessMessage(sourceName);
    _setStatus(successMessage, isError: false);
    _showGlobalSuccess(successMessage);
    _closeDialogIfMounted();
  }

  void _showGlobalError(
    String message, {
    Future<void> Function()? onRetry,
  }) {
    if (!mounted) return;
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      fluent.displayInfoBar(
        context,
        duration: const Duration(seconds: 4),
        builder: (context, close) => fluent.InfoBar(
          title: const Text('操作失败'),
          content: Text(message),
          severity: fluent.InfoBarSeverity.error,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null)
                fluent.Button(
                  onPressed: () async {
                    close();
                    if (!mounted) return;
                    await onRetry();
                  },
                  child: const Text('重试'),
                ),
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.clear),
                onPressed: close,
              ),
            ],
          ),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          action: onRetry == null
              ? null
              : SnackBarAction(
                  label: '重试',
                  onPressed: () async {
                    if (!mounted) return;
                    await onRetry();
                  },
                ),
        ),
      );
      return;
    }

    if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('操作失败'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
            if (onRetry != null)
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  if (!mounted) return;
                  await onRetry();
                },
                child: const Text('重试'),
              ),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('操作失败'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                await onRetry();
              },
              child: const Text('重试'),
            ),
        ],
      ),
    );
  }

  void _showGlobalSuccess(String message) {
    if (!mounted) return;
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      fluent.displayInfoBar(
        context,
        duration: const Duration(seconds: 2),
        builder: (context, close) => fluent.InfoBar(
          title: const Text('已完成'),
          content: Text(message),
          severity: fluent.InfoBarSeverity.success,
          action: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.clear),
            onPressed: close,
          ),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 导入 .cyrene 加密配置文件
  Future<void> _importCyreneConfig() async {
    await _runWithProcessing(
      () async {
        // 选择 .cyrene 文件
        // 移动端不支持自定义扩展名过滤，使用 FileType.any
        final isMobile = Platform.isAndroid || Platform.isIOS;
        final result = await FilePicker.platform.pickFiles(
          type: isMobile ? FileType.any : FileType.custom,
          allowedExtensions: isMobile ? null : ['cyrene'],
          allowMultiple: false,
        );

        if (result == null || result.files.isEmpty) {
          return;
        }

        final file = result.files.first;
        if (file.path == null) {
          _setStatus('无法读取文件', isError: true, showGlobal: true);
          return;
        }

        // 读取文件内容
        final bytes = await File(file.path!).readAsBytes();

        // 解密配置
        final config = CyreneConfigService().decrypt(bytes);
        if (config == null) {
          _setStatus('配置文件无效或已损坏', isError: true, showGlobal: true);
          return;
        }

        if (!mounted) return;
        // 填充表单
        setState(() {
          _selectedType = AudioSourceType.omniparse;
          _nameController.text = config.name;
          _urlController.text = config.url;
          _omniParseApiKeyController.text = config.apiKey;
          _statusMessage = '配置已导入：${config.name}';
          _isError = false;
        });
        _showGlobalSuccess('配置已导入：${config.name}');
      },
      statusMessage: '正在导入配置...',
      onError: (e) {
        _setErrorFromException('导入失败', e, onRetry: _importCyreneConfig);
      },
    );
  }

  void _setStatus(
    String? msg, {
    bool isError = false,
    bool showGlobal = false,
    Future<void> Function()? onRetry,
  }) {
    if (!mounted) return;
    setState(() {
      _statusMessage = msg;
      _isError = isError;
    });
    if (isError && showGlobal && msg != null && msg.isNotEmpty) {
      _showGlobalError(msg, onRetry: onRetry);
    }
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    if (themeManager.isFluentFramework && Platform.isWindows) {
      return _buildFluentDialog(context);
    } else if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isMacOS || Platform.isAndroid)) {
      // Checking Android too for manual theme switch cases
      return _buildCupertinoDialog(context);
    }
    return _buildMaterialDialog(context);
  }

  Widget _buildFluentDialog(BuildContext context) {
    return fluent.ContentDialog(
      title: Text(_isEditing ? '编辑音源' : '添加音源'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type Selector (Disabled if editing)
            fluent.InfoLabel(
              label: '音源类型',
              child: fluent.ComboBox<AudioSourceType>(
                value: _selectedType,
                items: _availableTypes
                    .map(
                      (e) => fluent.ComboBoxItem(
                        value: e,
                        child: Text(_getTypeName(e)),
                      ),
                    )
                    .toList(),
                onChanged: _isEditing
                    ? null
                    : (v) {
                        if (v != null)
                          setState(() {
                            _selectedType = v;
                            _statusMessage = null;
                            _needsApiKeyInput = false;
                            _pendingLxConfig = null;
                          });
                      },
              ),
            ),
            const SizedBox(height: 16),

            // Content based on type
            if (_selectedType == AudioSourceType.lxmusic) ...[
              Text(
                '输入洛雪音源脚本链接或从文件导入',
                style: fluent.FluentTheme.of(context).typography.caption,
              ),
              const SizedBox(height: 8),
              fluent.TextBox(
                controller: _lxScriptUrlController,
                placeholder: 'https://example.com/script.js',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _lxQuickScriptUrls.map((url) {
                  return fluent.Button(
                    onPressed: _isProcessing
                        ? null
                        : () => _applyLxQuickScriptUrl(url),
                    child: Text(_lxQuickPresetLabel(url)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  fluent.Button(
                    onPressed: _isProcessing ? null : _importLxScriptFromUrl,
                    child: const Text('链接导入'),
                  ),
                  const SizedBox(width: 8),
                  fluent.Button(
                    onPressed: _isProcessing ? null : _importLxScriptFromFile,
                    child: const Text('本地文件'),
                  ),
                ],
              ),
              if (_needsApiKeyInput) ...[
                const SizedBox(height: 12),
                fluent.InfoLabel(
                  label: '需要 API Key',
                  child: fluent.TextBox(
                    controller: _lxApiKeyController,
                    placeholder: '输入 API Key',
                  ),
                ),
                const SizedBox(height: 8),
                fluent.FilledButton(
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          await _confirmLxApiKey();
                        },
                  child: const Text('确认添加'),
                ),
              ],
            ] else if (_selectedType == AudioSourceType.omniparse) ...[
              // OmniParse 只允许通过导入配置文件进行配置
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    const Icon(fluent.FluentIcons.shield_alert, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      '为保护配置信息安全，OmniParse 音源\n只能通过导入配置文件进行配置',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    fluent.FilledButton(
                      onPressed: _importCyreneConfig,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(fluent.FluentIcons.open_file, size: 16),
                          SizedBox(width: 8),
                          Text('导入 .cyrene 配置文件'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // TuneHub 配置
              fluent.InfoLabel(
                label: '名称 (可选)',
                child: fluent.TextBox(
                  controller: _nameController,
                  placeholder: '给音源起个名字',
                ),
              ),
              const SizedBox(height: 8),
              fluent.InfoLabel(
                label: 'API 地址',
                child: fluent.TextBox(
                  controller: _urlController,
                  placeholder: 'http://...',
                ),
              ),
              // TuneHub v3 需要 API Key
              if (_selectedType == AudioSourceType.tunehub) ...[
                const SizedBox(height: 8),
                fluent.InfoLabel(
                  label: 'API Key',
                  child: fluent.TextBox(
                    controller: _tuneHubApiKeyController,
                    placeholder: 'th_your_api_key_here',
                    obscureText: true,
                  ),
                ),
              ],
            ],

            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              fluent.InfoBar(
                title: Text(_statusMessage!),
                severity: _isError
                    ? fluent.InfoBarSeverity.error
                    : fluent.InfoBarSeverity.success,
              ),
            ],
          ],
        ),
      ),
      actions: [
        fluent.Button(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_selectedType !=
            AudioSourceType
                .lxmusic) // LxMusic has its own confirm flow inside content (if key needed) or auto-adds
          fluent.FilledButton(
            onPressed: _isProcessing
                ? null
                : (_selectedType == AudioSourceType.tunehub
                      ? _saveTuneHubSource
                      : _saveOmniParseSource),
            child: _isProcessing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : Text(_isEditing ? '保存' : '添加'),
          ),
      ],
    );
  }

  Widget _buildCupertinoDialog(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final isDark = brightness == Brightness.dark;

    // 颜色定义
    final backgroundColor = isDark
        ? const Color(0xFF1C1C1E)
        : CupertinoColors.systemBackground.resolveFrom(context);
    final cardColor = isDark
        ? const Color(0xFF2C2C2E)
        : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context);
    final separatorColor = CupertinoColors.separator.resolveFrom(context);
    final labelColor = CupertinoColors.label.resolveFrom(context);
    final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(
      context,
    );

    // 构建分组标题
    Widget buildSectionHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, bottom: 8, top: 20),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: secondaryLabelColor,
            letterSpacing: -0.08,
          ),
        ),
      );
    }

    // 构建分组卡片
    Widget buildGroupedCard({required List<Widget> children}) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: children.asMap().entries.map((entry) {
            final index = entry.key;
            final child = entry.value;
            final isLast = index == children.length - 1;
            return Column(
              children: [
                child,
                if (!isLast)
                  Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Container(height: 0.5, color: separatorColor),
                  ),
              ],
            );
          }).toList(),
        ),
      );
    }

    // 构建列表项
    Widget buildListTile({
      required String title,
      String? subtitle,
      Widget? trailing,
      VoidCallback? onTap,
      bool showChevron = false,
    }) {
      return CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        color: labelColor,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: secondaryLabelColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (showChevron)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 构建输入框项
    Widget buildInputTile({
      required String placeholder,
      required TextEditingController controller,
      bool obscureText = false,
      TextInputType? keyboardType,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          obscureText: obscureText,
          keyboardType: keyboardType,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(),
          style: TextStyle(fontSize: 17, color: labelColor),
          placeholderStyle: TextStyle(
            fontSize: 17,
            color: CupertinoColors.placeholderText.resolveFrom(context),
          ),
        ),
      );
    }

    // 状态提示组件
    Widget buildStatusBanner() {
      if (_statusMessage == null) return const SizedBox.shrink();

      final isSuccess = !_isError;
      final bannerColor = isSuccess
          ? CupertinoColors.activeGreen.withValues(alpha: 0.15)
          : CupertinoColors.destructiveRed.withValues(alpha: 0.15);
      final iconColor = isSuccess
          ? CupertinoColors.activeGreen
          : CupertinoColors.destructiveRed;
      final textColor = isSuccess
          ? CupertinoColors.activeGreen
          : CupertinoColors.destructiveRed;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bannerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isSuccess
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.xmark_circle_fill,
              color: iconColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 获取键盘高度用于内容区域底部 padding
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          children: [
            // 拖拽手柄
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey3.resolveFrom(context),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),

            // 导航栏（带毛玻璃效果）
            ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: backgroundColor.withValues(alpha: 0.9),
                    border: Border(
                      bottom: BorderSide(color: separatorColor, width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        child: Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 17,
                            color: CupertinoColors.activeBlue.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        _isEditing ? '编辑音源' : '添加音源',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 17,
                          color: labelColor,
                        ),
                      ),
                      _isProcessing
                          ? const CupertinoActivityIndicator()
                          : CupertinoButton(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              onPressed:
                                  _selectedType == AudioSourceType.lxmusic
                                  ? null
                                  : (_selectedType == AudioSourceType.tunehub
                                        ? _saveTuneHubSource
                                        : _saveOmniParseSource),
                              child: Text(
                                _isEditing ? '保存' : '添加',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _selectedType == AudioSourceType.lxmusic
                                      ? CupertinoColors.tertiaryLabel
                                            .resolveFrom(context)
                                      : CupertinoColors.activeBlue.resolveFrom(
                                          context,
                                        ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            ),

            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.only(bottom: keyboardHeight),
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 音源类型选择
                      buildSectionHeader('音源类型'),
                      buildGroupedCard(
                        children: [
                          buildListTile(
                            title: _getTypeName(_selectedType),
                            trailing: _isEditing
                                ? null
                                : Text(
                                    '更改',
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: CupertinoColors.activeBlue
                                          .resolveFrom(context),
                                    ),
                                  ),
                            onTap: _isEditing
                                ? null
                                : () {
                                    showCupertinoModalPopup<void>(
                                      context: context,
                                      builder: (BuildContext ctx) => Container(
                                        height: 280,
                                        decoration: BoxDecoration(
                                          color: backgroundColor,
                                          borderRadius:
                                              const BorderRadius.vertical(
                                                top: Radius.circular(12),
                                              ),
                                        ),
                                        child: Column(
                                          children: [
                                            // Picker 导航栏
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: separatorColor,
                                                    width: 0.5,
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    child: const Text('取消'),
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                  ),
                                                  Text(
                                                    '选择音源类型',
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 17,
                                                      color: labelColor,
                                                    ),
                                                  ),
                                                  CupertinoButton(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size.zero,
                                                    child: const Text(
                                                      '完成',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    onPressed: () =>
                                                        Navigator.pop(ctx),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Picker
                                            Expanded(
                                              child: CupertinoPicker(
                                                magnification: 1.22,
                                                squeeze: 1.2,
                                                useMagnifier: true,
                                                itemExtent: 40,
                                                scrollController:
                                                    FixedExtentScrollController(
                                                      initialItem:
                                                          _availableTypes.indexOf(
                                                                _selectedType,
                                                              ) <
                                                              0
                                                          ? 0
                                                          : _availableTypes
                                                                .indexOf(
                                                                  _selectedType,
                                                                ),
                                                    ),
                                                onSelectedItemChanged:
                                                    (int selectedItem) {
                                                      setState(() {
                                                        _selectedType =
                                                            _availableTypes[selectedItem];
                                                        _statusMessage = null;
                                                        _needsApiKeyInput =
                                                            false;
                                                        _pendingLxConfig = null;
                                                      });
                                                    },
                                                children: _availableTypes
                                                    .map(
                                                      (type) => Center(
                                                        child: Text(
                                                          _getTypeName(type),
                                                          style: TextStyle(
                                                            fontSize: 20,
                                                            color: labelColor,
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),

                      // 状态提示
                      buildStatusBanner(),

                      // 根据音源类型显示不同配置
                      if (_selectedType == AudioSourceType.lxmusic) ...[
                        buildSectionHeader('脚本配置'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: '输入脚本链接 (https://...)',
                              controller: _lxScriptUrlController,
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _lxQuickScriptUrls.map((url) {
                              return CupertinoButton(
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                                minimumSize: Size.square(24),
                                onPressed: _isProcessing
                                    ? null
                                    : () => _applyLxQuickScriptUrl(url),
                                child: Text(
                                  _lxQuickPresetLabel(url),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: CupertinoColors.activeBlue
                                        .resolveFrom(context),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // 导入按钮
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 20,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  color: CupertinoColors.activeBlue.resolveFrom(
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: _isProcessing
                                      ? null
                                      : _importLxScriptFromUrl,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.link,
                                        size: 18,
                                        color: CupertinoColors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        '链接导入',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: CupertinoColors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  onPressed: _isProcessing
                                      ? null
                                      : _importLxScriptFromFile,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        CupertinoIcons.folder,
                                        size: 18,
                                        color: labelColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '本地文件',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: labelColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // API Key 输入（如果需要）
                        if (_needsApiKeyInput) ...[
                          buildSectionHeader('认证'),
                          buildGroupedCard(
                            children: [
                              buildInputTile(
                                placeholder: '输入 API Key',
                                controller: _lxApiKeyController,
                                obscureText: true,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 20,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: CupertinoButton(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                color: CupertinoColors.activeBlue.resolveFrom(
                                  context,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                onPressed: _isProcessing
                                    ? null
                                    : () async {
                                        await _confirmLxApiKey();
                                      },
                                child: const Text(
                                  '确认添加',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ] else if (_selectedType ==
                          AudioSourceType.omniparse) ...[
                        // OmniParse 只允许通过导入配置文件进行配置
                        const SizedBox(height: 48),
                        Center(
                          child: Column(
                            children: [
                              Icon(
                                CupertinoIcons.lock_shield,
                                size: 48,
                                color: CupertinoColors.systemGrey,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '为保护配置信息安全，OmniParse 音源\n只能通过导入配置文件进行配置',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: secondaryLabelColor,
                                ),
                              ),
                              const SizedBox(height: 24),
                              CupertinoButton.filled(
                                onPressed: _importCyreneConfig,
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CupertinoIcons.folder_open, size: 18),
                                    SizedBox(width: 8),
                                    Text('导入 .cyrene 配置文件'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // TuneHub 配置
                        buildSectionHeader('基本信息'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: '音源名称（可选）',
                              controller: _nameController,
                            ),
                          ],
                        ),

                        buildSectionHeader('服务器配置'),
                        buildGroupedCard(
                          children: [
                            buildInputTile(
                              placeholder: 'API 地址 (http://...)',
                              controller: _urlController,
                              keyboardType: TextInputType.url,
                            ),
                          ],
                        ),

                        if (_selectedType == AudioSourceType.tunehub) ...[
                          buildSectionHeader('认证'),
                          buildGroupedCard(
                            children: [
                              buildInputTile(
                                placeholder: 'API Key',
                                controller: _tuneHubApiKeyController,
                                obscureText: true,
                              ),
                            ],
                          ),
                        ],

                        // 添加说明
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 8,
                          ),
                          child: Text(
                            '请输入 TuneHub 服务器的 API 地址',
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryLabelColor,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Text(_isEditing ? '编辑音源' : '添加音源'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type Selector
              DropdownButtonFormField<AudioSourceType>(
                initialValue: _selectedType,
                decoration: InputDecoration(
                  labelText: '音源类型',
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: _availableTypes
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(_getTypeName(e)),
                      ),
                    )
                    .toList(),
                onChanged: _isEditing
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() {
                            _selectedType = v;
                            _statusMessage = null;
                            _needsApiKeyInput = false;
                            _pendingLxConfig = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 20),

              // Content based on type
              if (_selectedType == AudioSourceType.lxmusic) ...[
                Text(
                  '输入洛雪音源脚本链接或从文件导入',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lxScriptUrlController,
                  decoration: InputDecoration(
                    labelText: '脚本链接',
                    hintText: 'https://example.com/script.js',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _lxQuickScriptUrls.map((url) {
                    return ActionChip(
                      label: Text(_lxQuickPresetLabel(url)),
                      onPressed: _isProcessing
                          ? null
                          : () => _applyLxQuickScriptUrl(url),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        icon: const Icon(Icons.link),
                        onPressed: _isProcessing
                            ? null
                            : _importLxScriptFromUrl,
                        label: const Text('链接导入'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open_outlined),
                        onPressed: _isProcessing
                            ? null
                            : _importLxScriptFromFile,
                        label: const Text('本地文件'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_needsApiKeyInput) ...[
                  const SizedBox(height: 20),
                  TextField(
                    controller: _lxApiKeyController,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入 API Key',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              await _confirmLxApiKey();
                            },
                      child: const Text('确认添加'),
                    ),
                  ),
                ],
              ] else if (_selectedType == AudioSourceType.omniparse) ...[
                // OmniParse 只允许通过导入配置文件进行配置
                const SizedBox(height: 32),
                Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.security,
                        size: 56,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '为保护配置信息安全，OmniParse 音源\n只能通过导入配置文件进行配置',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _importCyreneConfig,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('导入 .cyrene 配置文件'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // TuneHub 配置
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '名称 (可选)',
                    hintText: '给音源起个名字',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    labelText: 'API 地址',
                    hintText: 'http://...',
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (_selectedType == AudioSourceType.tunehub) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _tuneHubApiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'th_your_api_key_here',
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ],

              if (_statusMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? colorScheme.errorContainer
                        : colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: _isError
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _isError
                                ? colorScheme.onErrorContainer
                                : colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_selectedType != AudioSourceType.lxmusic)
          FilledButton(
            onPressed: _isProcessing
                ? null
                : (_selectedType == AudioSourceType.tunehub
                      ? _saveTuneHubSource
                      : _saveOmniParseSource),
            child: _isProcessing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? '保存' : '添加'),
          ),
      ],
    );
  }

  String _getTypeName(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse:
        return 'OmniParse / 自定义';
      case AudioSourceType.lxmusic:
        return '洛雪音乐脚本';
      case AudioSourceType.tunehub:
        return 'TuneHub';
      case AudioSourceType.navidrome:
        return 'Navidrome';
    }
  }
}
