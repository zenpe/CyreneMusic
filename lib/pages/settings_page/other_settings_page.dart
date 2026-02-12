import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../models/playlist.dart';
import '../../services/app_settings_service.dart';
import '../../services/auth_service.dart';
import '../../services/playlist_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
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

  String _startupQueueModeLabel(StartupQueueMode mode) {
    switch (mode) {
      case StartupQueueMode.none:
        return '不加载';
      case StartupQueueMode.favorites:
        return '我的收藏';
      case StartupQueueMode.specificPlaylist:
        return '指定歌单';
    }
  }

  String _startupQueueModeSubtitle(AppSettingsService settings) {
    switch (settings.startupQueueMode) {
      case StartupQueueMode.none:
        return '启动时不预加载播放队列';
      case StartupQueueMode.favorites:
        return '启动时加载我的收藏';
      case StartupQueueMode.specificPlaylist:
        final playlistName = settings.startupQueuePlaylistName;
        if (playlistName != null && playlistName.isNotEmpty) {
          return '启动时加载：$playlistName';
        }
        return '指定歌单尚未选择';
    }
  }

  Future<void> _applyStartupQueueMode(StartupQueueMode mode) async {
    final settings = AppSettingsService();
    await settings.setStartupQueueMode(mode);
    if (!mounted) return;

    if (mode == StartupQueueMode.specificPlaylist &&
        settings.startupQueuePlaylistId == null) {
      await _selectStartupPlaylist();
    }
  }

  Future<List<Playlist>> _loadAvailablePlaylists() async {
    if (!AuthService().isLoggedIn) return [];
    final playlistService = PlaylistService();
    await playlistService.loadPlaylists();
    return List<Playlist>.from(playlistService.playlists);
  }

  Future<void> _selectStartupPlaylist() async {
    if (!AuthService().isLoggedIn) {
      _showMessage(context, '请先登录后再选择启动歌单');
      return;
    }

    final playlists = await _loadAvailablePlaylists();
    if (!mounted) return;
    if (playlists.isEmpty) {
      _showMessage(context, '未找到可用歌单');
      return;
    }

    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    final isCupertinoUI =
        (Platform.isIOS || Platform.isAndroid) &&
        ThemeManager().isCupertinoFramework;

    Playlist? selected;
    if (isFluentUI) {
      selected = await _showPlaylistPickerFluent(context, playlists);
    } else if (isCupertinoUI) {
      selected = await _showPlaylistPickerCupertino(context, playlists);
    } else {
      selected = await _showPlaylistPickerMaterial(context, playlists);
    }

    if (selected == null) return;
    await AppSettingsService().setStartupQueuePlaylist(
      playlistId: selected.id,
      playlistName: selected.name,
    );
  }

  Future<Playlist?> _showPlaylistPickerMaterial(
    BuildContext context,
    List<Playlist> playlists,
  ) {
    return showDialog<Playlist>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择启动歌单'),
        content: SizedBox(
          width: 420,
          height: 360,
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return ListTile(
                title: Text(playlist.name),
                subtitle: playlist.isDefault ? const Text('我的收藏') : null,
                onTap: () => Navigator.pop(dialogContext, playlist),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<Playlist?> _showPlaylistPickerFluent(
    BuildContext context,
    List<Playlist> playlists,
  ) {
    return fluent_ui.showDialog<Playlist>(
      context: context,
      builder: (dialogContext) => fluent_ui.ContentDialog(
        title: const Text('选择启动歌单'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: ListView.separated(
            itemCount: playlists.length,
            separatorBuilder: (context, index) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final label = playlist.isDefault
                  ? '${playlist.name}（我的收藏）'
                  : playlist.name;
              return fluent_ui.Button(
                onPressed: () => Navigator.pop(dialogContext, playlist),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label),
                ),
              );
            },
          ),
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<Playlist?> _showPlaylistPickerCupertino(
    BuildContext context,
    List<Playlist> playlists,
  ) {
    return showCupertinoModalPopup<Playlist>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('选择启动歌单'),
        actions: playlists.map((playlist) {
          final label = playlist.isDefault
              ? '${playlist.name}（我的收藏）'
              : playlist.name;
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(popupContext, playlist),
            child: Text(label),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  Future<void> _showStartupQueueModeDialogMaterial(BuildContext context) {
    final settings = AppSettingsService();
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('启动队列来源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: StartupQueueMode.values.map((mode) {
            return RadioListTile<StartupQueueMode>(
              value: mode,
              groupValue: settings.startupQueueMode,
              title: Text(_startupQueueModeLabel(mode)),
              onChanged: (value) async {
                if (value == null) return;
                Navigator.pop(dialogContext);
                await _applyStartupQueueMode(value);
              },
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStartupQueueModeDialogFluent(BuildContext context) {
    final settings = AppSettingsService();
    return fluent_ui.showDialog<void>(
      context: context,
      builder: (dialogContext) => fluent_ui.ContentDialog(
        title: const Text('启动队列来源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: StartupQueueMode.values.map((mode) {
            return fluent_ui.RadioButton(
              content: Text(_startupQueueModeLabel(mode)),
              checked: settings.startupQueueMode == mode,
              onChanged: (_) async {
                Navigator.pop(dialogContext);
                await _applyStartupQueueMode(mode);
              },
            );
          }).toList(),
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStartupQueueModeDialogCupertino(BuildContext context) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (popupContext) => CupertinoActionSheet(
        title: const Text('启动队列来源'),
        actions: StartupQueueMode.values.map((mode) {
          return CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(popupContext);
              await _applyStartupQueueMode(mode);
            },
            child: Text(_startupQueueModeLabel(mode)),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(popupContext),
          child: const Text('取消'),
        ),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
      return;
    }
    print('ℹ️ [OtherSettings] $message');
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
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            MD3SettingsSection(
              title: '启动行为',
              children: [
                MD3SettingsTile(
                  leading: const Icon(Icons.queue_music_outlined),
                  title: '启动时加载播放队列',
                  subtitle: _startupQueueModeSubtitle(settings),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showStartupQueueModeDialogMaterial(context),
                ),
                if (settings.startupQueueMode ==
                    StartupQueueMode.specificPlaylist)
                  MD3SettingsTile(
                    leading: const Icon(Icons.playlist_play_outlined),
                    title: '启动歌单',
                    subtitle: settings.startupQueuePlaylistName ?? '未选择（点击选择）',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _selectStartupPlaylist,
                  ),
                MD3SwitchTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
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
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return ListView(
          padding: const EdgeInsets.only(top: 20),
          children: [
            CupertinoSettingsSection(
              header: '启动行为',
              children: [
                CupertinoSettingsTile(
                  icon: CupertinoIcons.music_note_list,
                  iconColor: CupertinoColors.systemIndigo,
                  title: '启动时加载播放队列',
                  subtitle: _startupQueueModeSubtitle(settings),
                  showChevron: true,
                  onTap: () => _showStartupQueueModeDialogCupertino(context),
                ),
                if (settings.startupQueueMode ==
                    StartupQueueMode.specificPlaylist)
                  CupertinoSettingsTile(
                    icon: CupertinoIcons.music_albums,
                    iconColor: CupertinoColors.systemBlue,
                    title: '启动歌单',
                    subtitle: settings.startupQueuePlaylistName ?? '未选择（点击选择）',
                    showChevron: true,
                    onTap: _selectStartupPlaylist,
                  ),
                CupertinoSwitchTile(
                  icon: CupertinoIcons.arrow_counterclockwise,
                  iconColor: CupertinoColors.systemBlue,
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
                  },
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
      animation: AppSettingsService(),
      builder: (context, _) {
        final settings = AppSettingsService();
        return fluent_ui.ListView(
          padding: const EdgeInsets.all(24),
          children: [
            FluentSettingsGroup(
              title: '启动行为',
              children: [
                FluentSettingsTile(
                  icon: fluent_ui.FluentIcons.music_in_collection_fill,
                  title: '启动时加载播放队列',
                  subtitle: _startupQueueModeSubtitle(settings),
                  trailing: const Icon(
                    fluent_ui.FluentIcons.chevron_right,
                    size: 12,
                  ),
                  onTap: () => _showStartupQueueModeDialogFluent(context),
                ),
                if (settings.startupQueueMode ==
                    StartupQueueMode.specificPlaylist)
                  FluentSettingsTile(
                    icon: fluent_ui.FluentIcons.music_note,
                    title: '启动歌单',
                    subtitle: settings.startupQueuePlaylistName ?? '未选择（点击选择）',
                    trailing: const Icon(
                      fluent_ui.FluentIcons.chevron_right,
                      size: 12,
                    ),
                    onTap: _selectStartupPlaylist,
                  ),
                FluentSwitchTile(
                  icon: fluent_ui.FluentIcons.history,
                  title: '启动时提示恢复播放',
                  subtitle: '开启后启动时会提示从上次位置继续',
                  value: settings.showResumePromptOnStartup,
                  onChanged: (value) {
                    settings.setShowResumePromptOnStartup(value);
                  },
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
          ],
        );
      },
    );
  }
}
