import 'package:flutter/material.dart';
import '../../../services/player_service.dart';
import '../../../services/system_volume_service.dart';

/// 音量调节设置区域 - Material Design Expressive 风格
class VolumeSection extends StatefulWidget {
  const VolumeSection({super.key});

  @override
  State<VolumeSection> createState() => _VolumeSectionState();
}

class _VolumeSectionState extends State<VolumeSection> {
  final _player = PlayerService();
  final _systemService = SystemVolumeService();
  bool _systemSupported = false;
  double _systemVolume = 0.0;

  @override
  void initState() {
    super.initState();
    _checkSystemVolume();
  }

  Future<void> _checkSystemVolume() async {
    try {
      final supported = await _systemService.isSupported();
      if (supported && mounted) {
        final vol = (await _systemService.getVolume()) ?? _player.volume;
        setState(() {
          _systemSupported = supported;
          _systemVolume = vol;
        });
      }
    } catch (_) {}
  }

  Widget _buildSliderRow({
    required BuildContext context,
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: colorScheme.primary),
        if (_systemSupported) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: colorScheme.primary,
              inactiveTrackColor: colorScheme.outlineVariant.withValues(alpha: 0.3),
              thumbColor: colorScheme.primary,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            '${(value * 100).toInt()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontFamily: 'Consolas',
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest
              .withValues(alpha: isDark ? 0.6 : 0.8),
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
                  Icons.volume_up_rounded,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  '音量调节',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 音量滑块
            AnimatedBuilder(
              animation: _player,
              builder: (context, _) {
                final appVolume = _player.volume;

                if (!_systemSupported) {
                  return _buildSliderRow(
                    context: context,
                    colorScheme: colorScheme,
                    icon: appVolume == 0
                        ? Icons.volume_off_rounded
                        : appVolume < 0.5
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                    label: '应用',
                    value: appVolume,
                    onChanged: (v) => _player.setVolume(v),
                  );
                }

                return Column(
                  children: [
                    _buildSliderRow(
                      context: context,
                      colorScheme: colorScheme,
                      icon: Icons.speaker_rounded,
                      label: '系统',
                      value: _systemVolume,
                      onChanged: (v) {
                        setState(() => _systemVolume = v);
                        _systemService.setVolume(v);
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildSliderRow(
                      context: context,
                      colorScheme: colorScheme,
                      icon: Icons.music_note_rounded,
                      label: '应用',
                      value: appVolume,
                      onChanged: (v) => _player.setVolume(v),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
