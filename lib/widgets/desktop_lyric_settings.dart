import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../services/desktop_lyric_service.dart';
import 'fluent_settings_card.dart';

/// 桌面歌词设置组件
class DesktopLyricSettings extends StatefulWidget {
  const DesktopLyricSettings({super.key});

  @override
  State<DesktopLyricSettings> createState() => _DesktopLyricSettingsState();
}

class _DesktopLyricSettingsState extends State<DesktopLyricSettings> {
  final _desktopLyricService = DesktopLyricService();
  
  late int _fontSize;
  late Color _textColor;
  late Color _strokeColor;
  late int _strokeWidth;
  late bool _isDraggable;
  late bool _isMouseTransparent;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  void _loadConfig() {
    final config = _desktopLyricService.config;
    setState(() {
      _fontSize = config['fontSize'] as int;
      _textColor = Color(config['textColor'] as int);
      _strokeColor = Color(config['strokeColor'] as int);
      _strokeWidth = config['strokeWidth'] as int;
      _isDraggable = config['isDraggable'] as bool;
      _isMouseTransparent = config['isMouseTransparent'] as bool;
    });
  }

  Future<void> _pickColor(String type) async {
    Color initialColor = type == 'text' ? _textColor : _strokeColor;

    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;

    if (isFluent) {
      await fluent_ui.showDialog(
        context: context,
        builder: (context) => fluent_ui.ContentDialog(
          title: Text(type == 'text' ? '选择文字颜色' : '选择描边颜色'),
          content: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: 300,
              child: HueRingPicker(
                pickerColor: initialColor,
                onColorChanged: (color) {
                  setState(() {
                    if (type == 'text') {
                      _textColor = color;
                      _desktopLyricService.setTextColor(color.value);
                    } else {
                      _strokeColor = color;
                      _desktopLyricService.setStrokeColor(color.value);
                    }
                  });
                },
                enableAlpha: true,
                displayThumbColor: true,
              ),
            ),
          ),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == 'text' ? '选择文字颜色' : '选择描边颜色'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: initialColor,
            onColorChanged: (color) {
              setState(() {
                if (type == 'text') {
                  _textColor = color;
                  _desktopLyricService.setTextColor(color.value);
                } else {
                  _strokeColor = color;
                  _desktopLyricService.setStrokeColor(color.value);
                }
              });
            },
            enableAlpha: true,
            displayThumbColor: true,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('桌面歌词功能仅支持Windows平台'),
        ),
      );
    }

    final theme = Theme.of(context);
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;

    if (isFluent) {
      final fluentTheme = fluent_ui.FluentTheme.of(context);
      
      return FluentSettingsGroup(
        title: '桌面歌词',
        children: [
          // 显示开关
          FluentSwitchTile(
            icon: fluent_ui.FluentIcons.text_paragraph_option,
            title: '显示桌面歌词',
            subtitle: '在桌面覆盖层显示当前歌词',
            value: _desktopLyricService.isVisible,
            onChanged: (value) async {
              await _desktopLyricService.toggle();
              setState(() {});
            },
          ),
          // 字体大小
          FluentSliderTile(
            icon: fluent_ui.FluentIcons.font_size,
            title: '字体大小',
            value: _fontSize.toDouble(),
            min: 16,
            max: 72,
            divisions: 28,
            valueLabel: '$_fontSize',
            onChanged: (value) {
              setState(() {
                _fontSize = value.toInt();
              });
              _desktopLyricService.setFontSize(_fontSize);
            },
          ),
          // 文字颜色
          FluentSettingsTile(
            icon: fluent_ui.FluentIcons.font_color_a,
            title: '文字颜色',
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _textColor,
                border: Border.all(color: fluentTheme.resources.dividerStrokeColorDefault),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onTap: () => _pickColor('text'),
          ),
          // 描边颜色
          FluentSettingsTile(
            icon: fluent_ui.FluentIcons.border_dash,
            title: '描边颜色',
            trailing: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _strokeColor,
                border: Border.all(color: fluentTheme.resources.dividerStrokeColorDefault),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onTap: () => _pickColor('stroke'),
          ),
          // 描边宽度
          FluentSliderTile(
            icon: fluent_ui.FluentIcons.line_thickness,
            title: '描边宽度',
            value: _strokeWidth.toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            valueLabel: '$_strokeWidth',
            onChanged: (value) {
              setState(() {
                _strokeWidth = value.toInt();
              });
              _desktopLyricService.setStrokeWidth(_strokeWidth);
            },
          ),
          // 可拖动
          FluentSwitchTile(
            icon: fluent_ui.FluentIcons.move,
            title: '允许拖动',
            subtitle: '鼠标可以拖动歌词窗口',
            value: _isDraggable,
            onChanged: (value) {
              setState(() {
                _isDraggable = value;
              });
              _desktopLyricService.setDraggable(value);
            },
          ),
          // 鼠标穿透
          FluentSwitchTile(
            icon: fluent_ui.FluentIcons.touch_pointer,
            title: '鼠标穿透',
            subtitle: '歌词窗口不响应鼠标事件',
            value: _isMouseTransparent,
            onChanged: (value) {
              setState(() {
                _isMouseTransparent = value;
              });
              _desktopLyricService.setMouseTransparent(value);
            },
          ),
          // 测试按钮
          FluentSettingsTile(
            icon: fluent_ui.FluentIcons.play,
            title: '测试歌词显示',
            subtitle: '显示一条测试歌词',
            trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
            onTap: () {
              _desktopLyricService.setLyricText('这是测试歌词 - This is a test lyric');
            },
          ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lyrics, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '桌面歌词',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                Switch(
                  value: _desktopLyricService.isVisible,
                  onChanged: (value) async {
                    await _desktopLyricService.toggle();
                    setState(() {});
                  },
                ),
              ],
            ),
            const Divider(),
            
            // 字体大小
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('字体大小'),
              subtitle: Slider(
                value: _fontSize.toDouble(),
                min: 16,
                max: 72,
                divisions: 28,
                label: _fontSize.toString(),
                onChanged: (value) {
                  setState(() {
                    _fontSize = value.toInt();
                  });
                  _desktopLyricService.setFontSize(_fontSize);
                },
              ),
              trailing: Text('$_fontSize'),
            ),

            // 文字颜色
            ListTile(
              leading: const Icon(Icons.color_lens),
              title: const Text('文字颜色'),
              trailing: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _textColor,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onTap: () => _pickColor('text'),
            ),

            // 描边颜色
            ListTile(
              leading: const Icon(Icons.border_color),
              title: const Text('描边颜色'),
              trailing: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _strokeColor,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onTap: () => _pickColor('stroke'),
            ),

            // 描边宽度
            ListTile(
              leading: const Icon(Icons.line_weight),
              title: const Text('描边宽度'),
              subtitle: Slider(
                value: _strokeWidth.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                label: _strokeWidth.toString(),
                onChanged: (value) {
                  setState(() {
                    _strokeWidth = value.toInt();
                  });
                  _desktopLyricService.setStrokeWidth(_strokeWidth);
                },
              ),
              trailing: Text('$_strokeWidth'),
            ),

            // 可拖动
            SwitchListTile(
              secondary: const Icon(Icons.open_with),
              title: const Text('允许拖动'),
              subtitle: const Text('鼠标可以拖动歌词窗口'),
              value: _isDraggable,
              onChanged: (value) {
                setState(() {
                  _isDraggable = value;
                });
                _desktopLyricService.setDraggable(value);
              },
            ),

            // 鼠标穿透
            SwitchListTile(
              secondary: const Icon(Icons.touch_app),
              title: const Text('鼠标穿透'),
              subtitle: const Text('歌词窗口不响应鼠标事件'),
              value: _isMouseTransparent,
              onChanged: (value) {
                setState(() {
                  _isMouseTransparent = value;
                });
                _desktopLyricService.setMouseTransparent(value);
              },
            ),

            const SizedBox(height: 16),
            
            // 测试按钮
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  _desktopLyricService.setLyricText('这是测试歌词 - This is a test lyric');
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('测试歌词显示'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
