import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../utils/theme_manager.dart';
import '../../services/player_background_service.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/material/material_settings_widgets.dart';


/// 外观设置入口组件（显示在主设置页面）
class AppearanceSettings extends StatelessWidget {
  final VoidCallback? onTap;
  
  const AppearanceSettings({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertinoUI = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }
    
    return _buildMaterialUI(context);
  }
  
  /// 构建 Cupertino UI 版本 - 入口卡片
  Widget _buildCupertinoUI(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Cupertino 模式下使用 iOS 蓝色
    const iconColor = ThemeManager.iosBlue;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  CupertinoIcons.paintbrush_fill,
                  color: CupertinoColors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '外观设置',
                      style: TextStyle(
                        fontSize: 17,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getSubtitle(),
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                CupertinoIcons.chevron_forward,
                color: CupertinoColors.systemGrey,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建 Material UI 版本 - 入口卡片
  Widget _buildMaterialUI(BuildContext context) {
    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.palette_outlined),
          title: '外观设置',
          subtitle: _getSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ],
    );
  }

  /// 构建 Fluent UI 版本 - 入口卡片
  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '外观',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.color,
          title: '外观设置',
          subtitle: _getSubtitle(),
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: onTap,
        ),
      ],
    );
  }

  String _getSubtitle() {
    final themeMode = ThemeManager().themeMode;
    final themeModeStr = themeMode == ThemeMode.light 
        ? '亮色' 
        : (themeMode == ThemeMode.dark ? '暗色' : '跟随系统');
    final backgroundType = PlayerBackgroundService().getBackgroundTypeName();
    return '$themeModeStr · $backgroundType';
  }
}

