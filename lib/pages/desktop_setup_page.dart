import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../features/audio_source/audio_source_feature.dart';
import '../utils/theme_manager.dart';
import '../widgets/terms_consent.dart';
import 'settings_page/audio_source_settings_page.dart';
import 'auth/fluent_auth_page.dart';

class DesktopSetupPage extends StatefulWidget {
  const DesktopSetupPage({super.key});
  @override
  State<DesktopSetupPage> createState() => _DesktopSetupPageState();
}

class _DesktopSetupPageState extends State<DesktopSetupPage>
    with WindowListener {
  bool _isWindowMaximized = false;
  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((value) {
        if (mounted) setState(() => _isWindowMaximized = value);
      });
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isWindowMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isWindowMaximized = false);
  }

  // 窗口控制方法
  void _handleCaptionMinimize() {
    if (!Platform.isWindows) return;
    windowManager.minimize();
  }

  void _handleCaptionMaximizeOrRestore() {
    if (!Platform.isWindows) return;
    windowManager.isMaximized().then((isMaximized) {
      if (isMaximized) {
        windowManager.unmaximize();
      } else {
        windowManager.maximize();
      }
      if (mounted) {
        setState(() {
          _isWindowMaximized = !isMaximized;
        });
      }
    });
  }

  void _handleCaptionClose() {
    if (!Platform.isWindows) return;
    windowManager.close();
  }

  /// 构建标题栏（包含拖动区域和窗口控制按钮）
  Widget _buildTitleBar(BuildContext context, fluent.FluentThemeData theme) {
    final brightness = theme.brightness;
    final typography = theme.typography;

    return SizedBox(
      height: 50,
      child: Stack(
        children: [
          // 可拖动区域
          Positioned.fill(
            child: DragToMoveArea(child: Container(color: Colors.transparent)),
          ),
          // 标题（左侧）
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/tray_icon.png',
                    width: 16,
                    height: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Cyrene Music',
                    style:
                        (typography.subtitle ?? typography.bodyLarge)?.copyWith(
                          fontSize: 12,
                        ) ??
                        const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          // 窗口控制按钮（右侧）
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WindowCaptionButton.minimize(
                  brightness: brightness,
                  onPressed: _handleCaptionMinimize,
                ),
                _isWindowMaximized
                    ? WindowCaptionButton.unmaximize(
                        brightness: brightness,
                        onPressed: _handleCaptionMaximizeOrRestore,
                      )
                    : WindowCaptionButton.maximize(
                        brightness: brightness,
                        onPressed: _handleCaptionMaximizeOrRestore,
                      ),
                WindowCaptionButton.close(
                  brightness: brightness,
                  onPressed: _handleCaptionClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final facade = AudioSourceFacade();
    final theme = fluent.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final useWindowEffect =
        Platform.isWindows &&
        ThemeManager().windowEffect != WindowEffect.disabled;
    final Widget content;
    if (!facade.isLoggedIn) {
      content = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: const FluentAuthPage(embedded: true),
        ),
      );
    } else if (!facade.termsAccepted) {
      content = const AgreementConfirmation(fluentStyle: true);
    } else {
      content = const AudioSourceSettingsContent(embed: true);
    }
    return Container(
      color: useWindowEffect
          ? Colors.transparent
          : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF3F3F3)),
      child: Column(
        children: [
          _buildTitleBar(context, theme),
          Expanded(child: content),
        ],
      ),
    );
  }
}
