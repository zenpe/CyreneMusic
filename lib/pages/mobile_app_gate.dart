import 'dart:io';
import 'package:flutter/material.dart';
import '../layouts/navidrome_main_layout.dart';
import '../services/audio_source_service.dart';
import '../services/auth_service.dart';
import '../services/navidrome_session_service.dart';
import '../services/persistent_storage_service.dart';
import '../layouts/main_layout.dart';
import 'navidrome_setup_page.dart';
import 'mobile_setup_page.dart';

/// 移动端应用入口控制器
/// 
/// 根据音源配置和登录状态决定显示引导页还是主布局。
/// 使用内部状态管理避免重建 Navigator。
class MobileAppGate extends StatefulWidget {
  const MobileAppGate({super.key});

  @override
  State<MobileAppGate> createState() => _MobileAppGateState();
}

class _MobileAppGateState extends State<MobileAppGate> {
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

    if (isNavidromeActive) {
      if (isConfigured && isTermsAccepted) {
        return const NavidromeMainLayout();
      }
      return const NavidromeSetupPage();
    }

    // 音源配置、登录以及协议确认都完成后，显示主布局
    if (isConfigured && isLoggedIn && isTermsAccepted) {
      return const MainLayout();
    }

    // 否则显示引导页
    return const MobileSetupPage();
  }
}
