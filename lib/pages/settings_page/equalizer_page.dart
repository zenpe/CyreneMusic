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
    return Scaffold(
      appBar: AppBar(
        title: const Text('均衡器'),
        actions: [
          Switch(
            value: PlayerService().equalizerEnabled,
            onChanged: (value) {
              PlayerService().setEqualizerEnabled(value);
              setState(() {});
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _buildBody(context),
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
      child: SafeArea(child: _buildBody(context)),
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
        
        return Column(
          children: [
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
        );
      },
    );
  }
}
