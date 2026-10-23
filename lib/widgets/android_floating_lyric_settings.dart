import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/android_floating_lyric_service.dart';
import '../utils/theme_manager.dart';
import 'cupertino/cupertino_settings_widgets.dart';
import '../widgets/material/material_settings_widgets.dart';

/// Android 悬浮歌词设置组件
class AndroidFloatingLyricSettings extends StatefulWidget {
  const AndroidFloatingLyricSettings({super.key});

  @override
  State<AndroidFloatingLyricSettings> createState() => _AndroidFloatingLyricSettingsState();
}

class _AndroidFloatingLyricSettingsState extends State<AndroidFloatingLyricSettings> {
  final AndroidFloatingLyricService _lyricService = AndroidFloatingLyricService();
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  /// 检查权限状态
  Future<void> _checkPermission() async {
    final hasPermission = await _lyricService.checkPermission();
    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    if (ThemeManager().isCupertinoFramework) {
      return _buildCupertinoSettings(context);
    }

    return Column(
      children: [
        // 权限状态卡片
        MD3SettingsSection(
          title: '权限管理',
          children: [
            MD3SettingsTile(
              title: '悬浮窗权限',
              subtitle: _hasPermission ? '✅ 已获得授权' : '❌ 未获得授权',
              leading: Icon(
                _hasPermission ? Icons.verified_user : Icons.gpp_maybe,
                color: _hasPermission ? Colors.green : Colors.orange,
              ),
              trailing: _hasPermission
                  ? null
                  : TextButton(
                      onPressed: () async {
                        final granted = await _lyricService.requestPermissionWithDialog(context);
                        if (granted) {
                          await _checkPermission();
                          if (mounted && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ 权限已授予'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      },
                      child: const Text('去授权'),
                    ),
            ),
          ],
        ),

        // 常规设置卡片
        MD3SettingsSection(
          title: '基础设置',
          children: [
            MD3SwitchTile(
              title: '启用悬浮歌词',
              subtitle: _lyricService.isVisible
                  ? '悬浮歌词窗口已显示'
                  : '悬浮歌词窗口已隐藏',
              leading: const Icon(Icons.subtitles),
              value: _lyricService.isVisible,
              onChanged: (value) async {
                if (value) {
                  final granted = await _lyricService.requestPermissionWithDialog(context);
                  if (granted) {
                    await _lyricService.show();
                    await _checkPermission();
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('✅ 悬浮歌词已启用'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  } else {
                    if (mounted && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('❌ 需要悬浮窗权限才能启用悬浮歌词'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                } else {
                  await _lyricService.hide();
                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('悬浮歌词已关闭'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
                setState(() {});
              },
            ),
          ],
        ),

        // 外观设置卡片
        MD3SettingsSection(
          title: '外观展示',
          children: [
            MD3SettingsTile(
              title: '字体大小',
              subtitle: '当前: ${_lyricService.config['fontSize']}px',
              leading: const Icon(Icons.format_size),
              onTap: () => _showFontSizeDialog(),
            ),
            MD3SettingsTile(
              title: '文字颜色',
              subtitle: '点击选择颜色',
              leading: const Icon(Icons.color_lens),
              onTap: () => _showTextColorPicker(),
              trailing: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(_lyricService.config['textColor']),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
            MD3SettingsTile(
              title: '描边颜色',
              subtitle: '增加文字可读性',
              leading: const Icon(Icons.border_color),
              onTap: () => _showStrokeColorPicker(),
              trailing: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Color(_lyricService.config['strokeColor']),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
              ),
            ),
            MD3SettingsTile(
              title: '描边宽度',
              subtitle: '当前: ${_lyricService.config['strokeWidth']}px',
              leading: const Icon(Icons.line_weight),
              onTap: () => _showStrokeWidthDialog(),
            ),
            MD3SettingsTile(
              title: '透明度',
              subtitle: '当前: ${(_lyricService.config['alpha'] * 100).toInt()}%',
              leading: const Icon(Icons.opacity),
              onTap: () => _showAlphaDialog(),
            ),
          ],
        ),

        // 交互设置卡片
        MD3SettingsSection(
          title: '交互行为',
          children: [
            MD3SwitchTile(
              title: '允许拖动',
              subtitle: _lyricService.config['isDraggable']
                  ? '可以自由拖动悬浮窗'
                  : '悬浮窗位置已固定',
              leading: const Icon(Icons.pan_tool),
              value: _lyricService.config['isDraggable'],
              onChanged: (value) async {
                await _lyricService.setDraggable(value);
                setState(() {});
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 构建 Cupertino 风格设置
  Widget _buildCupertinoSettings(BuildContext context) {
    return CupertinoSettingsSection(
      children: [
        // 权限状态
        CupertinoSettingsTile(
          title: '权限状态',
          subtitle: _hasPermission ? '已获得悬浮窗权限' : '需要悬浮窗权限',
          icon: _hasPermission ? CupertinoIcons.check_mark_circled : CupertinoIcons.exclamationmark_circle,
          iconColor: _hasPermission ? CupertinoColors.activeGreen : CupertinoColors.systemOrange,
          trailing: _hasPermission ? null : CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Text('授权'),
            onPressed: () async {
              final granted = await _lyricService.requestPermissionWithDialog(context);
              if (granted) {
                await _checkPermission();
              }
            },
          ),
        ),

        // 启用悬浮歌词
        CupertinoSettingsTile(
          title: '启用悬浮歌词',
          subtitle: _lyricService.isVisible ? '已显示' : '已隐藏',
          icon: CupertinoIcons.captions_bubble,
          iconColor: CupertinoColors.systemBlue,
          trailing: CupertinoSwitch(
            value: _lyricService.isVisible,
            onChanged: (value) async {
              if (value) {
                final granted = await _lyricService.requestPermissionWithDialog(context);
                if (granted) {
                  await _lyricService.show();
                  await _checkPermission();
                }
              } else {
                await _lyricService.hide();
              }
              setState(() {});
            },
          ),
        ),

        // 字体大小
        CupertinoSettingsTile(
          title: '字体大小',
          subtitle: '${_lyricService.config['fontSize']}px',
          icon: CupertinoIcons.textformat_size,
          iconColor: CupertinoColors.systemGrey,
          showChevron: true,
          onTap: () => _showCupertinoValuePicker(
            title: '字体大小',
            value: _lyricService.config['fontSize'].toDouble(),
            min: 12.0,
            max: 48.0,
            divisions: 36,
            labelFormat: (v) => '${v.round()}px',
            onChanged: (v) async {
              await _lyricService.setFontSize(v.round());
              setState(() {});
            },
          ),
        ),

        // 文字颜色
        CupertinoSettingsTile(
          title: '文字颜色',
          icon: CupertinoIcons.paintbrush,
          iconColor: CupertinoColors.systemIndigo,
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(_lyricService.config['textColor']),
              shape: BoxShape.circle,
              border: Border.all(color: CupertinoColors.systemGrey4),
            ),
          ),
          onTap: () => showCupertinoColorPicker(
            context: context,
            colors: ThemeColors.presets.map((e) => e.color).toList(),
            currentColor: Color(_lyricService.config['textColor']),
            onColorSelected: (color) async {
              await _lyricService.setTextColor(color.toARGB32());
              setState(() {});
            },
          ),
        ),

        // 描边颜色
        CupertinoSettingsTile(
          title: '描边颜色',
          icon: CupertinoIcons.pencil_outline,
          iconColor: CupertinoColors.systemOrange,
          trailing: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Color(_lyricService.config['strokeColor']),
              shape: BoxShape.circle,
              border: Border.all(color: CupertinoColors.systemGrey4),
            ),
          ),
          onTap: () => showCupertinoColorPicker(
            context: context,
            colors: ThemeColors.presets.map((e) => e.color).toList(),
            currentColor: Color(_lyricService.config['strokeColor']),
            onColorSelected: (color) async {
              await _lyricService.setStrokeColor(color.toARGB32());
              setState(() {});
            },
          ),
        ),

        // 描边宽度
        CupertinoSettingsTile(
          title: '描边宽度',
          subtitle: '${_lyricService.config['strokeWidth']}px',
          icon: CupertinoIcons.scribble,
          iconColor: CupertinoColors.systemPink,
          showChevron: true,
          onTap: () => _showCupertinoValuePicker(
            title: '描边宽度',
            value: _lyricService.config['strokeWidth'].toDouble(),
            min: 0.0,
            max: 8.0,
            divisions: 8,
            labelFormat: (v) => '${v.round()}px',
            onChanged: (v) async {
              await _lyricService.setStrokeWidth(v.round());
              setState(() {});
            },
          ),
        ),

        // 透明度
        CupertinoSettingsTile(
          title: '透明度',
          subtitle: '${(_lyricService.config['alpha'] * 100).toInt()}%',
          icon: CupertinoIcons.circle_grid_hex,
          iconColor: CupertinoColors.systemTeal,
          showChevron: true,
          onTap: () => _showCupertinoValuePicker(
            title: '透明度',
            value: _lyricService.config['alpha'],
            min: 0.1,
            max: 1.0,
            divisions: 9,
            labelFormat: (v) => '${(v * 100).toInt()}%',
            onChanged: (v) async {
              await _lyricService.setAlpha(v);
              setState(() {});
            },
          ),
        ),

        // 允许拖动
        CupertinoSettingsTile(
          title: '允许拖动',
          subtitle: _lyricService.config['isDraggable'] ? '可拖动' : '已锁定',
          icon: CupertinoIcons.move,
          iconColor: CupertinoColors.systemPurple,
          trailing: CupertinoSwitch(
            value: _lyricService.config['isDraggable'],
            onChanged: (value) async {
              await _lyricService.setDraggable(value);
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  /// 显示 Cupertino 风格数值选择器
  Future<void> _showCupertinoValuePicker({
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String Function(double) labelFormat,
    required ValueChanged<double> onChanged,
  }) async {
    double tempValue = value;

    await showCupertinoModalPopup(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textColor = isDark ? CupertinoColors.white : CupertinoColors.black;

        return Container(
          height: 300,
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CupertinoButton(
                      child: const Text('取消'),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    CupertinoButton(
                      child: const Text('完成'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StatefulBuilder(
                      builder: (context, setState) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            labelFormat(tempValue),
                            style: TextStyle(
                              fontSize: 24,
                              color: textColor,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: CupertinoSlider(
                              value: tempValue,
                              min: min,
                              max: max,
                              divisions: divisions,
                              onChanged: (v) {
                                setState(() {
                                  tempValue = v;
                                });
                                onChanged(v);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示字体大小对话框
  void _showFontSizeDialog() {
    int currentSize = _lyricService.config['fontSize'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('字体大小'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前大小: ${currentSize}px'),
              const SizedBox(height: 16),
              Slider(
                value: currentSize.toDouble(),
                min: 12.0,
                max: 48.0,
                divisions: 36,
                label: '${currentSize}px',
                onChanged: (value) {
                  setState(() {
                    currentSize = value.round();
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await _lyricService.setFontSize(currentSize);
                if (!context.mounted) return;
                Navigator.pop(context);
                this.setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示文字颜色选择器
  void _showTextColorPicker() {
    Color currentColor = Color(_lyricService.config['textColor']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择文字颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              currentColor = color;
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _lyricService.setTextColor(currentColor.toARGB32());
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示描边颜色选择器
  void _showStrokeColorPicker() {
    Color currentColor = Color(_lyricService.config['strokeColor']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择描边颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: currentColor,
            onColorChanged: (color) {
              currentColor = color;
            },
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await _lyricService.setStrokeColor(currentColor.toARGB32());
              if (!context.mounted) return;
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 显示描边宽度对话框
  void _showStrokeWidthDialog() {
    int currentWidth = _lyricService.config['strokeWidth'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('描边宽度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前宽度: ${currentWidth}px'),
              const SizedBox(height: 16),
              Slider(
                value: currentWidth.toDouble(),
                min: 0.0,
                max: 8.0,
                divisions: 8,
                label: '${currentWidth}px',
                onChanged: (value) {
                  setState(() {
                    currentWidth = value.round();
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await _lyricService.setStrokeWidth(currentWidth);
                if (!context.mounted) return;
                Navigator.pop(context);
                this.setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示透明度对话框
  void _showAlphaDialog() {
    double currentAlpha = _lyricService.config['alpha'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('透明度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('当前透明度: ${(currentAlpha * 100).toInt()}%'),
              const SizedBox(height: 16),
              Slider(
                value: currentAlpha,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '${(currentAlpha * 100).toInt()}%',
                onChanged: (value) {
                  setState(() {
                    currentAlpha = value;
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                await _lyricService.setAlpha(currentAlpha);
                if (!context.mounted) return;
                Navigator.pop(context);
                this.setState(() {});
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}
