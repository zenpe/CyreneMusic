import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../services/audio_quality_service.dart';
import '../../services/audio_source_service.dart';
import '../../services/player_service.dart';
import '../../models/song_detail.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import 'equalizer_page.dart';


/// 播放设置组件
class PlaybackSettings extends StatelessWidget {
  const PlaybackSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;
    final qualityService = AudioQualityService();

    // 使用 ListenableBuilder 监听音质变化，实现实时刷新
    return ListenableBuilder(
      listenable: qualityService,
      builder: (context, child) {
        if (isFluent) {
          return FluentSettingsGroup(
            title: '播放',
            children: [
              FluentSettingsTile(
                icon: Icons.high_quality,
                title: '音质选择',
                subtitle:
                    '${qualityService.getQualityName()} - ${qualityService.getQualityDescription()}',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showAudioQualityDialogFluent(context),
              ),
              FluentSettingsTile(
                icon: Icons.graphic_eq,
                title: '均衡器',
                subtitle: '调节音频频率响应',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context, fluent_ui.FluentPageRoute(builder: (_) => const EqualizerPage())),
              ),
            ],
          );
        }

        if (isCupertino) {
          return Column(
            children: [
              _buildCupertinoUI(context, qualityService),
              _buildCupertinoEqualizerLink(context),
            ],
          );
        }

        return MD3SettingsSection(
          children: [
            MD3SettingsTile(
              leading: const Icon(Icons.high_quality_outlined),
              title: '音质选择',
              subtitle: '${qualityService.getQualityName()} - ${qualityService.getQualityDescription()}',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showAudioQualityDialog(context),
            ),
            MD3SettingsTile(
              leading: const Icon(Icons.graphic_eq),
              title: '均衡器',
              subtitle: '自定义音效',
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EqualizerPage())),
            ),
          ],
        );
      },
    );
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context, AudioQualityService qualityService) {
    return CupertinoSettingsTile(
      icon: CupertinoIcons.music_note_2,
      iconColor: CupertinoColors.systemPurple,
      title: '音质选择',
      subtitle: '${qualityService.getQualityName()} - ${qualityService.getQualityDescription()}',
      showChevron: true,
      onTap: () => _showAudioQualityDialogCupertino(context),
    );
  }

  Widget _buildCupertinoEqualizerLink(BuildContext context) {
    return CupertinoSettingsTile(
      icon: CupertinoIcons.waveform,
      iconColor: CupertinoColors.systemBlue,
      title: '均衡器',
      subtitle: '调节音频效果',
      showChevron: true,
      onTap: () => Navigator.push(context, CupertinoPageRoute(builder: (_) => const EqualizerPage())),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _showAudioQualityDialog(BuildContext context) {
    final qualityService = AudioQualityService();
    final currentQuality = qualityService.currentQuality;
    final sourceType = AudioSourceService().sourceType;
    final supportedQualities = qualityService.getSupportedQualities(sourceType);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择音质'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: supportedQualities.map((quality) => RadioListTile<AudioQuality>(
            title: Text(qualityService.getQualityName(quality)),
            subtitle: Text(qualityService.getQualityDescription(quality)),
            value: quality,
            groupValue: currentQuality,
            onChanged: (value) {
              if (value != null) {
                qualityService.setQuality(value);
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('音质设置已更新'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              }
            },
          )).toList(),
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

  void _showAudioQualityDialogFluent(BuildContext context) {
    final qualityService = AudioQualityService();
    final currentQuality = qualityService.currentQuality;
    final sourceType = AudioSourceService().sourceType;
    final supportedQualities = qualityService.getSupportedQualities(sourceType);

    fluent_ui.showDialog(
      context: context,
      builder: (context) {
        return fluent_ui.ContentDialog(
          title: const Text('选择音质'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: supportedQualities.map((quality) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: fluent_ui.RadioButton(
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(qualityService.getQualityName(quality)),
                    Text(
                      qualityService.getQualityDescription(quality),
                      style: fluent_ui.FluentTheme.of(context).typography.caption,
                    ),
                  ],
                ),
                checked: currentQuality == quality,
                onChanged: (v) {
                  qualityService.setQuality(quality);
                  Navigator.pop(context);
                },
              ),
            )).toList(),
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

  /// 显示 Cupertino 风格的音质选择对话框
  void _showAudioQualityDialogCupertino(BuildContext context) {
    final qualityService = AudioQualityService();
    final currentQuality = qualityService.currentQuality;
    final sourceType = AudioSourceService().sourceType;
    final supportedQualities = qualityService.getSupportedQualities(sourceType);
    
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择音质'),
        actions: supportedQualities.map((quality) => CupertinoActionSheetAction(
          onPressed: () {
            qualityService.setQuality(quality);
            Navigator.pop(context);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (currentQuality == quality)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(CupertinoIcons.checkmark, size: 18),
                ),
              Text(qualityService.getQualityName(quality)),
              const SizedBox(width: 8),
              Text(
                qualityService.getQualityDescription(quality),
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
              ),
            ],
          ),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
}
