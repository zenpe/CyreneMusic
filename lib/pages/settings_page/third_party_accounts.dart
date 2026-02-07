import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../services/auth_service.dart';
import '../../services/netease_login_service.dart';
import '../../services/kugou_login_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';


/// 第三方账号管理入口组件（显示在主设置页面）
class ThirdPartyAccounts extends StatefulWidget {
  final VoidCallback? onTap;
  
  const ThirdPartyAccounts({super.key, this.onTap});

  @override
  State<ThirdPartyAccounts> createState() => _ThirdPartyAccountsState();
}

class _ThirdPartyAccountsState extends State<ThirdPartyAccounts> {
  int _boundCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    AuthService().addListener(_onAuthChanged);
    // 监听第三方登录服务的状态变化
    NeteaseLoginService().addListener(_onBindingChanged);
    KugouLoginService().addListener(_onBindingChanged);
    _loadBindingStatus();
  }

  @override
  void dispose() {
    AuthService().removeListener(_onAuthChanged);
    NeteaseLoginService().removeListener(_onBindingChanged);
    KugouLoginService().removeListener(_onBindingChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    _loadBindingStatus();
  }

  /// 当第三方账号绑定状态变化时刷新绑定数量
  void _onBindingChanged() {
    if (!mounted) return;
    _loadBindingStatus();
  }

  Future<void> _loadBindingStatus() async {
    if (!AuthService().isLoggedIn) {
      if (mounted) {
        setState(() {
          _boundCount = 0;
          _isLoading = false;
        });
      }
      return;
    }

    try {
      int count = 0;
      
      // 检查网易云绑定状态
      final neteaseResp = await NeteaseLoginService().fetchBindings();
      final neteaseData = neteaseResp['data'] as Map<String, dynamic>?;
      final netease = neteaseData?['netease'] as Map<String, dynamic>?;
      if (netease != null && netease['bound'] == true) {
        count++;
      }
      
      // 检查酷狗绑定状态
      final kugouResp = await KugouLoginService().fetchBindings();
      final kugouData = kugouResp['data'] as Map<String, dynamic>?;
      final kugou = kugouData?['kugou'] as Map<String, dynamic>?;
      if (kugou != null && kugou['bound'] == true) {
        count++;
      }
      
      if (mounted) {
        setState(() {
          _boundCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    
    // 如果未登录，不显示此组件
    if (user == null) {
      return const SizedBox.shrink();
    }
    
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertinoUI = ThemeManager().isCupertinoFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    if (isCupertinoUI) {
      return _buildCupertinoUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// 构建 Cupertino UI 版本 - 入口卡片
  Widget _buildCupertinoUI(BuildContext context) {
    return CupertinoSettingsCard(
      icon: CupertinoIcons.person_2_fill,
      iconColor: ThemeManager.iosBlue,
      title: '第三方账号管理',
      subtitle: _getSubtitle(),
      onTap: widget.onTap,
    );
  }

  /// 构建 Material UI 版本 - 入口卡片
  Widget _buildMaterialUI(BuildContext context) {
    return MD3SettingsSection(
      children: [
        MD3SettingsTile(
          leading: const Icon(Icons.link),
          title: '第三方账号管理',
          subtitle: _getSubtitle(),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onTap,
        ),
      ],
    );
  }

  /// 构建 Fluent UI 版本 - 入口卡片
  Widget _buildFluentUI(BuildContext context) {
    return FluentSettingsGroup(
      title: '第三方账号',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.link,
          title: '第三方账号管理',
          subtitle: _getSubtitle(),
          trailing: const Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
          onTap: widget.onTap,
        ),
      ],
    );
  }

  String _getSubtitle() {
    if (_isLoading) {
      return '加载中...';
    }
    if (_boundCount == 0) {
      return '未绑定任何账号';
    }
    return '已绑定 $_boundCount 个账号';
  }
}

