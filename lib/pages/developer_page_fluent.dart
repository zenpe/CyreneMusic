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
            currentIndex: _fluentAdminTabIndex,
            onChanged: (index) => setState(() => _fluentAdminTabIndex = index),
            tabs: [
              fluent.Tab(
                text: const Text('用户列表'),
                icon: const Icon(fluent.FluentIcons.people),
                body: _buildFluentUsersTab(),
              ),
              fluent.Tab(
                text: const Text('赞助排行'),
                icon: const Icon(fluent.FluentIcons.trophy2),
                body: _buildFluentSponsorRankingTab(),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(fluent.FluentIcons.error, size: 48, color: fluent.Colors.red),
            const SizedBox(height: 16),
            const Text('数据加载失败'),
            const SizedBox(height: 8),
            Text(AdminService().errorMessage!),
            const SizedBox(height: 24),
            fluent.Button(
              onPressed: () {
                AdminService().logout();
              },
              child: const Text('重新登录'),
            ),
          ],
        ),
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
                      onPressed: () => _showFluentSponsorDialog(user),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(fluent.FluentIcons.heart, size: 16, color: Colors.pink),
                          SizedBox(width: 8),
                          Text('赞助管理'),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    fluent.Button(
                      style: fluent.ButtonStyle(
                        foregroundColor: fluent.ButtonState.all(fluent.Colors.red),
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
              backgroundColor: fluent.ButtonState.all(fluent.Colors.red),
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

  /// 显示 Fluent UI 赞助管理对话框
  void _showFluentSponsorDialog(AdminUserData user) async {
    final details = await AdminService().fetchUserSponsorDetails(user.id);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: Row(
          children: [
            const Icon(fluent.FluentIcons.heart, color: Colors.pink),
            const SizedBox(width: 8),
            Text('赞助管理 - ${user.username}'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 赞助状态卡片
                fluent.Card(
                  child: Row(
                    children: [
                      Icon(
                        details?.isSponsor == true ? fluent.FluentIcons.verified_brand : fluent.FluentIcons.cancel,
                        color: details?.isSponsor == true ? fluent.Colors.orange : fluent.Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              details?.isSponsor == true ? '赞助用户' : '非赞助用户',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (details?.sponsorSince != null)
                              Text(
                                '赞助时间: ${_formatDateTime(details!.sponsorSince)}',
                                style: fluent.FluentTheme.of(context).typography.caption,
                              ),
                          ],
                        ),
                      ),
                      fluent.ToggleSwitch(
                        checked: details?.isSponsor ?? false,
                        onChanged: (value) async {
                          final success = await AdminService().updateSponsorStatus(user.id, value);
                          if (success && mounted) {
                            Navigator.pop(context);
                            _showFluentSnackbar(value ? '已设为赞助用户' : '已取消赞助状态');
                            _showFluentSponsorDialog(user);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 累计金额
                _buildUserInfoRow('累计赞助金额', '¥${details?.totalAmount.toStringAsFixed(2) ?? "0.00"}'),
                const SizedBox(height: 16),

                // 赞助记录
                Text(
                  '赞助记录 (${details?.donations.length ?? 0})',
                  style: fluent.FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: 8),
                if (details?.donations.isEmpty ?? true)
                  Text('暂无赞助记录', style: fluent.FluentTheme.of(context).typography.caption)
                else
                  ...details!.donations.map((donation) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: fluent.Card(
                          child: Row(
                            children: [
                              Icon(
                                donation.isPaid ? fluent.FluentIcons.check_mark : fluent.FluentIcons.clock,
                                color: donation.isPaid ? fluent.Colors.green : fluent.Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '¥${donation.amount.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      '${donation.paymentTypeText} · ${donation.statusText}',
                                      style: fluent.FluentTheme.of(context).typography.caption,
                                    ),
                                    Text(
                                      _formatDateTime(donation.paidAt ?? donation.createdAt),
                                      style: fluent.FluentTheme.of(context).typography.caption,
                                    ),
                                  ],
                                ),
                              ),
                              fluent.IconButton(
                                icon: Icon(fluent.FluentIcons.delete, color: fluent.Colors.red, size: 16),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => fluent.ContentDialog(
                                      title: const Text('删除赞助记录'),
                                      content: Text('确定要删除这笔 ¥${donation.amount.toStringAsFixed(2)} 的赞助记录吗？'),
                                      actions: [
                                        fluent.Button(
                                          onPressed: () => Navigator.pop(ctx, false),
                                          child: const Text('取消'),
                                        ),
                                        fluent.FilledButton(
                                          style: fluent.ButtonStyle(
                                            backgroundColor: fluent.ButtonState.all(fluent.Colors.red),
                                          ),
                                          onPressed: () => Navigator.pop(ctx, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    final success = await AdminService().deleteDonation(donation.id);
                                    if (success && mounted) {
                                      Navigator.pop(context);
                                      _showFluentSponsorDialog(user);
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          fluent.FilledButton(
            onPressed: () => _showFluentAddDonationDialog(user),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(fluent.FluentIcons.add, size: 16),
                SizedBox(width: 8),
                Text('添加赞助'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 显示 Fluent UI 添加赞助对话框
  void _showFluentAddDonationDialog(AdminUserData user) {
    final amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String? errorText;
          return fluent.ContentDialog(
            title: Text('为 ${user.username} 添加赞助'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                fluent.TextBox(
                  controller: amountController,
                  placeholder: '赞助金额 (元)',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Text('¥'),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(errorText!, style: TextStyle(color: fluent.Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 8),
                Text(
                  '添加后将自动标记为已支付，并将用户设为赞助用户',
                  style: fluent.FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
            actions: [
              fluent.Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              fluent.FilledButton(
                onPressed: () async {
                  final amountStr = amountController.text.trim();
                  final amount = double.tryParse(amountStr);
                  if (amount == null || amount <= 0) {
                    setDialogState(() => errorText = '请输入有效金额');
                    return;
                  }

                  final success = await AdminService().addManualDonation(user.id, amount);
                  if (mounted) {
                    Navigator.pop(context);
                    Navigator.pop(context);
                    _showFluentSnackbar(success ? '赞助记录已添加' : '添加失败');
                    if (success) {
                      _showFluentSponsorDialog(user);
                    }
                  }
                },
                child: const Text('确认添加'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 构建 Fluent UI 赞助排行榜标签页
  Widget _buildFluentSponsorRankingTab() {
    return FutureBuilder<SponsorRankingData?>(
      future: AdminService().fetchSponsorRanking(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: fluent.ProgressRing());
        }

        final data = snapshot.data;
        if (data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(fluent.FluentIcons.error, size: 48, color: fluent.Colors.grey),
                const SizedBox(height: 16),
                const Text('加载赞助排行榜失败'),
                const SizedBox(height: 16),
                fluent.FilledButton(
                  onPressed: () => setState(() {}),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 汇总卡片
            fluent.Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(fluent.FluentIcons.trophy2, color: fluent.Colors.orange),
                      const SizedBox(width: 8),
                      Text('赞助汇总', style: fluent.FluentTheme.of(context).typography.subtitle),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFluentStatCard('总赞助金额', '¥${data.summary.totalDonations.toStringAsFixed(2)}', fluent.FluentIcons.money),
                      _buildFluentStatCard('赞助用户', data.summary.totalSponsors.toString(), fluent.FluentIcons.verified_brand),
                      _buildFluentStatCard('参与人数', data.summary.totalUsers.toString(), fluent.FluentIcons.people),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 排行榜标题
            Text('赞助排行榜', style: fluent.FluentTheme.of(context).typography.bodyStrong),
            const SizedBox(height: 8),

            if (data.ranking.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('暂无赞助记录', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ...data.ranking.map((item) => _buildFluentRankingItem(item)),
          ],
        );
      },
    );
  }

  /// 构建 Fluent UI 排行榜项
  Widget _buildFluentRankingItem(SponsorRankingItem item) {
    Color? rankColor;
    if (item.rank == 1) {
      rankColor = const Color(0xFFFFD700);
    } else if (item.rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
    } else if (item.rank == 3) {
      rankColor = const Color(0xFFCD7F32);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: fluent.Card(
        child: fluent.ListTile.selectable(
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                child: item.rank <= 3
                    ? Icon(fluent.FluentIcons.trophy2, color: rankColor, size: 24)
                    : Text(
                        '#${item.rank}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 18,
                backgroundImage: item.avatarUrl != null ? NetworkImage(item.avatarUrl!) : null,
                child: item.avatarUrl == null ? Text(item.username[0].toUpperCase()) : null,
              ),
            ],
          ),
          title: Row(
            children: [
              Text(item.username, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (item.isSponsor) ...[
                const SizedBox(width: 4),
                Icon(fluent.FluentIcons.verified_brand, color: fluent.Colors.orange, size: 14),
              ],
            ],
          ),
          subtitle: Text(
            '赞助 ${item.donationCount} 次 · ${_formatDateTime(item.lastDonationAt)}',
            style: fluent.FluentTheme.of(context).typography.caption,
          ),
          trailing: Text(
            '¥${item.totalAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: fluent.Colors.orange,
            ),
          ),
          onPressed: () => _showFluentSponsorDialogFromRanking(item),
        ),
      ),
    );
  }

  /// Fluent UI 从排行榜打开赞助详情
  void _showFluentSponsorDialogFromRanking(SponsorRankingItem item) async {
    final details = await AdminService().fetchUserSponsorDetails(item.userId);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: Row(
          children: [
            const Icon(fluent.FluentIcons.heart, color: Colors.pink),
            const SizedBox(width: 8),
            Expanded(child: Text('赞助详情 - ${item.username}')),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户信息卡片
                fluent.Card(
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: item.avatarUrl != null ? NetworkImage(item.avatarUrl!) : null,
                        child: item.avatarUrl == null ? Text(item.username[0].toUpperCase()) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(item.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                                if (item.isSponsor) ...[
                                  const SizedBox(width: 4),
                                  Icon(fluent.FluentIcons.verified_brand, color: fluent.Colors.orange, size: 14),
                                ],
                              ],
                            ),
                            Text(item.email, style: fluent.FluentTheme.of(context).typography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 赞助统计
                _buildUserInfoRow('排名', '#${item.rank}'),
                _buildUserInfoRow('累计赞助', '¥${item.totalAmount.toStringAsFixed(2)}'),
                _buildUserInfoRow('赞助次数', '${item.donationCount} 次'),
                if (item.sponsorSince != null)
                  _buildUserInfoRow('赞助时间', _formatDateTime(item.sponsorSince)),
                const SizedBox(height: 16),

                // 赞助记录
                Text('赞助记录 (${details?.donations.length ?? 0})', style: fluent.FluentTheme.of(context).typography.bodyStrong),
                const SizedBox(height: 8),
                if (details?.donations.isEmpty ?? true)
                  Text('暂无赞助记录', style: fluent.FluentTheme.of(context).typography.caption)
                else
                  ...details!.donations.map((donation) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: fluent.Card(
                          child: Row(
                            children: [
                              Icon(
                                donation.isPaid ? fluent.FluentIcons.check_mark : fluent.FluentIcons.clock,
                                color: donation.isPaid ? fluent.Colors.green : fluent.Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥${donation.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(
                                      '${donation.paymentTypeText} · ${donation.statusText}',
                                      style: fluent.FluentTheme.of(context).typography.caption,
                                    ),
                                    Text(
                                      _formatDateTime(donation.paidAt ?? donation.createdAt),
                                      style: fluent.FluentTheme.of(context).typography.caption,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )),
              ],
            ),
          ),
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
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
