import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../services/developer_mode_service.dart';
import '../services/music_service.dart';
import '../services/auth_service.dart';
import '../services/admin_service.dart';
import '../services/notification_service.dart';
import '../services/playback_state_service.dart';
import '../services/player_service.dart';
import '../utils/theme_manager.dart';
import 'lx_music_runtime_test_page.dart';

part 'developer_page_material.dart';
part 'developer_page_fluent.dart';
part 'developer_page_cupertino.dart';

/// 开发者页面
class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _logScrollController = ScrollController();
  int _fluentTabIndex = 0;
  int _fluentAdminTabIndex = 0;
  int _cupertinoTabIndex = 0; // iOS 标签页索引

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // 监听日志更新，自动滚动到底部
    DeveloperModeService().addListener(_scrollToBottom);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _logScrollController.dispose();
    DeveloperModeService().removeListener(_scrollToBottom);
    super.dispose();
  }

  void _scrollToBottom() {
    if (_logScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 检查是否启用 Fluent UI 主题
    if (ThemeManager().isDesktopFluentUI) {
      return _buildFluentPage(context);
    }

    // 检查是否启用 Cupertino 主题
    if ((Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework) {
      return _buildCupertinoPage(context);
    }

    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.code, color: colorScheme.primary),
            const SizedBox(width: 8),
            const Text('开发者模式'),
          ],
        ),
        backgroundColor: colorScheme.surface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.bug_report), text: '日志'),
            Tab(icon: Icon(Icons.storage), text: '数据'),
            Tab(icon: Icon(Icons.settings), text: '设置'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            tooltip: '退出开发者模式',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('退出开发者模式'),
                  content: const Text('确定要退出开发者模式吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () {
                        DeveloperModeService().disableDeveloperMode();
                        Navigator.pop(context);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLogTab(),
          _buildDataTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

}
