import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../widgets/material/material_settings_widgets.dart';
import '../../services/developer_mode_service.dart';
import '../../utils/theme_manager.dart';


/// 搜索设置组件
class SearchSettings extends StatefulWidget {
  const SearchSettings({super.key});

  @override
  State<SearchSettings> createState() => _SearchSettingsState();
}

class _SearchSettingsState extends State<SearchSettings> {
  @override
  void initState() {
    super.initState();
    DeveloperModeService().addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    DeveloperModeService().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;

    if (isFluent) {
      return FluentSettingsGroup(
        title: '搜索',
        children: [
          FluentSettingsTile(
            icon: Icons.merge_type,
            title: '合并搜索结果',
            subtitle: DeveloperModeService().isSearchResultMergeEnabled
                ? '开启：聚合多平台相同歌曲'
                : '关闭：分平台显示结果',
            trailing: fluent_ui.ToggleSwitch(
              checked: DeveloperModeService().isSearchResultMergeEnabled,
              onChanged: (value) {
                DeveloperModeService().toggleSearchResultMerge(value);
              },
            ),
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
          leading: const Icon(Icons.merge_type_outlined),
          title: '合并搜索结果',
          subtitle: DeveloperModeService().isSearchResultMergeEnabled
              ? '开启：聚合多平台相同歌曲'
              : '关闭：分平台显示结果',
          trailing: Switch.adaptive(
            value: DeveloperModeService().isSearchResultMergeEnabled,
            onChanged: (value) {
              DeveloperModeService().toggleSearchResultMerge(value);
            },
          ),
        ),
      ],
    );
  }

  /// 构建 Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context) {
    
    return CupertinoSettingsTile(
      icon: CupertinoIcons.arrow_merge,
      iconColor: CupertinoColors.systemBlue,
      title: '合并搜索结果',
      subtitle: DeveloperModeService().isSearchResultMergeEnabled
          ? '聚合多平台相同歌曲'
          : '分平台显示结果',
      showChevron: false,
      trailing: CupertinoSwitch(
        value: DeveloperModeService().isSearchResultMergeEnabled,
        onChanged: (value) {
          DeveloperModeService().toggleSearchResultMerge(value);
        },
        activeTrackColor: CupertinoColors.systemBlue,
      ),
    );
  }
}
