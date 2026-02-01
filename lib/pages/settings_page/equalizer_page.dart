import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import '../../services/player_service.dart';
import '../../utils/theme_manager.dart';

class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
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
      return _buildFluentPage();
    } else if (ThemeManager().isCupertinoFramework) {
      return _buildCupertinoPage();
    } else {
      return _buildMaterialPage();
    }
  }

  Widget _buildMaterialPage() {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: Text(
          '均衡器',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        actions: [
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: PlayerService().equalizerEnabled,
              onChanged: (value) {
                PlayerService().setEqualizerEnabled(value);
                setState(() {});
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildMaterialBody(context),
    );
  }

  Widget _buildMaterialBody(BuildContext context) {
    final playerService = PlayerService();
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;

        return Column(
          children: [
            // 提示：均衡器目前仅支持mp3格式
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
                      '均衡器目前仅支持mp3格式，暂时不支持无损音质和Hi-Res音质',
                      style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontSize: 12,
                      ),
                    ),
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

  Widget _buildCupertinoPage() {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('均衡器'),
        trailing: CupertinoSwitch(
          value: PlayerService().equalizerEnabled,
          onChanged: (value) {
            PlayerService().setEqualizerEnabled(value);
            setState(() {});
          },
        ),
      ),
      child: SafeArea(child: _buildCupertinoBody(context)),
    );
  }

  Widget _buildCupertinoBody(BuildContext context) {
    final playerService = PlayerService();
    // 使用 ListenabableBuilder 监听 updateEqualizer 的变化
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;
        final primaryColor = CupertinoTheme.of(context).primaryColor;
        
        return Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              // 提示：均衡器目前仅支持mp3格式
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
                      '均衡器目前仅支持mp3格式，暂时不支持无损音质和Hi-Res音质',
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
                        // 计算每个推子的宽度
                        final width = constraints.maxWidth / 10;
                        
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(10, (index) {
                            final freq = PlayerService.kEqualizerFrequencies[index];
                            final gain = gains[index];
                            
                            // 显示频率标签
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
                                  // 增益值显示
                                  Text(
                                    '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: CupertinoColors.label.resolveFrom(context).withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // 垂直滑块
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
                                  // 频率标签
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
            
            // 底部提示
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

  Widget _buildFluentPage() {
    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: const Text('均衡器'),
        commandBar: fluent.ToggleSwitch(
          checked: PlayerService().equalizerEnabled,
          onChanged: (value) {
            PlayerService().setEqualizerEnabled(value);
            setState(() {});
          },
          content: Text(PlayerService().equalizerEnabled ? '已启用' : '已禁用'),
        ),
      ),
      content: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final playerService = PlayerService();
    // 使用 ListenabableBuilder 监听 updateEqualizer 的变化
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final gains = playerService.equalizerGains;
        final enabled = playerService.equalizerEnabled;
        
        return Material(
          type: MaterialType.transparency,
          child: Column(
            children: [
              // 提示：均衡器目前仅支持mp3格式
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '均衡器目前仅支持mp3格式，暂时不支持无损音质和Hi-Res音质',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 预设选择
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 50,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _presets.length,
                itemBuilder: (context, index) {
                  final name = _presets.keys.elementAt(index);
                  final presetGains = _presets[name]!;
                  
                  // 简单的匹配逻辑：如果当前 gains 与预设非常接近，则高亮
                  bool isSelected = true;
                  for (int i = 0; i < 10; i++) {
                    if ((gains[i] - presetGains[i]).abs() > 0.1) {
                      isSelected = false;
                      break;
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: isSelected,
                      onSelected: enabled ? (selected) {
                        if (selected) {
                          playerService.updateEqualizer(presetGains);
                        }
                      } : null,
                    ),
                  );
                },
              ),
            ),
            
            const Divider(),
            
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
                        // 计算每个推子的宽度
                        final width = constraints.maxWidth / 10;
                        
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(10, (index) {
                            final freq = PlayerService.kEqualizerFrequencies[index];
                            final gain = gains[index];
                            
                            // 显示频率标签
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
                                  // 增益值显示
                                  Text(
                                    '${gain > 0 ? "+" : ""}${gain.toStringAsFixed(1)}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  const SizedBox(height: 8),
                                  
                                  // 垂直滑块
                                  Expanded(
                                    child: RotatedBox(
                                      quarterTurns: 3,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
                                  
                                  const SizedBox(height: 8),
                                  // 频率标签
                                  Text(
                                    freqLabel,
                                    style: const TextStyle(fontSize: 10),
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
              padding: const EdgeInsets.all(16.0),
              child: Text(
                '提示：调节过大可能会导致失真',
                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
              ),
            ),
            ],
          ),
        );
      },
    );
  }
}

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

    const double gapHeight = 4.5; // 间隙大小

    // 绘制活跃部分 (左侧/底部)
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
          topRight: const Radius.circular(3.0), // 近直角
          bottomRight: const Radius.circular(3.0), // 近直角
        ),
        activePaint,
      );
    }

    // 绘制非活跃部分 (右侧/顶部)
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
          topLeft: const Radius.circular(3.0), // 近直角
          bottomLeft: const Radius.circular(3.0), // 近直角
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

    // 滑块在激活时（拖动时）变细：从 4.0 变为 2.0
    final double currentWidth = 4.0 - (2.0 * activationAnimation.value);

    // 绘制一个圆角横滑块
    final RRect line = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: currentWidth, height: 28.0),
      Radius.circular(currentWidth / 2),
    );
    
    canvas.drawRRect(line, paint);
  }
}
