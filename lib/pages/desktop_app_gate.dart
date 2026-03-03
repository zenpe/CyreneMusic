import 'package:flutter/material.dart';
import '../features/audio_source/audio_source_feature.dart';
import '../layouts/fluent_main_layout.dart';
import '../layouts/navidrome_main_layout.dart';
import '../pages/navidrome_setup_page.dart';
import 'desktop_setup_page.dart';

/// 桌面端应用入口控制器
/// 
/// 根据音源配置和协议确认状态决定显示引导页还是主布局。
/// 使用内部状态管理避免重建 Navigator。
class DesktopAppGate extends StatefulWidget {
  const DesktopAppGate({super.key});

  @override
  State<DesktopAppGate> createState() => _DesktopAppGateState();
}

class _DesktopAppGateState extends State<DesktopAppGate> {
  final AudioSourceFacade _audioSourceFacade = AudioSourceFacade();

  Widget _buildHomeByRoute(AppGateRoute route) {
    return switch (route) {
      AppGateRoute.navidromeMain => const NavidromeMainLayout(),
      AppGateRoute.navidromeSetup => const NavidromeSetupPage(),
      AppGateRoute.regularMain => const FluentMainLayout(),
      AppGateRoute.regularSetup => const DesktopSetupPage(),
    };
  }

  @override
  void initState() {
    super.initState();
    _audioSourceFacade.addEntryStateListener(_onStateChanged);
  }

  @override
  void dispose() {
    _audioSourceFacade.removeEntryStateListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = _audioSourceFacade.resolveEntryRoute();
    return _buildHomeByRoute(route);
  }
}

