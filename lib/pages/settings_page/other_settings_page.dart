import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;

import '../../services/app_settings_service.dart';
import '../../services/auth_credentials_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/material/material_settings_widgets.dart';

/// 其它设置详情内容（二级页面内容，嵌入在设置页面中）
class OtherSettingsContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;

  const OtherSettingsContent({
    super.key,
    required this.onBack,
    this.embed = false,
  });

  @override
  State<OtherSettingsContent> createState() => _OtherSettingsContentState();
}

class _OtherSettingsContentState extends State<OtherSettingsContent> {
  @override
  void initState() {
    super.initState();
    AppSettingsService().ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    final isCupertinoUI =
        (Platform.isIOS || Platform.isAndroid) &&
        ThemeManager().isCupertinoFramework;

    if (isFluentUI) {
      return _buildFluentUI(context);
    }

    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }

    return _buildMaterialUI(context);
  }

  Widget _buildMaterialUI(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettingsService(),
        AuthCredentialsService(),
      ]),
      builder: (context, _) {
        final settings = AppSettingsService();
        final credentials = AuthCredentialsService();
        final canToggleAutoPlay = settings.restorePlaybackSessionOnStartup;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            MD3SettingsSection(
              title: '启动行为',
              children: [
                MD3SwitchTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: '启动时恢复播放会话',
                  subtitle: '恢复上次的队列、当前歌曲和播放进度',
                  value: settings.restorePlaybackSessionOnStartup,
                  onChanged: (value) {
                    settings.setRestorePlaybackSessionOnStartup(value);
                  },
                ),
                MD3SwitchTile(
                  leading: const Icon(Icons.play_circle_outline),
                  title: '启动时自动播放',
                  subtitle: '需先开启恢复播放会话，恢复后自动开始播放，默认关闭',
                  value: settings.autoPlayAfterRestoreOnStartup,
                  enabled: canToggleAutoPlay,
                  onChanged: (value) {
                    settings.setAutoPlayAfterRestoreOnStartup(value);
                  },
                ),
                MD3SwitchTile(
                  leading: const Icon(Icons.system_update_alt_outlined),
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
            MD3SettingsSection(
              title: '登录',
              children: [
                MD3SwitchTile(
                  leading: const Icon(Icons.lock_person_outlined),
                  title: '记住登录信息',
                  subtitle: '关闭后不显示记住选项，并清除已保存的账号密码',
                  value: credentials.isRememberLoginEnabled,
                  onChanged: (value) {
                    credentials.setRememberLoginEnabled(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildCupertinoUI(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? CupertinoColors.black
        : CupertinoColors.systemGroupedBackground;

    final content = AnimatedBuilder(
      animation: Listenable.merge([
        AppSettingsService(),
        AuthCredentialsService(),
      ]),
      builder: (context, _) {
        final settings = AppSettingsService();
        final credentials = AuthCredentialsService();
        final canToggleAutoPlay = settings.restorePlaybackSessionOnStartup;
        return ListView(
          padding: const EdgeInsets.only(top: 20),
          children: [
            CupertinoSettingsSection(
              header: '启动行为',
              children: [
                CupertinoSwitchTile(
                  icon: CupertinoIcons.arrow_counterclockwise,
                  iconColor: CupertinoColors.systemBlue,
                  title: '启动时恢复播放会话',
                  subtitle: '恢复上次的队列、当前歌曲和播放进度',
                  value: settings.restorePlaybackSessionOnStartup,
                  onChanged: (value) {
                    settings.setRestorePlaybackSessionOnStartup(value);
                  },
                ),
                CupertinoSwitchTile(
                  icon: CupertinoIcons.play_circle,
                  iconColor: CupertinoColors.systemGreen,
                  title: '启动时自动播放',
                  subtitle: '需先开启恢复播放会话，恢复后自动开始播放，默认关闭',
                  value: settings.autoPlayAfterRestoreOnStartup,
                  onChanged: canToggleAutoPlay
                      ? (value) {
                          settings.setAutoPlayAfterRestoreOnStartup(value);
                        }
                      : null,
                ),
                CupertinoSwitchTile(
                  icon: CupertinoIcons.arrow_down_circle,
                  iconColor: CupertinoColors.systemOrange,
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
            CupertinoSettingsSection(
              header: '登录',
              children: [
                CupertinoSwitchTile(
                  icon: CupertinoIcons.lock_shield,
                  iconColor: CupertinoColors.systemPurple,
                  title: '记住登录信息',
                  subtitle: '关闭后不显示记住选项，并清除已保存的账号密码',
                  value: credentials.isRememberLoginEnabled,
                  onChanged: (value) {
                    credentials.setRememberLoginEnabled(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );

    if (widget.embed) {
      return Container(color: backgroundColor, child: content);
    }

    return CupertinoPageScaffold(
      backgroundColor: backgroundColor,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: backgroundColor.withOpacity(0.8),
        border: null,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: widget.onBack,
          child: const Icon(CupertinoIcons.back),
        ),
        middle: const Text('其它设置'),
      ),
      child: SafeArea(child: content),
    );
  }

  Widget _buildFluentUI(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppSettingsService(),
        AuthCredentialsService(),
      ]),
      builder: (context, _) {
        final settings = AppSettingsService();
        final credentials = AuthCredentialsService();
        final canToggleAutoPlay = settings.restorePlaybackSessionOnStartup;
        return fluent_ui.ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FluentSettingsGroup(
              title: '启动行为',
              children: [
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.history,
                  title: '启动时恢复播放会话',
                  subtitle: '恢复上次的队列、当前歌曲和播放进度',
                  value: settings.restorePlaybackSessionOnStartup,
                  onChanged: (value) {
                    settings.setRestorePlaybackSessionOnStartup(value);
                  },
                ),
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.play,
                  title: '启动时自动播放',
                  subtitle: '需先开启恢复播放会话，恢复后自动开始播放，默认关闭',
                  value: settings.autoPlayAfterRestoreOnStartup,
                  onChanged: canToggleAutoPlay
                      ? (value) {
                          settings.setAutoPlayAfterRestoreOnStartup(value);
                        }
                      : null,
                ),
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.sync,
                  title: '启动时弹出更新提示',
                  subtitle: '关闭后不再弹出更新提示页',
                  value: settings.showUpdatePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowUpdatePromptOnStartup(value);
                  },
                ),
              ],
            ),
            FluentSettingsGroup(
              title: '登录',
              children: [
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.lock,
                  title: '记住登录信息',
                  subtitle: '关闭后不显示记住选项，并清除已保存的账号密码',
                  value: credentials.isRememberLoginEnabled,
                  onChanged: (value) {
                    credentials.setRememberLoginEnabled(value);
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
