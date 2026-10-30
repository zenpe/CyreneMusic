import '../../widgets/server_address_editor.dart';
import '../../utils/app_feedback.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../features/audio_source/audio_source_feature.dart';
import '../../services/url_service.dart';
import '../../services/api/api_client.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 网络设置组件
class NetworkSettings extends StatefulWidget {
  /// 点击音源设置时的回调，用于在设置页面中打开子页面
  final VoidCallback? onAudioSourceTap;
  final bool serverOnly;

  const NetworkSettings({
    super.key,
    this.onAudioSourceTap,
    this.serverOnly = false,
  });

  @override
  State<NetworkSettings> createState() => _NetworkSettingsState();
}

class _NetworkSettingsState extends State<NetworkSettings> {
  late final AudioSourceReadController _audioSourceReadController =
      AudioSourceReadController();
  bool _isTesting = false;
  int _connectionTestId = 0;
  int? _latencyMs;
  String? _errorMessage;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    UrlService().addListener(_handleUrlChanged);
    if (!widget.serverOnly) {
      _audioSourceReadController.addListener(_handleAudioSourceChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _testConnection();
      _startAutoRefresh();
    });
  }

  @override
  void dispose() {
    UrlService().removeListener(_handleUrlChanged);
    if (!widget.serverOnly) {
      _audioSourceReadController.removeListener(_handleAudioSourceChanged);
    }
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _handleUrlChanged() {
    if (!mounted) return;
    _connectionTestId++;
    _isTesting = false;
    _latencyMs = null;
    _errorMessage = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _testConnection();
      _startAutoRefresh();
    });
  }

  void _handleAudioSourceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _testConnection();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;

    if (isFluent) {
      return FluentSettingsGroup(
        title: widget.serverOnly ? '服务器' : '网络',
        children: [
          FluentSettingsTile(
            icon: Icons.dns,
            title: '服务器设置',
            subtitle: UrlService().getSourceDescription(),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBackendSourceDialogFluent(context),
          ),
          if (!widget.serverOnly)
            FluentSettingsTile(
              icon: Icons.music_note,
              title: '音源设置',
              subtitle: _audioSourceReadController.sourceSummary,
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.onAudioSourceTap,
            ),
          FluentSettingsTile(
            icon: Icons.wifi_tethering,
            title: '测试连接',
            subtitle: _errorMessage != null ? '无法连接服务器' : '自动检测与服务器的连接',
            trailing: _buildLatencyIndicator(context),
          ),
        ],
      );
    }

    if (isCupertino) {
      return _buildCupertinoUI(context);
    }

    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.dns_outlined),
          title: '服务器设置',
          subtitle: UrlService().getSourceDescription(),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showBackendSourceDialog(context),
        ),
        if (!widget.serverOnly)
          MD3SettingsTile(
            leading: const Icon(Icons.music_note_outlined),
            title: '音源设置',
            subtitle: _audioSourceReadController.sourceSummary,
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAudioSourceTap,
          ),
        MD3SettingsTile(
          leading: const Icon(Icons.wifi_tethering_outlined),
          title: '测试连接',
          subtitle: _errorMessage != null ? '无法连接服务器' : '自动检测与服务器的连接',
          trailing: _buildLatencyIndicator(context),
        ),
      ],
    );
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context) {
    return Column(
      children: [
        CupertinoSettingsTile(
          icon: CupertinoIcons.globe,
          iconColor: CupertinoColors.systemBlue,
          title: '服务器设置',
          subtitle: UrlService().getSourceDescription(),
          showChevron: true,
          onTap: () => _showBackendSourceDialogCupertino(context),
        ),
        const SizedBox(height: 1),
        if (!widget.serverOnly)
          CupertinoSettingsTile(
            icon: CupertinoIcons.music_note,
            iconColor: CupertinoColors.systemPurple,
            title: '音源设置',
            subtitle: _audioSourceReadController.sourceSummary,
            showChevron: true,
            onTap: widget.onAudioSourceTap,
          ),
        const SizedBox(height: 1),
        CupertinoSettingsTile(
          icon: CupertinoIcons.wifi,
          iconColor: CupertinoColors.systemGreen,
          title: '测试连接',
          subtitle: _errorMessage != null ? '无法连接服务器' : '自动检测与服务器的连接',
          trailing: _buildLatencyIndicatorCupertino(context),
        ),
      ],
    );
  }

  /// 构建 Cupertino 风格的延迟指示器
  Widget _buildLatencyIndicatorCupertino(BuildContext context) {
    if (_isTesting) {
      return const CupertinoActivityIndicator();
    }

    if (_latencyMs != null) {
      final latency = _latencyMs!.clamp(0, 9999);
      Color displayColor;
      if (latency <= 100) {
        displayColor = CupertinoColors.systemGreen;
      } else if (latency <= 300) {
        displayColor = CupertinoColors.systemOrange;
      } else {
        displayColor = CupertinoColors.systemRed;
      }

      return Text(
        '$latency ms',
        style: TextStyle(fontWeight: FontWeight.bold, color: displayColor),
      );
    }

    if (_errorMessage != null) {
      return Text(
        '失联',
        style: TextStyle(
          color: CupertinoColors.systemRed,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      '--',
      style: TextStyle(
        color: CupertinoColors.systemGrey,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  void _showCustomUrlDialogFluent(BuildContext context) {
    fluent_ui.showDialog<void>(
      context: context,
      builder: (_) =>
          const ServerAddressEditor(style: ServerEditorStyle.fluent),
    );
  }

  void _showBackendSourceDialogFluent(BuildContext context) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) {
        return fluent_ui.ContentDialog(
          title: const Text('服务器设置'),
          content: fluent_ui.RadioGroup<BackendSourceType>(
            groupValue: UrlService().sourceType,
            onChanged: (value) {
              if (value == null) return;
              if (value == BackendSourceType.official) {
                UrlService().useOfficialSource();
                Navigator.pop(context);
                final messenger = AppFeedback.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已切换到官方服务器')),
                  );
                }
                return;
              }
              Navigator.pop(context);
              _showCustomUrlDialogFluent(context);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const fluent_ui.RadioButton<BackendSourceType>(
                  value: BackendSourceType.official,
                  content: Text('官方服务器'),
                ),
                const SizedBox(height: 8),
                fluent_ui.RadioButton<BackendSourceType>(
                  value: BackendSourceType.custom,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('自定义服务器'),
                      Text(
                        UrlService().customBaseUrl.isNotEmpty
                            ? UrlService().customBaseUrl
                            : '点击设置自定义地址',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showBackendSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('服务器设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<BackendSourceType>(
              groupValue: UrlService().sourceType,
              onChanged: (value) {
                UrlService().useOfficialSource();
                Navigator.pop(context);
                AppFeedback.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已切换到官方服务器')));
              },
              child: RadioListTile<BackendSourceType>(
                title: const Text('官方服务器'),
                subtitle: Text(
                  UrlService.officialBaseUrl,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: BackendSourceType.official,
              ),
            ),
            RadioGroup<BackendSourceType>(
              groupValue: UrlService().sourceType,
              onChanged: (value) {
                Navigator.pop(context);
                _showCustomUrlDialog(context);
              },
              child: RadioListTile<BackendSourceType>(
                title: const Text('自定义服务器'),
                subtitle: Text(
                  UrlService().customBaseUrl.isNotEmpty
                      ? UrlService().customBaseUrl
                      : '点击设置自定义地址',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                value: BackendSourceType.custom,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _showCustomUrlDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          const ServerAddressEditor(style: ServerEditorStyle.material),
    );
  }

  /// 显示 Cupertino 风格的后端源选择对话框
  void _showBackendSourceDialogCupertino(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('服务器设置'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              UrlService().useOfficialSource();
              Navigator.pop(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (UrlService().sourceType == BackendSourceType.official)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
                const Text('官方服务器'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showCustomUrlDialogCupertino(context);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (UrlService().sourceType == BackendSourceType.custom)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(CupertinoIcons.checkmark, size: 18),
                  ),
                const Text('自定义服务器'),
                if (UrlService().customBaseUrl.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    UrlService().customBaseUrl,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }

  /// 显示 Cupertino 风格的自定义 URL 对话框
  void _showCustomUrlDialogCupertino(BuildContext context) {
    showCupertinoDialog<void>(
      context: context,
      builder: (_) =>
          const ServerAddressEditor(style: ServerEditorStyle.cupertino),
    );
  }

  Widget _buildLatencyIndicator(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isTesting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_latencyMs != null) {
      final latency = _latencyMs!.clamp(0, 9999);
      Color displayColor;
      if (latency <= 100) {
        displayColor = Colors.green;
      } else if (latency <= 300) {
        displayColor = Colors.orange;
      } else {
        displayColor = colorScheme.error;
      }

      return Text(
        '$latency ms',
        style: TextStyle(fontWeight: FontWeight.bold, color: displayColor),
      );
    }

    if (_errorMessage != null) {
      return Tooltip(
        message: _errorMessage!,
        child: Text(
          '失联',
          style: TextStyle(
            color: colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return Text(
      '--',
      style: TextStyle(color: colorScheme.outline, fontWeight: FontWeight.bold),
    );
  }

  Future<void> _testConnection() async {
    if (_isTesting || !mounted) return;

    final baseUrl = UrlService().baseUrl;
    if (baseUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _latencyMs = null;
        _errorMessage = '未设置服务器地址';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isTesting = true;
      _errorMessage = null;
    });

    final testId = ++_connectionTestId;
    final stopwatch = Stopwatch()..start();
    try {
      final result = await ApiClient().getJson(
        '/info',
        auth: false,
        timeout: const Duration(seconds: 10),
      );

      stopwatch.stop();
      if (!mounted || testId != _connectionTestId) return;

      if (result.ok) {
        setState(() {
          _latencyMs = stopwatch.elapsedMilliseconds == 0
              ? 1
              : stopwatch.elapsedMilliseconds;
          _isTesting = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isTesting = false;
          _latencyMs = null;
          _errorMessage = 'HTTP ${result.statusCode}';
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (!mounted || testId != _connectionTestId) return;
      setState(() {
        _isTesting = false;
        _latencyMs = null;
        _errorMessage = e.toString();
      });
    }
  }
}
