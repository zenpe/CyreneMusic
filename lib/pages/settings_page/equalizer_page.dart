import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import '../../services/player_service.dart';
import '../../utils/theme_manager.dart';

/// 均衡器内容组件（二级页面内容）
class EqualizerContent extends StatefulWidget {
  final VoidCallback onBack;
  final bool embed;

  const EqualizerContent({
    super.key,
    required this.onBack,
    this.embed = false,
  });

  @override
  State<EqualizerContent> createState() => _EqualizerContentState();
}

class _EqualizerContentState extends State<EqualizerContent> {
  // 预设
  final Map<String, List<double>> _presets = {
    '默认': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    '流行 (Pop)': [4, 2, 0, -2, -4, -4, -2, 0, 2, 4],
    '摇滚 (Rock)': [5, 3, 1, 0, -1, 0, 1, 3, 5, 6],
    '爵士 (Jazz)': [3, 2, 0, 2, 2, 2, 0, 2, 4, 5],
    '古典 (Classical)': [5, 3, 2, 0, -1, 0, 2, 4, 5, 6],
    '低音增强 (Bass)': [7, 5, 3, 1, 0, 0, 0, 0, 0, 0],
    '人声 (Vocal)': [-2, -2, -1, 0, 3, 5, 4, 2, 0, -1],
    '舞曲 (Dance)': [6, 4, 2, 0, 0, 0, 2, 4, 4, 4],
    'R&B': [3, 7, 3, -2, -3, -2, 2, 4, 5, 6],
    '电子 (Electronic)': [6, 4, 0, -2, -4, -2, 0, 2, 4, 6],
    '嘻哈 (Hip-Hop)': [5, 3, 0, -1, -1, -1, 0, 2, 4, 5],
    '原声 (Acoustic)': [3, 2, 1, 1, 1, 1, 2, 3, 3, 4],
    '钢琴 (Piano)': [2, 1, 0, 2, 3, 2, 1, 2, 4, 5],
    '高音增强 (Treble Boost)': [0, 0, 0, 0, 0, 1, 3, 5, 6, 8],
    '耳机 (Headphone)': [3, 5, 4, 1, 1, 1, 3, 5, 4, 2],
  };

  @override
  Widget build(BuildContext context) {
    if (ThemeManager().isFluentFramework) {
      return _buildFluentBody();
    } else if (ThemeManager().isCupertinoFramework) {
      return _buildCupertinoBody();
    } else {
      return _buildMaterialBody();
    }
  }

  Widget _buildMaterialBody() {
    final playerService = PlayerService();
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final available = playerService.isEqualizerAvailable;
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;
        if (!available) return _buildMaterialUnavailable(cs);

        return Column(
          children: [
            // 提示：不同音源/格式效果可能有差异
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '不同音源和编码格式的均衡器效果可能存在差异',
                      style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 启用开关（仅在嵌入模式下显示在列表中）
            if (widget.embed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Expanded(child: Text('启用均衡器', style: TextStyle(fontWeight: FontWeight.bold))),
                    Switch(
                      value: enabled,
                      onChanged: (value) {
                        playerService.setEqualizerEnabled(value);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            // 预设选择
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _presets.length,
                itemBuilder: (context, index) {
                  final name = _presets.keys.elementAt(index);
                  final presetGains = _presets[name]!;

                  bool isSelected = true;
                  for (int i = 0; i < 10; i++) {
                    if ((gains[i] - presetGains[i]).abs() > 0.1) {
                      isSelected = false;
                      break;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilterChip(
                      label: Text(name),
                      selected: isSelected,
                      onSelected: enabled
                          ? (selected) {
                              if (selected) {
                                playerService.updateEqualizer(presetGains);
                              }
                            }
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: BorderSide.none,
                      backgroundColor: cs.surfaceContainerHigh,
                      selectedColor: cs.primaryContainer,
                      labelStyle: TextStyle(
                        color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      showCheckmark: false,
                    ),
                  );
                },
              ),
            ),

            // 均衡器推子区域
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Opacity(
                  opacity: enabled ? 1.0 : 0.4,
                  child: AbsorbPointer(
                    absorbing: !enabled,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth / 10;

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(10, (index) {
                            final freq = PlayerService.kEqualizerFrequencies[index];
                            final gain = gains[index];

                            String freqLabel;
                            if (freq >= 1000) {
                              freqLabel = '${freq ~/ 1000}k';
                            } else {
                              freqLabel = '$freq';
                            }

                            return SizedBox(
                              width: width,
                              child: Column(
                                children: [
                                  // 增益值显示
                                  Text(
                                    '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  // 垂直滑块
                                  Expanded(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 24,
                                          trackShape: const _SplitCapsuleSliderTrackShape(),
                                          thumbShape: const _LineSliderThumbShape(),
                                          overlayShape: SliderComponentShape.noOverlay,
                                          activeTrackColor: cs.primary,
                                          inactiveTrackColor: cs.surfaceContainerHighest,
                                          thumbColor: cs.primary,
                                        ),
                                        child: Slider(
                                          value: gain,
                                          min: -12.0,
                                          max: 12.0,
                                          onChanged: (value) {
                                            final newGains = List<double>.from(gains);
                                            newGains[index] = value;
                                            playerService.updateEqualizer(newGains);
                                          },
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 12),
                                  // 频率标签
                                  Text(
                                    freqLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // 底部提示
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                '提示：调节过大可能会导致失真',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCupertinoBody() {
    final playerService = PlayerService();
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final available = playerService.isEqualizerAvailable;
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;
        final primaryColor = CupertinoTheme.of(context).primaryColor;
        if (!available) return _buildCupertinoUnavailable(context);
        
        return Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              // 启用状态 (仅嵌入模式)
              if (widget.embed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Expanded(child: Text('启用均衡器', style: TextStyle(fontSize: 17))),
                      CupertinoSwitch(
                        value: enabled,
                        onChanged: (value) {
                          playerService.setEqualizerEnabled(value);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              // 提示
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey6.resolveFrom(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.info, size: 16, color: CupertinoColors.label.resolveFrom(context).withOpacity(0.6)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '不同音源和编码格式的均衡器效果可能存在差异',
                        style: TextStyle(
                          color: CupertinoColors.label.resolveFrom(context).withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 预设选择
              Container(
                height: 44,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _presets.length,
                  itemBuilder: (context, index) {
                    final name = _presets.keys.elementAt(index);
                    final presetGains = _presets[name]!;
                    
                    bool isSelected = true;
                    for (int i = 0; i < 10; i++) {
                      if ((gains[i] - presetGains[i]).abs() > 0.1) {
                        isSelected = false;
                        break;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: enabled ? () {
                           playerService.updateEqualizer(presetGains);
                        } : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : CupertinoColors.systemGrey5.resolveFrom(context),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? CupertinoColors.white : CupertinoColors.label.resolveFrom(context),
                              fontSize: 14,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              const Padding(
                 padding: EdgeInsets.symmetric(horizontal: 16),
                 child: Divider(height: 1, color: CupertinoColors.systemGrey5),
              ),
              
              // 均衡器推子区域
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Opacity(
                    opacity: enabled ? 1.0 : 0.5,
                    child: AbsorbPointer(
                      absorbing: !enabled,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth / 10;
                          
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: List.generate(10, (index) {
                              final freq = PlayerService.kEqualizerFrequencies[index];
                              final gain = gains[index];
                              
                              String freqLabel;
                              if (freq >= 1000) {
                                freqLabel = '${freq ~/ 1000}k';
                              } else {
                                freqLabel = '$freq';
                              }

                              return SizedBox(
                                width: width,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: CupertinoColors.label.resolveFrom(context).withOpacity(0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: RotatedBox(
                                        quarterTurns: 3,
                                        child: CupertinoSlider(
                                          value: gain,
                                          min: -12.0,
                                          max: 12.0,
                                          onChanged: (value) {
                                            final newGains = List<double>.from(gains);
                                            newGains[index] = value;
                                            playerService.updateEqualizer(newGains);
                                          },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      freqLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.label.resolveFrom(context).withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  '提示：调节过大可能会导致失真',
                  style: TextStyle(color: CupertinoColors.secondaryLabel.resolveFrom(context), fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFluentBody() {
    final playerService = PlayerService();
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final available = playerService.isEqualizerAvailable;
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;
        final theme = fluent.FluentTheme.of(context);
        if (!available) return _buildFluentUnavailable(context);
        
        return fluent.ListView(
          padding: widget.embed ? const EdgeInsets.all(24) : const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // 启用开关
            fluent.Card(
              child: Row(
                children: [
                  const Icon(fluent.FluentIcons.equalizer, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('均衡器', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('自定义音频频率响应', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  fluent.ToggleSwitch(
                    checked: enabled,
                    onChanged: (value) {
                      playerService.setEqualizerEnabled(value);
                      setState(() {});
                    },
                    content: Text(enabled ? '已开启' : '已关闭'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 提示信息
            fluent.InfoBar(
              title: const Text('提示'),
              content: const Text('不同音源和编码格式的均衡器效果可能存在差异。'),
              severity: fluent.InfoBarSeverity.info,
              isIconVisible: true,
            ),
            const SizedBox(height: 16),

            // 预设选择
            fluent.Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text('预设选项', style: TextStyle(fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   fluent.ComboBox<String>(
                    placeholder: const Text('选择预设'),
                    isExpanded: true,
                    value: _getCurrentPresetName(gains),
                    items: _presets.keys.map((name) {
                      return fluent.ComboBoxItem<String>(
                        value: name,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: enabled ? (name) {
                      if (name != null) {
                        playerService.updateEqualizer(_presets[name]!);
                      }
                    } : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 推子区域
            fluent.Card(
              child: SizedBox(
                height: 300,
                child: Opacity(
                  opacity: enabled ? 1.0 : 0.5,
                  child: AbsorbPointer(
                    absorbing: !enabled,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth / 10;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(10, (index) {
                            final freq = PlayerService.kEqualizerFrequencies[index];
                            final gain = gains[index];
                            String freqLabel = freq >= 1000 ? '${freq ~/ 1000}k' : '$freq';

                            return SizedBox(
                              width: width,
                              child: Column(
                                children: [
                                  Text(
                                    '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                                    style: TextStyle(fontSize: 10, color: theme.accentColor),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: fluent.Slider(
                                        value: gain,
                                        min: -12.0,
                                        max: 12.0,
                                        onChanged: (value) {
                                          final newGains = List<double>.from(gains);
                                          newGains[index] = value;
                                          playerService.updateEqualizer(newGains);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    freqLabel,
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                '提示：调节过大可能会导致失真',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMaterialUnavailable(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '当前平台暂不支持均衡器',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildCupertinoUnavailable(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '当前平台暂不支持均衡器',
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildFluentUnavailable(BuildContext context) {
    return fluent.ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: const [
        fluent.InfoBar(
          title: Text('均衡器不可用'),
          content: Text('当前平台暂不支持均衡器。'),
          severity: fluent.InfoBarSeverity.warning,
          isIconVisible: true,
        ),
      ],
    );
  }

  String? _getCurrentPresetName(List<double> gains) {
    for (var entry in _presets.entries) {
      bool matched = true;
      for (int i = 0; i < 10; i++) {
        if ((gains[i] - entry.value[i]).abs() > 0.1) {
          matched = false;
          break;
        }
      }
      if (matched) return entry.key;
    }
    return null;
  }
}

class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (ThemeManager().isFluentFramework) {
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: const Text('均衡器'),
        ),
        content: EqualizerContent(onBack: () => Navigator.pop(context)),
      );
    } else if (ThemeManager().isCupertinoFramework) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: const Text('均衡器'),
          trailing: ListenableBuilder(
            listenable: PlayerService(),
            builder: (context, _) {
              final player = PlayerService();
              return CupertinoSwitch(
                value: player.equalizerEnabled,
                onChanged: player.isEqualizerAvailable
                    ? (value) => player.setEqualizerEnabled(value)
                    : null,
              );
            },
          ),
        ),
        child: SafeArea(
          child: EqualizerContent(onBack: () => Navigator.pop(context)),
        ),
      );
    } else {
      final colorScheme = Theme.of(context).colorScheme;
      return Scaffold(
        backgroundColor: colorScheme.surfaceContainerLow,
        appBar: AppBar(
          title: const Text('均衡器', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: colorScheme.surfaceContainerLow,
          surfaceTintColor: Colors.transparent,
          actions: [
            ListenableBuilder(
              listenable: PlayerService(),
              builder: (context, _) {
                final player = PlayerService();
                return Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: player.equalizerEnabled,
                    onChanged: player.isEqualizerAvailable
                        ? (value) => player.setEqualizerEnabled(value)
                        : null,
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: EqualizerContent(onBack: () => Navigator.pop(context)),
      );
    }
  }
}

// 保持原有的 Custom Painter 类
class _SplitCapsuleSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _SplitCapsuleSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) return;

    final ColorTween activeTrackColorTween = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    );
    final ColorTween inactiveTrackColorTween = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    );
    final Paint activePaint = Paint()
      ..color = activeTrackColorTween.evaluate(enableAnimation)!;
    final Paint inactivePaint = Paint()
      ..color = inactiveTrackColorTween.evaluate(enableAnimation)!;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    const double gapHeight = 4.5;

    final Rect leftTrackRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx - gapHeight,
      trackRect.bottom,
    );
    
    if (leftTrackRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          leftTrackRect.left,
          leftTrackRect.top,
          leftTrackRect.right,
          leftTrackRect.bottom,
          topLeft: Radius.circular(trackRect.height / 2),
          bottomLeft: Radius.circular(trackRect.height / 2),
          topRight: const Radius.circular(3.0),
          bottomRight: const Radius.circular(3.0),
        ),
        activePaint,
      );
    }

    final Rect rightTrackRect = Rect.fromLTRB(
      thumbCenter.dx + gapHeight,
      trackRect.top,
      trackRect.right,
      trackRect.bottom,
    );
    
    if (rightTrackRect.width > 0) {
      context.canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          rightTrackRect.left,
          rightTrackRect.top,
          rightTrackRect.right,
          rightTrackRect.bottom,
          topLeft: const Radius.circular(3.0),
          bottomLeft: const Radius.circular(3.0),
          topRight: Radius.circular(trackRect.height / 2),
          bottomRight: Radius.circular(trackRect.height / 2),
        ),
        inactivePaint,
      );
    }
  }
}

class _LineSliderThumbShape extends SliderComponentShape {
  const _LineSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(8, 28);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    
    final Paint paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.blue
      ..style = PaintingStyle.fill;

    final double currentWidth = 4.0 - (2.0 * activationAnimation.value);

    final RRect line = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: currentWidth, height: 28.0),
      Radius.circular(currentWidth / 2),
    );
    
    canvas.drawRRect(line, paint);
  }
}
