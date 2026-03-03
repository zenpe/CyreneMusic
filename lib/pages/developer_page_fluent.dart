part of 'developer_page.dart';

extension _DeveloperPageFluent on _DeveloperPageState {
  Widget _buildFluentPage(BuildContext context) {
    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: const Text('开发者模式'),
        commandBar: fluent.CommandBar(
          primaryItems: [
            fluent.CommandBarButton(
              icon: const Icon(fluent.FluentIcons.power_button),
              label: const Text('退出开发者模式'),
              onPressed: () {
                _showFluentExitDialog();
              },
            ),
          ],
        ),
      ),
      content: fluent.TabView(
        currentIndex: _fluentTabIndex,
        onChanged: (index) => setState(() => _fluentTabIndex = index),
        tabs: [
          fluent.Tab(
            text: const Text('日志'),
            icon: const Icon(fluent.FluentIcons.error),
            body: _buildFluentLogTab(),
          ),
          fluent.Tab(
            text: const Text('数据'),
            icon: const Icon(fluent.FluentIcons.database),
            body: _buildFluentDataTab(),
          ),
          fluent.Tab(
            text: const Text('设置'),
            icon: const Icon(fluent.FluentIcons.settings),
            body: _buildFluentSettingsTab(),
          ),
        ],
      ),
    );
  }

  void _showFluentExitDialog() {
    showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('退出开发者模式'),
        content: const Text('确定要退出开发者模式吗？'),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () {
              DeveloperModeService().disableDeveloperMode();
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentLogTab() {
    return AnimatedBuilder(
      animation: DeveloperModeService(),
      builder: (context, child) {
        final logs = DeveloperModeService().logs;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: fluent.CommandBar(
                primaryItems: [
                  fluent.CommandBarButton(
                    icon: const Icon(fluent.FluentIcons.copy),
                    label: const Text('复制全部'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: logs.join('\n')));
                      _showFluentSnackbar('已复制到剪贴板');
                    },
                  ),
                  fluent.CommandBarButton(
                    icon: const Icon(fluent.FluentIcons.delete),
                    label: const Text('清除日志'),
                    onPressed: () {
                      DeveloperModeService().clearLogs();
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: logs.isEmpty
                  ? const Center(child: Text('暂无日志'))
                  : ListView.builder(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(8),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: SelectableText(
                            log,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
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

  void _showFluentSnackbar(String message) {
    fluent.displayInfoBar(
      context,
      builder: (context, close) {
        return fluent.InfoBar(
          title: Text(message),
          onClose: close,
        );
      },
    );
  }

  Widget _buildFluentDataTab() {
    return AnimatedBuilder(
      animation: AdminService(),
      builder: (context, child) {
        if (!AdminService().isAuthenticated) {
          return _buildFluentAdminLogin();
        } else {
          return _buildFluentAdminPanel();
        }
      },
    );
  }

  Widget _buildFluentAdminLogin() {
    final passwordController = TextEditingController();
    bool obscurePassword = true;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: StatefulBuilder(
            builder: (context, setState) {
              return fluent.Card(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      fluent.FluentIcons.shield,
                      size: 60,
                      color: fluent.FluentTheme.of(context).accentColor,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '管理员后台',
                      style: fluent.FluentTheme.of(context).typography.title,
                    ),
                    const SizedBox(height: 8),
                    const Text('需要验证管理员身份'),
                    const SizedBox(height: 32),
                    fluent.TextBox(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      placeholder: '管理员密码',
                      suffix: fluent.IconButton(
                        icon: Icon(
                          obscurePassword
                              ? fluent.FluentIcons.view
                              : fluent.FluentIcons.hide,
                        ),
                        onPressed: () {
                          setState(() => obscurePassword = !obscurePassword);
                        },
                      ),
                      onSubmitted: (_) async {
                        await _handleAdminLogin(passwordController.text);
                        passwordController.clear();
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: fluent.FilledButton(
                        onPressed: AdminService().isLoading
                            ? null
                            : () async {
                                await _handleAdminLogin(passwordController.text);
                                passwordController.clear();
                              },
                        child: AdminService().isLoading
                            ? const fluent.ProgressRing(strokeWidth: 2.5)
                            : const Text('登录'),
                      ),
                    ),
                    if (AdminService().errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        AdminService().errorMessage!,
                        style: TextStyle(
                          color: fluent.Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFluentAdminPanel() {
    final adminTabIndex = _fluentAdminTabIndex > 1 ? 1 : _fluentAdminTabIndex;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: fluent.CommandBar(
            primaryItems: [
              fluent.CommandBarButton(
                icon: const Icon(fluent.FluentIcons.refresh),
                label: const Text('刷新'),
                onPressed: AdminService().isLoading ? null : () async {
                  try {
                    await AdminService().fetchUsers();
                    await AdminService().fetchStats();
                  } catch (e) {
                    if (mounted) _showFluentSnackbar('刷新失败: $e');
                  }
                },
              ),
              fluent.CommandBarButton(
                icon: const Icon(fluent.FluentIcons.sign_out),
                label: const Text('退出'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => fluent.ContentDialog(
                      title: const Text('退出管理员'),
                      content: const Text('确定要退出管理员后台吗？'),
                      actions: [
                        fluent.Button(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        fluent.FilledButton(
                          onPressed: () {
                            AdminService().logout();
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
        ),
        Expanded(
          child: fluent.TabView(
            currentIndex: adminTabIndex,
            onChanged: (index) => setState(() => _fluentAdminTabIndex = index),
            tabs: [
              fluent.Tab(
                text: const Text('用户列表'),
                icon: const Icon(fluent.FluentIcons.people),
                body: _buildFluentUsersTab(),
              ),
              fluent.Tab(
                text: const Text('统计数据'),
                icon: const Icon(fluent.FluentIcons.chart),
                body: _buildFluentStatsTab(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFluentUsersTab() {
    if (AdminService().isLoading && AdminService().users.isEmpty) {
      return const Center(child: fluent.ProgressRing());
    }

    if (AdminService().errorMessage != null &&
        AdminService().errorMessage!.contains('令牌验证失败')) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.hasBoundedHeight && constraints.maxHeight < 220;
          final minHeight = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        fluent.FluentIcons.error,
                        size: compact ? 40 : 48,
                        color: fluent.Colors.red,
                      ),
                      SizedBox(height: compact ? 12 : 16),
                      const Text('数据加载失败'),
                      const SizedBox(height: 8),
                      Text(
                        AdminService().errorMessage!,
                        textAlign: TextAlign.center,
                        maxLines: compact ? 3 : 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: compact ? 16 : 24),
                      fluent.Button(
                        onPressed: () {
                          AdminService().logout();
                        },
                        child: const Text('重新登录'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (AdminService().users.isEmpty) {
      return const Center(child: Text('暂无用户数据'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: AdminService().users.length,
      itemBuilder: (context, index) {
        final user = AdminService().users[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: fluent.Expander(
            header: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: user.avatarUrl != null
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(user.username[0].toUpperCase())
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(user.email, style: fluent.FluentTheme.of(context).typography.caption),
                  ],
                ),
                const Spacer(),
                if (user.isVerified)
                  Icon(fluent.FluentIcons.verified_brand, color: fluent.Colors.green, size: 16),
              ],
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUserInfoRow('用户ID', user.id.toString()),
                _buildUserInfoRow('注册时间', _formatDateTime(user.createdAt)),
                _buildUserInfoRow('最后登录', _formatDateTime(user.lastLogin)),
                _buildUserInfoRow('IP地址', user.lastIp ?? '未知'),
                _buildUserInfoRow('IP归属地', user.lastIpLocation ?? '未知'),
                _buildUserInfoRow('IP更新时间', _formatDateTime(user.lastIpUpdatedAt)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    fluent.Button(
                      style: fluent.ButtonStyle(
                        foregroundColor: WidgetStatePropertyAll(fluent.Colors.red),
                      ),
                      onPressed: () => _confirmFluentDeleteUser(user),
                      child: const Text('删除用户'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmFluentDeleteUser(user) {
    showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('删除用户'),
        content: Text('确定要删除用户 "${user.username}" 吗？\n\n此操作无法撤销！'),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            style: fluent.ButtonStyle(
              backgroundColor: WidgetStatePropertyAll(fluent.Colors.red),
            ),
            onPressed: () async {
              Navigator.pop(context);
              final success = await AdminService().deleteUser(user.id);
              if (mounted) {
                _showFluentSnackbar(success ? '用户已删除' : '删除失败');
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentStatsTab() {
    if (AdminService().isLoading && AdminService().stats == null) {
      return const Center(child: fluent.ProgressRing());
    }

    final stats = AdminService().stats;
    if (stats == null) {
      return const Center(child: Text('暂无统计数据'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        fluent.Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('用户概览', style: fluent.FluentTheme.of(context).typography.subtitle),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFluentStatCard('总用户', stats.totalUsers.toString(), fluent.FluentIcons.people),
                  _buildFluentStatCard('已验证', stats.verifiedUsers.toString(), fluent.FluentIcons.verified_brand),
                  _buildFluentStatCard('未验证', stats.unverifiedUsers.toString(), fluent.FluentIcons.unknown),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildFluentStatCard('今日新增', stats.todayUsers.toString(), fluent.FluentIcons.add_friend),
                  _buildFluentStatCard('今日活跃', stats.todayActiveUsers.toString(), fluent.FluentIcons.trending12),
                  _buildFluentStatCard('本周新增', stats.last7DaysUsers.toString(), fluent.FluentIcons.calendar),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (stats.topLocations.isNotEmpty) ...[
          fluent.Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('地区分布 Top 10', style: fluent.FluentTheme.of(context).typography.subtitle),
                const SizedBox(height: 16),
                ...stats.topLocations.map((loc) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(loc.location)),
                      Expanded(
                        flex: 7,
                        child: fluent.ProgressBar(
                          value: (loc.count / stats.totalUsers) * 100,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${loc.count} 人'),
                    ],
                  ),
                )),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFluentStatCard(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 24, color: fluent.FluentTheme.of(context).accentColor),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        Text(label, style: fluent.FluentTheme.of(context).typography.caption),
      ],
    );
  }

  Widget _buildFluentSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        fluent.Card(
          child: fluent.ListTile(
            leading: const Icon(fluent.FluentIcons.info),
            title: const Text('版本信息'),
            subtitle: const Text('Cyrene Music v1.0.0'),
          ),
        ),
        const SizedBox(height: 8),
        fluent.Card(
          child: fluent.ListTile(
            leading: const Icon(fluent.FluentIcons.code),
            title: const Text('Flutter 版本'),
            subtitle: const Text('3.32.7'),
          ),
        ),
        const SizedBox(height: 8),
        fluent.Card(
          child: fluent.ListTile(
            leading: const Icon(fluent.FluentIcons.cell_phone),
            title: const Text('平台'),
            subtitle: Text(_getPlatformName()),
          ),
        ),
        const SizedBox(height: 8),
        fluent.Card(
          child: fluent.ListTile(
            leading: const Icon(fluent.FluentIcons.merge),
            title: const Text('合并搜索结果'),
            subtitle: const Text('关闭后将分平台显示搜索结果（网易云/QQ/酷狗/酷我）'),
            trailing: fluent.ToggleSwitch(
              checked: DeveloperModeService().isSearchResultMergeEnabled,
              onChanged: (value) {
                setState(() {
                  DeveloperModeService().toggleSearchResultMerge(value);
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        fluent.Card(
          child: fluent.ListTile(
            leading: const Icon(fluent.FluentIcons.line_chart),
            title: const Text('性能叠加层'),
            subtitle: const Text('开启后在界面顶部显示帧率和渲染监控曲线'),
            trailing: fluent.ToggleSwitch(
              checked: DeveloperModeService().showPerformanceOverlay,
              onChanged: (value) {
                setState(() {
                  DeveloperModeService().togglePerformanceOverlay(value);
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        fluent.FilledButton(
          onPressed: () {
            DeveloperModeService().addLog('📋 触发测试日志');
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.bug),
              SizedBox(width: 8),
              Text('添加测试日志'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        fluent.FilledButton(
          onPressed: () async {
            await NotificationService().showNotification(
              id: 999,
              title: '测试通知',
              body: '这是一条来自开发者模式的测试通知',
            );
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.ringer),
              SizedBox(width: 8),
              Text('发送测试通知'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        fluent.FilledButton(
          onPressed: () async {
            await _testPlaybackResumeNotification();
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.play),
              SizedBox(width: 8),
              Text('测试播放恢复通知'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        fluent.FilledButton(
          style: fluent.ButtonStyle(
            backgroundColor: fluent.WidgetStateProperty.all(fluent.Colors.red),
          ),
          onPressed: () async {
            await _clearPlaybackSession();
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.delete),
              SizedBox(width: 8),
              Text('清除播放状态'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          '音源测试',
          style: fluent.FluentTheme.of(context).typography.bodyStrong?.copyWith(
            color: fluent.FluentTheme.of(context).accentColor,
          ),
        ),
        const SizedBox(height: 8),
        fluent.FilledButton(
          style: fluent.ButtonStyle(
            backgroundColor: fluent.WidgetStateProperty.all(fluent.Colors.teal),
          ),
          onPressed: () {
            Navigator.push(
              context,
              fluent.FluentPageRoute(
                builder: (context) => const LxMusicRuntimeTestPage(),
              ),
            );
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.test_beaker),
              SizedBox(width: 8),
              Text('洛雪音源运行时测试'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'WSA 专用',
          style: fluent.FluentTheme.of(context).typography.bodyStrong?.copyWith(
            color: fluent.FluentTheme.of(context).accentColor,
          ),
        ),
        const SizedBox(height: 8),
        fluent.FilledButton(
          style: fluent.ButtonStyle(
            backgroundColor: fluent.WidgetStateProperty.all(fluent.Colors.purple),
          ),
          onPressed: () => _showFluentQuickLoginDialog(),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(fluent.FluentIcons.signin),
              SizedBox(width: 8),
              Text('快速登录'),
            ],
          ),
        ),
      ],
    );
  }

  /// 显示 Fluent UI 版本的快速登录对话框
  void _showFluentQuickLoginDialog() {
    final accountController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return fluent.ContentDialog(
            title: Row(
              children: [
                Icon(fluent.FluentIcons.signin, color: fluent.FluentTheme.of(context).accentColor),
                const SizedBox(width: 8),
                const Text('快速登录'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('直接输入账号密码登录（用于 WSA 等环境）'),
                const SizedBox(height: 16),
                fluent.TextBox(
                  controller: accountController,
                  enabled: !isLoading,
                  placeholder: '邮箱 / 用户名',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(fluent.FluentIcons.contact, size: 16),
                  ),
                ),
                const SizedBox(height: 12),
                fluent.TextBox(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  enabled: !isLoading,
                  placeholder: '密码',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(fluent.FluentIcons.lock, size: 16),
                  ),
                  suffix: fluent.IconButton(
                    icon: Icon(
                      obscurePassword
                          ? fluent.FluentIcons.view
                          : fluent.FluentIcons.hide3,
                      size: 16,
                    ),
                    onPressed: () {
                      setState(() => obscurePassword = !obscurePassword);
                    },
                  ),
                  onSubmitted: isLoading ? null : (_) async {
                    setState(() => isLoading = true);
                    await _performQuickLogin(accountController.text, passwordController.text, context);
                  },
                ),
              ],
            ),
            actions: [
              fluent.Button(
                onPressed: isLoading ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              fluent.FilledButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() => isLoading = true);
                        await _performQuickLogin(accountController.text, passwordController.text, context);
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: fluent.ProgressRing(strokeWidth: 2),
                      )
                    : const Text('登录'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getPlatformName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (kIsWeb) return 'Web';
    return 'Unknown';
  }
}

