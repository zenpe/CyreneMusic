import 'package:flutter/material.dart';
import '../../../services/lyric_style_service.dart';
import '../../../services/lyric_font_service.dart';

/// 歌词细节设置区域 - Material Design Expressive 风格
/// 现代化滑块设计，带圆形数值徽章
class LyricDetailSection extends StatelessWidget {
  const LyricDetailSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: LyricStyleService(),
      builder: (context, _) {
        final styleService = LyricStyleService();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.6 : 0.8),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Row(
                  children: [
                    Icon(
                      Icons.text_fields_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '歌词细节',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 歌词字体选择
                _buildFontSection(
                  context: context,
                  colorScheme: colorScheme,
                  isDark: isDark,
                ),

                const SizedBox(height: 20),

                // 字号调节
                _buildSliderSection(
                  context: context,
                  icon: Icons.format_size_rounded,
                  label: '歌词字号',
                  value: styleService.fontSize,
                  displayValue: '${styleService.fontSize.toInt()} px',
                  min: 24.0,
                  max: 48.0,
                  divisions: 24,
                  accentColor: colorScheme.primary,
                  onChanged: (v) => styleService.setFontSize(v),
                  colorScheme: colorScheme,
                  isDark: isDark,
                ),

                const SizedBox(height: 20),

                // 视觉模糊强度
                _buildSliderSection(
                  context: context,
                  icon: Icons.blur_on_rounded,
                  label: '视觉模糊',
                  value: styleService.blurSigma,
                  displayValue: styleService.blurSigma.toStringAsFixed(1),
                  min: 0.0,
                  max: 10.0,
                  divisions: 20,
                  accentColor: colorScheme.secondary,
                  onChanged: (v) => styleService.setBlurSigma(v),
                  colorScheme: colorScheme,
                  isDark: isDark,
                ),

                const SizedBox(height: 20),

                // 行间距调节
                _buildLineHeightSection(
                  context: context,
                  styleService: styleService,
                  colorScheme: colorScheme,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建滑块区域
  Widget _buildSliderSection({
    required BuildContext context,
    required IconData icon,
    required String label,
    required double value,
    required String displayValue,
    required double min,
    required double max,
    required int divisions,
    required Color accentColor,
    required ValueChanged<double> onChanged,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 圆形数值徽章
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.2),
                    accentColor.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Text(
                displayValue,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 滑块
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accentColor,
            inactiveTrackColor: colorScheme.surfaceContainerHigh,
            thumbColor: accentColor,
            overlayColor: accentColor.withValues(alpha: 0.15),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 4,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// 构建行间距区域（带自动/手动切换）
  Widget _buildLineHeightSection({
    required BuildContext context,
    required LyricStyleService styleService,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    final accentColor = colorScheme.tertiary;
    final isAuto = styleService.autoLineHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标签行
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.format_line_spacing_rounded,
                color: accentColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '歌词行间距',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // 分段按钮：自动/手动
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSegmentButton(
                    label: '自动',
                    icon: Icons.auto_awesome_rounded,
                    isSelected: isAuto,
                    onTap: () => styleService.setAutoLineHeight(true),
                    colorScheme: colorScheme,
                    accentColor: accentColor,
                  ),
                  _buildSegmentButton(
                    label: '手动',
                    icon: Icons.edit_rounded,
                    isSelected: !isAuto,
                    onTap: () => styleService.setAutoLineHeight(false),
                    colorScheme: colorScheme,
                    accentColor: accentColor,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 数值显示
        if (!isAuto)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.2),
                      accentColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${styleService.lineHeight.toInt()} px',
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),

        // 滑块
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: isAuto
                ? colorScheme.outline.withValues(alpha: 0.5)
                : accentColor,
            inactiveTrackColor: colorScheme.surfaceContainerHigh,
            thumbColor: isAuto
                ? colorScheme.outline.withValues(alpha: 0.5)
                : accentColor,
            overlayColor: accentColor.withValues(alpha: 0.15),
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 4,
            ),
            disabledActiveTrackColor: colorScheme.outline.withValues(alpha: 0.3),
            disabledInactiveTrackColor: colorScheme.surfaceContainerHigh,
            disabledThumbColor: colorScheme.outline.withValues(alpha: 0.5),
          ),
          child: Slider(
            value: styleService.lineHeight,
            min: 60.0,
            max: 180.0,
            onChanged: isAuto ? null : (v) => styleService.setLineHeight(v),
          ),
        ),
      ],
    );
  }

  /// 构建分段按钮
  Widget _buildSegmentButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    required Color accentColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? accentColor
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? accentColor
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建歌词字体选择区域
  Widget _buildFontSection({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    final fontService = LyricFontService();
    final accentColor = colorScheme.primary;

    return GestureDetector(
      onTap: () => _showFontPicker(context, colorScheme, isDark),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.font_download_rounded, color: accentColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '歌词字体',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fontService.currentFontName,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            size: 22,
          ),
        ],
      ),
    );
  }

  /// 显示歌词字体选择器
  void _showFontPicker(BuildContext context, ColorScheme colorScheme, bool isDark) {
    final fontService = LyricFontService();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AnimatedBuilder(
              animation: fontService,
              builder: (context, _) {
                return Container(
                  height: MediaQuery.of(context).size.height * 0.6,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: Column(
                    children: [
                      // 拖动指示器
                      Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.outline.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 标题
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.font_download_rounded,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '选择歌词字体',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const Spacer(),
                            // 关闭按钮
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      // 分隔线
                      Divider(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        height: 1,
                      ),
                      // 字体列表
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            // 自定义字体区域
                            _buildCustomFontSection(
                              context: context,
                              fontService: fontService,
                              colorScheme: colorScheme,
                            ),

                            // 分隔线
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      '系统字体',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // 预设字体列表
                            ...LyricFontService.platformFonts.map((font) {
                              final isSelected = fontService.fontType == 'preset' &&
                                                 fontService.presetFontId == font.id;

                              return ListTile(
                                onTap: () {
                                  fontService.setPresetFont(font.id);
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colorScheme.primary.withValues(alpha: 0.15)
                                        : colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      font.name.substring(0, 1),
                                      style: TextStyle(
                                        fontFamily: font.fontFamily,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? colorScheme.primary
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  font.name,
                                  style: TextStyle(
                                    fontFamily: font.fontFamily,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.onSurface,
                                  ),
                                ),
                                subtitle: Text(
                                  font.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: colorScheme.primary,
                                      )
                                    : null,
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// 构建自定义字体区域
  Widget _buildCustomFontSection({
    required BuildContext context,
    required LyricFontService fontService,
    required ColorScheme colorScheme,
  }) {
    final hasCustomFont = fontService.customFontPath != null;
    final isCustomSelected = fontService.fontType == 'custom';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 区域标题
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
          child: Row(
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 16,
                color: colorScheme.tertiary,
              ),
              const SizedBox(width: 6),
              Text(
                '自定义字体',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // 已导入的自定义字体
        if (hasCustomFont) ...[
          ListTile(
            onTap: () {
              // 选中自定义字体
              fontService.loadCustomFont(fontService.customFontPath!);
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isCustomSelected
                      ? [colorScheme.tertiary.withValues(alpha: 0.2), colorScheme.tertiary.withValues(alpha: 0.1)]
                      : [colorScheme.surfaceContainerHighest, colorScheme.surfaceContainerHighest],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.text_fields_rounded,
                color: isCustomSelected ? colorScheme.tertiary : colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            title: Text(
              fontService.currentFontName.replaceFirst('自定义: ', ''),
              style: TextStyle(
                fontWeight: isCustomSelected ? FontWeight.w700 : FontWeight.w500,
                color: isCustomSelected ? colorScheme.tertiary : colorScheme.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '已导入的自定义字体',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCustomSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: colorScheme.tertiary,
                  ),
                const SizedBox(width: 8),
                // 删除按钮
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: colorScheme.error.withValues(alpha: 0.7),
                    size: 20,
                  ),
                  onPressed: () {
                    fontService.clearCustomFont();
                  },
                  tooltip: '移除自定义字体',
                ),
              ],
            ),
          ),
        ],

        // 导入字体按钮
        ListTile(
          onTap: () async {
            final success = await fontService.pickAndLoadCustomFont();
            if (success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('字体导入成功'),
                  backgroundColor: colorScheme.primary,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            }
          },
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.3),
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Icon(
              Icons.add_rounded,
              color: colorScheme.primary,
              size: 22,
            ),
          ),
          title: Text(
            hasCustomFont ? '更换字体文件' : '导入字体文件',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          subtitle: Text(
            '支持 TTF、OTF、TTC 格式',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}
