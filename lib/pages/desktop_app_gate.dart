import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../layouts/fluent_main_layout.dart';
import '../layouts/navidrome_main_layout.dart';
import '../pages/navidrome_setup_page.dart';
import '../services/audio_source_service.dart';
import '../services/auth_service.dart';
import '../services/navidrome_session_service.dart';
import '../services/persistent_storage_service.dart';
import 'desktop_setup_page.dart';

/// 桌面端应用入口控制器
/// 
/// 根据音源配置、登录状态和协议确认状态决定显示引导页还是主布局。
/// 使用内部状态管理避免重建 Navigator。
class DesktopAppGate extends StatefulWidget {
  const DesktopAppGate({super.key});

  @override
  State<DesktopAppGate> createState() => _DesktopAppGateState();
}

class _DesktopAppGateState extends State<DesktopAppGate> {
  @override
  void initState() {
    super.initState();
    AudioSourceService().addListener(_onStateChanged);
    AuthService().addListener(_onStateChanged);
    NavidromeSessionService().addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AudioSourceService().removeListener(_onStateChanged);
    AuthService().removeListener(_onStateChanged);
    NavidromeSessionService().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioSourceService = AudioSourceService();
    final isConfigured = audioSourceService.isConfigured;
    final isNavidromeActive = audioSourceService.isNavidromeActive;
    final isLoggedIn = AuthService().isLoggedIn;
    final isTermsAccepted = PersistentStorageService().getBool('terms_accepted') ?? false;
    final isLocalMode = PersistentStorageService().enableLocalMode;

    if (isNavidromeActive) {
      if (isConfigured && isTermsAccepted) {
        return const NavidromeMainLayout();
      }
      return const NavidromeSetupPage();
    }

    // 音源配置、登录以及协议确认都完成后，显示主布局；或者开启了本地模式且已确认协议
    if ((isConfigured && isLoggedIn && isTermsAccepted) || (isLocalMode && isTermsAccepted)) {
      return const FluentMainLayout();
    }

    // 否则显示引导页
    return const DesktopSetupPage();
  }
}

