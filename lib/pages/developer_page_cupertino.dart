part of 'developer_page.dart';

extension _DeveloperPageCupertino on _DeveloperPageState {
  Widget _buildCupertinoPage(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 底部 Tab 栏高度（悬浮 Tab 栏约 60 + 底部安全区）
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;

    return Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('开发者模式'),
          backgroundColor: (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white).withOpacity(0.9),
          border: null,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            child: const Icon(CupertinoIcons.power),
            onPressed: () => _showCupertinoExitDialog(context, isDark),
          ),
        ),
        child: SafeArea(
          bottom: false, // 不使用 SafeArea 的底部，手动处理
          child: Column(
            children: [
              // 分段控制器
              Padding(
                padding: const EdgeInsets.all(16),
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _cupertinoTabIndex,
                  onValueChanged: (value) {
                    if (value != null) {
                      setState(() => _cupertinoTabIndex = value);
                    }
                  },
                  children: const {
                    0: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('日志'),
                    ),
                    1: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('数据'),
                    ),
                    2: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('设置'),
                    ),
                  },
                ),
              ),
              // 内容区域（底部留出 Tab 栏空间）
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _buildCupertinoTabContent(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建 Cupertino 标签页内容
  Widget _buildCupertinoTabContent(bool isDark) {
    switch (_cupertinoTabIndex) {
      case 0:
        return _buildCupertinoLogTab(isDark);
      case 1:
        return _buildCupertinoDataTab(isDark);
      case 2:
        return _buildCupertinoSettingsTab(isDark);
      default:
        return _buildCupertinoLogTab(isDark);
    }
  }

  /// 显示 Cupertino 退出对话框
  void _showCupertinoExitDialog(BuildContext context, bool isDark) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('退出开发者模式'),
        content: const Text('确定要退出开发者模式吗？'),
        actions: [
          CupertinoDialogAction(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('确定'),
            onPressed: () {
              DeveloperModeService().disableDeveloperMode();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  /// 构建 Cupertino 日志标签页
  Widget _buildCupertinoLogTab(bool isDark) {
    return AnimatedBuilder(
      animation: DeveloperModeService(),
      builder: (context, child) {
        final logs = DeveloperModeService().logs;

        return Column(
          children: [
            // 工具栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '共 ${logs.length} 条日志',
                    style: TextStyle(
                      color: CupertinoColors.systemGrey,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.doc_on_clipboard, size: 22),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      _showCupertinoToast('已复制到剪贴板');
                    },
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Icon(CupertinoIcons.trash, size: 22),
                    onPressed: () => DeveloperModeService().clearLogs(),
                  ),
                ],
              ),
            ),
            // 日志列表
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('暂无日志', style: TextStyle(color: CupertinoColors.systemGrey)))
                  : ListView.builder(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            log,
                            style: TextStyle(
                              fontFamily: 'Menlo',
                              fontSize: 12,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 构建 Cupertino 数据标签页
  Widget _buildCupertinoDataTab(bool isDark) {
    return AnimatedBuilder(
      animation: AdminService(),
      builder: (context, child) {
        if (!AdminService().isAuthenticated) {
          return _buildCupertinoAdminLogin(isDark);
        } else {
          return _buildCupertinoAdminPanel(isDark);
        }
      },
    );
  }

  /// 构建 Cupertino 管理员登录
  Widget _buildCupertinoAdminLogin(bool isDark) {
    final passwordController = TextEditingController();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.shield_lefthalf_fill,
              size: 80,
              color: CupertinoColors.activeBlue,
            ),
            const SizedBox(height: 24),
            const Text(
              '管理员后台',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '需要验证管理员身份',
              style: TextStyle(color: CupertinoColors.systemGrey),
            ),
            const SizedBox(height: 48),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CupertinoTextField(
                controller: passwordController,
                obscureText: true,
                placeholder: '管理员密码',
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                prefix: const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(CupertinoIcons.lock_fill, color: CupertinoColors.systemGrey, size: 20),
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                onSubmitted: (_) async {
                  await _handleAdminLogin(passwordController.text);
                  passwordController.clear();
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: AdminService().isLoading
                    ? null
                    : () async {
                        await _handleAdminLogin(passwordController.text);
                        passwordController.clear();
                      },
                child: AdminService().isLoading
                    ? const CupertinoActivityIndicator(color: CupertinoColors.white)
                    : const Text('登录'),
              ),
            ),
            if (AdminService().errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                AdminService().errorMessage!,
                style: const TextStyle(color: CupertinoColors.destructiveRed),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建 Cupertino 管理员面板（简化版，显示用户列表）
  Widget _buildCupertinoAdminPanel(bool isDark) {
    return Column(
      children: [
        // 工具栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: const Icon(CupertinoIcons.refresh, size: 22),
                onPressed: AdminService().isLoading
                    ? null
                    : () async {
                        await AdminService().fetchUsers();
                        await AdminService().fetchStats();
                      },
              ),
              const Spacer(),
              CupertinoButton(
                padding: EdgeInsets.zero,
                child: Row(
                  children: [
                    const Icon(CupertinoIcons.square_arrow_right, size: 18),
                    const SizedBox(width: 4),
                    const Text('退出'),
                  ],
                ),
                onPressed: () {
                  showCupertinoDialog(
                    context: context,
                    builder: (context) => CupertinoAlertDialog(
                      title: const Text('退出管理员'),
                      content: const Text('确定要退出管理员后台吗？'),
                      actions: [
                        CupertinoDialogAction(
                          child: const Text('取消'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          child: const Text('确定'),
                          onPressed: () {
                            AdminService().logout();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        // 用户列表
        Expanded(
          child: AdminService().isLoading && AdminService().users.isEmpty
              ? const Center(child: CupertinoActivityIndicator())
              : AdminService().users.isEmpty
                  ? const Center(child: Text('暂无用户数据', style: TextStyle(color: CupertinoColors.systemGrey)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: AdminService().users.length,
                      itemBuilder: (context, index) {
                        final user = AdminService().users[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: CupertinoListTile(
                            leading: CircleAvatar(
                              backgroundImage: user.avatarUrl != null
                                  ? NetworkImage(user.avatarUrl!)
                                  : null,
                              child: user.avatarUrl == null
                                  ? Text(user.username[0].toUpperCase())
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Text(user.username),
                                if (user.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(CupertinoIcons.checkmark_seal_fill,
                                    color: CupertinoColors.activeGreen, size: 14),
                                ],
                              ],
                            ),
                            subtitle: Text(user.email),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// 构建 Cupertino 设置标签页
  Widget _buildCupertinoSettingsTab(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 版本信息
        _buildCupertinoSettingsCard(
          isDark: isDark,
          icon: CupertinoIcons.info_circle_fill,
          title: '版本信息',
          subtitle: 'Cyrene Music v1.0.0',
        ),
        const SizedBox(height: 8),
        _buildCupertinoSettingsCard(
          isDark: isDark,
          icon: CupertinoIcons.chevron_left_slash_chevron_right,
          title: 'Flutter 版本',
          subtitle: '3.32.7',
        ),
        const SizedBox(height: 8),
        _buildCupertinoSettingsCard(
          isDark: isDark,
          icon: CupertinoIcons.device_phone_portrait,
          title: '平台',
          subtitle: _getPlatformName(),
        ),
        const SizedBox(height: 8),
        // 合并搜索结果开关
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CupertinoListTile(
            leading: const Icon(CupertinoIcons.arrow_merge, color: CupertinoColors.activeBlue),
            title: const Text('合并搜索结果'),
            subtitle: const Text('关闭后将分平台显示'),
            trailing: CupertinoSwitch(
              value: DeveloperModeService().isSearchResultMergeEnabled,
              onChanged: (value) {
                setState(() {
                  DeveloperModeService().toggleSearchResultMerge(value);
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        // 性能叠加层开关
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: CupertinoListTile(
            leading: const Icon(CupertinoIcons.graph_square, color: CupertinoColors.activeBlue),
            title: const Text('性能叠加层'),
            subtitle: const Text('显示帧率和渲染监控曲线'),
            trailing: CupertinoSwitch(
              value: DeveloperModeService().showPerformanceOverlay,
              onChanged: (value) {
                setState(() {
                  DeveloperModeService().togglePerformanceOverlay(value);
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 测试按钮
        _buildCupertinoButton(
          label: '发送测试通知',
          icon: CupertinoIcons.bell_fill,
          onPressed: () async {
            await NotificationService().showNotification(
              id: 999,
              title: '测试通知',
              body: '这是一条来自开发者模式的测试通知',
            );
          },
        ),
        const SizedBox(height: 8),
        _buildCupertinoButton(
          label: '测试播放恢复通知',
          icon: CupertinoIcons.play_circle_fill,
          onPressed: () async {
            await _testPlaybackResumeNotification();
          },
        ),
        const SizedBox(height: 8),
        _buildCupertinoButton(
          label: '清除播放状态',
          icon: CupertinoIcons.trash_fill,
          color: CupertinoColors.systemOrange,
          onPressed: () async {
            await _clearPlaybackSession();
          },
        ),
        const SizedBox(height: 16),
        // WSA 专用
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'WSA 专用',
            style: TextStyle(
              color: CupertinoColors.activeBlue,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _buildCupertinoButton(
          label: '快速登录',
          icon: CupertinoIcons.person_crop_circle_badge_checkmark,
          color: CupertinoColors.systemPurple,
          onPressed: () => _showCupertinoQuickLoginDialog(isDark),
        ),
      ],
    );
  }

  /// 构建 Cupertino 设置卡片
  Widget _buildCupertinoSettingsCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: CupertinoListTile(
        leading: Icon(icon, color: CupertinoColors.activeBlue),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  /// 构建 Cupertino 按钮
  Widget _buildCupertinoButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        color: color ?? CupertinoColors.activeBlue,
        padding: const EdgeInsets.symmetric(vertical: 14),
        borderRadius: BorderRadius.circular(10),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: CupertinoColors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: CupertinoColors.white)),
          ],
        ),
      ),
    );
  }

  /// 显示 Cupertino 快速登录对话框
  void _showCupertinoQuickLoginDialog(bool isDark) {
    final accountController = TextEditingController();
    final passwordController = TextEditingController();

    showCupertinoModalPopup(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemGroupedBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 拖动指示器
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey3,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '快速登录',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '直接输入账号密码登录（用于 WSA 等环境）',
                    style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // 账号输入框
                  CupertinoTextField(
                    controller: accountController,
                    placeholder: '邮箱 / 用户名',
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(CupertinoIcons.person_fill, color: CupertinoColors.systemGrey, size: 20),
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 密码输入框
                  CupertinoTextField(
                    controller: passwordController,
                    placeholder: '密码',
                    obscureText: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(CupertinoIcons.lock_fill, color: CupertinoColors.systemGrey, size: 20),
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 登录按钮
                  CupertinoButton.filled(
                    onPressed: () async {
                      if (accountController.text.trim().isEmpty || passwordController.text.isEmpty) {
                        _showCupertinoToast('请输入账号和密码');
                        return;
                      }

                      Navigator.pop(context);

                      final result = await AuthService().login(
                        account: accountController.text.trim(),
                        password: passwordController.text,
                      );

                      if (result['success']) {
                        _showCupertinoToast('✅ 登录成功', isSuccess: true);
                        AuthService().updateLocation();
                      } else {
                        _showCupertinoToast('登录失败: ${result['message']}');
                      }
                    },
                    child: const Text('登录'),
                  ),
                  const SizedBox(height: 12),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 显示 Cupertino Toast
  void _showCupertinoToast(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? CupertinoColors.activeGreen : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
