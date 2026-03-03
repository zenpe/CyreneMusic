import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../features/auth/auth_feature.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../services/netease_login_service.dart';
import '../../services/kugou_login_service.dart';
import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import 'netease_qr_dialog.dart';

import 'kugou_qr_dialog.dart';

/// 第三方账号管理二级页面内容
class ThirdPartyAccountsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embed;
  
  const ThirdPartyAccountsContent({
    super.key,
    this.onBack,
    this.embed = false,
  });

  @override
  State<ThirdPartyAccountsContent> createState() => _ThirdPartyAccountsContentState();
  
  /// 构建 Fluent UI 面包屑导航（Windows 11 24H2 风格）
  Widget buildFluentBreadcrumb(BuildContext context) {
    final theme = fluent_ui.FluentTheme.of(context);
    final typography = theme.typography;
    
    // Windows 11 设置页面的面包屑样式：
    // - 无返回按钮
    // - 父级页面文字颜色较浅，可点击
    // - 当前页面文字颜色正常
    // - 字体大小与 PageHeader 的 title 一致（使用 typography.title）
    return Row(
      children: [
        // 父级：设置（颜色较浅，可点击）
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              '设置',
              style: typography.title?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            fluent_ui.FluentIcons.chevron_right,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        // 当前页面：第三方账号（正常颜色）
        Text(
          '第三方账号',
          style: typography.title,
        ),
      ],
    );
  }
}

class _ThirdPartyAccountsContentState extends State<ThirdPartyAccountsContent> {
  final AuthFacade _authFacade = AuthFacade();
  int _refreshKey = 0;

  void _refresh() {
    if (mounted) {
      setState(() {
        _refreshKey++;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _authFacade.addAuthStateListener(_onAuthChanged);
    // 监听第三方登录服务的状态变化
    NeteaseLoginService().addListener(_onBindingChanged);
    KugouLoginService().addListener(_onBindingChanged);
  }

  @override
  void dispose() {
    _authFacade.removeAuthStateListener(_onAuthChanged);
    NeteaseLoginService().removeListener(_onBindingChanged);
    KugouLoginService().removeListener(_onBindingChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  /// 当第三方账号绑定状态变化时刷新 UI
  void _onBindingChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _authFacade.currentUser;
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
    
    // 如果未登录，显示提示信息
    if (user == null) {
      return _buildNotLoggedIn(context, isFluent, isCupertino);
    }

    if (isCupertino) {
      return _buildCupertinoContent(context, user);
    }
    if (isFluent) {
      return _buildFluentContent(context, user);
    }
    return _buildMaterialContent(context, user);
  }

  /// 构建未登录提示
  Widget _buildNotLoggedIn(BuildContext context, bool isFluent, bool isCupertino) {
    if (isCupertino) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return CupertinoScrollbar(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.person_circle,
                    size: 64,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '未登录',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请先登录 Cyrene Music 账号后再管理第三方账号',
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.systemGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    
    if (isFluent) {
      return fluent_ui.ListView(
        padding: const EdgeInsets.all(24),
        children: [
          fluent_ui.InfoBar(
            title: const Text('未登录'),
            content: const Text('请先登录 Cyrene Music 账号后再管理第三方账号'),
            severity: fluent_ui.InfoBarSeverity.warning,
          ),
        ],
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(
                  Icons.account_circle_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '未登录',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '请先登录 Cyrene Music 账号后再管理第三方账号',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialContent(BuildContext context, dynamic user) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 提示信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '绑定第三方账号后，我们可以为您定制首页推荐内容',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        
        MD3SettingsSection(
          title: '网易云音乐',
          children: [
            _buildNeteaseCard(context, user),
          ],
        ),
        
        MD3SettingsSection(
          title: '酷狗音乐',
          children: [
            _buildKugouCard(context, user),
          ],
        ),
      ],
    );
  }

  /// 构建 Cupertino UI 内容
  Widget _buildCupertinoContent(BuildContext context, dynamic user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground;
    
    return Container(
      color: backgroundColor,
      child: CupertinoScrollbar(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ThemeManager.iosBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.info_circle_fill,
                    color: ThemeManager.iosBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '绑定第三方账号后，我们可以为您定制首页推荐内容',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // 网易云音乐
            CupertinoSettingsSection(
              header: '网易云音乐',
              children: [
                _buildCupertinoNeteaseCard(context, user),
              ],
            ),
            const SizedBox(height: 16),
            
            // 酷狗音乐
            CupertinoSettingsSection(
              header: '酷狗音乐',
              children: [
                _buildCupertinoKugouCard(context, user),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建网易云音乐卡片 (Cupertino)
  Widget _buildCupertinoNeteaseCard(BuildContext context, dynamic user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_refreshKey),
      future: NeteaseLoginService().fetchBindings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemRed,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.cloud_fill, color: CupertinoColors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('网易云音乐', style: TextStyle(fontSize: 16)),
                      Text('加载中...', style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                    ],
                  ),
                ),
                const CupertinoActivityIndicator(),
              ],
            ),
          );
        }

        final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
        final netease = bindings?['netease'] as Map<String, dynamic>?;
        final bound = (netease != null) && (netease['bound'] == true);
        final nickname = netease?['nickname'] as String?;
        final avatarUrl = netease?['avatarUrl'] as String?;
        final neteaseUserId = netease?['userId']?.toString();

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: avatarUrl != null
                      ? DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover)
                      : null,
                  color: avatarUrl == null ? CupertinoColors.systemRed : null,
                ),
                child: avatarUrl == null
                    ? const Icon(CupertinoIcons.cloud_fill, color: CupertinoColors.white, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '网易云音乐',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (bound) ...[
                      Text(
                        '昵称: ${nickname ?? '-'}',
                        style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                      ),
                      Text(
                        'ID: ${neteaseUserId ?? '-'}',
                        style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                      ),
                    ] else
                      Text(
                        '未绑定',
                        style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                      ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: bound ? CupertinoColors.systemGrey4 : ThemeManager.iosBlue,
                minSize: 0,
                onPressed: bound
                    ? () => _showUnbindDialogCupertino(context, '网易云音乐', () async {
                        return await NeteaseLoginService().unbindNetease();
                      })
                    : () => _bindNetease(context, user.id),
                child: Text(
                  bound ? '解绑' : '去绑定',
                  style: TextStyle(
                    fontSize: 14,
                    color: bound
                        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                        : CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 构建酷狗音乐卡片 (Cupertino)
  Widget _buildCupertinoKugouCard(BuildContext context, dynamic user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_refreshKey),
      future: KugouLoginService().fetchBindings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(CupertinoIcons.music_note, color: CupertinoColors.white, size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('酷狗音乐', style: TextStyle(fontSize: 16)),
                      Text('加载中...', style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)),
                    ],
                  ),
                ),
                const CupertinoActivityIndicator(),
              ],
            ),
          );
        }

        final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
        final kugou = bindings?['kugou'] as Map<String, dynamic>?;
        final bound = (kugou != null) && (kugou['bound'] == true);
        final username = kugou?['username'] as String?;
        final avatar = kugou?['avatar'] as String?;
        final kugouUserId = kugou?['userId']?.toString();

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: avatar != null
                      ? DecorationImage(image: NetworkImage(avatar), fit: BoxFit.cover)
                      : null,
                  color: avatar == null ? CupertinoColors.systemBlue : null,
                ),
                child: avatar == null
                    ? const Icon(CupertinoIcons.music_note, color: CupertinoColors.white, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '酷狗音乐',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (bound) ...[
                      Text(
                        '昵称: ${username ?? '-'}',
                        style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                      ),
                      Text(
                        'ID: ${kugouUserId ?? '-'}',
                        style: TextStyle(fontSize: 12, color: CupertinoColors.systemGrey),
                      ),
                    ] else
                      Text(
                        '未绑定',
                        style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                      ),
                  ],
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: bound ? CupertinoColors.systemGrey4 : ThemeManager.iosBlue,
                minSize: 0,
                onPressed: bound
                    ? () => _showUnbindDialogCupertino(context, '酷狗音乐', () async {
                        return await KugouLoginService().unbindKugou();
                      })
                    : () => _bindKugou(context, user.id),
                child: Text(
                  bound ? '解绑' : '去绑定',
                  style: TextStyle(
                    fontSize: 14,
                    color: bound
                        ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                        : CupertinoColors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示 Cupertino 风格解绑对话框
  void _showUnbindDialogCupertino(BuildContext context, String serviceName, Future<bool> Function() unbindAction) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('解绑$serviceName账号'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(context);
              final ok = await unbindAction();
              if (ok) {
                _refresh();
              }
            },
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }

  /// 构建 Fluent UI 内容
  Widget _buildFluentContent(BuildContext context, dynamic user) {
    return fluent_ui.ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 提示信息
        fluent_ui.InfoBar(
          title: const Text('提示'),
          content: const Text('绑定第三方账号后，我们可以为您定制首页推荐内容'),
          severity: fluent_ui.InfoBarSeverity.info,
        ),
        const SizedBox(height: 24),
        
        // 网易云音乐
        FluentSettingsGroup(
          title: '网易云音乐',
          children: [
            _buildFluentNeteaseCard(context, user),
          ],
        ),
        const SizedBox(height: 16),
        
        // 酷狗音乐
        FluentSettingsGroup(
          title: '酷狗音乐',
          children: [
            _buildFluentKugouCard(context, user),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildNeteaseCard(BuildContext context, dynamic user) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_refreshKey),
      future: NeteaseLoginService().fetchBindings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MD3SettingsTile(
            leading: Icon(Icons.cloud_outlined),
            title: '网易云音乐',
            subtitle: '加载中...',
            trailing: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
        final netease = bindings?['netease'] as Map<String, dynamic>?;
        final bound = (netease != null) && (netease['bound'] == true);
        final nickname = netease?['nickname'] as String?;
        final avatarUrl = netease?['avatarUrl'] as String?;
        final neteaseUserId = netease?['userId']?.toString();

        return MD3SettingsTile(
          leading: avatarUrl != null
              ? CircleAvatar(
                  radius: 12,
                  backgroundImage: NetworkImage(avatarUrl),
                )
              : const Icon(Icons.cloud_outlined),
          title: '网易云音乐',
          subtitle: bound
              ? '昵称: ${nickname ?? '-'}\n用户ID: ${neteaseUserId ?? '-'}'
              : '未绑定',
          trailing: bound
              ? TextButton.icon(
                  onPressed: () => _showUnbindDialog(context),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('解绑'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                )
              : FilledButton.icon(
                  onPressed: () => _bindNetease(context, user.id),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('去绑定'),
                ),
        );
      },
    );
  }

  Widget _buildKugouCard(BuildContext context, dynamic user) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_refreshKey),
      future: KugouLoginService().fetchBindings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MD3SettingsTile(
            leading: Icon(Icons.music_note_outlined),
            title: '酷狗音乐',
            subtitle: '加载中...',
            trailing: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
        final kugou = bindings?['kugou'] as Map<String, dynamic>?;
        final bound = (kugou != null) && (kugou['bound'] == true);
        final username = kugou?['username'] as String?;
        final avatar = kugou?['avatar'] as String?;
        final kugouUserId = kugou?['userId']?.toString();

        return MD3SettingsTile(
          leading: avatar != null
              ? CircleAvatar(
                  radius: 12,
                  backgroundImage: NetworkImage(avatar),
                )
              : const Icon(Icons.music_note_outlined),
          title: '酷狗音乐',
          subtitle: bound
              ? '昵称: ${username ?? '-'}\n用户ID: ${kugouUserId ?? '-'}'
              : '未绑定',
          trailing: bound
              ? TextButton.icon(
                  onPressed: () => _showUnbindKugouDialog(context),
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('解绑'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                )
              : FilledButton.icon(
                  onPressed: () => _bindKugou(context, user.id),
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('去绑定'),
                ),
        );
      },
    );
  }

  /// 构建网易云音乐卡片 (Fluent)
  Widget _buildFluentNeteaseCard(BuildContext context, dynamic user) {
    return fluent_ui.Card(
      padding: fluent_ui.EdgeInsets.zero,
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshKey),
        future: NeteaseLoginService().fetchBindings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const fluent_ui.ListTile(
              leading: Icon(Icons.cloud, size: 20),
              title: Text('网易云音乐'),
              subtitle: Text('加载中...'),
              trailing: fluent_ui.ProgressRing(),
            );
          }

          final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
          final netease = bindings?['netease'] as Map<String, dynamic>?;
          final bound = (netease != null) && (netease['bound'] == true);
          final nickname = netease?['nickname'] as String?;
          final avatarUrl = netease?['avatarUrl'] as String?;
          final neteaseUserId = netease?['userId']?.toString();

          return fluent_ui.ListTile(
            leading: avatarUrl != null
                ? CircleAvatar(backgroundImage: NetworkImage(avatarUrl))
                : const Icon(Icons.cloud, size: 20),
            title: const Text('网易云音乐'),
            subtitle: bound
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('昵称: ${nickname ?? '-'}'),
                      Text('用户ID: ${neteaseUserId ?? '-'}'),
                    ],
                  )
                : const Text('未绑定'),
            trailing: bound
                ? fluent_ui.Button(
                    onPressed: () => _showUnbindDialogFluent(context),
                    child: const Text('解绑'),
                  )
                : fluent_ui.FilledButton(
                    onPressed: () => _bindNetease(context, user.id),
                    child: const Text('去绑定'),
                  ),
          );
        },
      ),
    );
  }

  /// 构建酷狗音乐卡片 (Fluent)
  Widget _buildFluentKugouCard(BuildContext context, dynamic user) {
    return fluent_ui.Card(
      padding: fluent_ui.EdgeInsets.zero,
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshKey),
        future: KugouLoginService().fetchBindings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const fluent_ui.ListTile(
              leading: Icon(Icons.music_note, size: 20),
              title: Text('酷狗音乐'),
              subtitle: Text('加载中...'),
              trailing: fluent_ui.ProgressRing(),
            );
          }

          final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
          final kugou = bindings?['kugou'] as Map<String, dynamic>?;
          final bound = (kugou != null) && (kugou['bound'] == true);
          final username = kugou?['username'] as String?;
          final avatar = kugou?['avatar'] as String?;
          final kugouUserId = kugou?['userId']?.toString();

          return fluent_ui.ListTile(
            leading: avatar != null
                ? CircleAvatar(backgroundImage: NetworkImage(avatar))
                : const Icon(Icons.music_note, size: 20),
            title: const Text('酷狗音乐'),
            subtitle: bound
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('昵称: ${username ?? '-'}'),
                      Text('用户ID: ${kugouUserId ?? '-'}'),
                    ],
                  )
                : const Text('未绑定'),
            trailing: bound
                ? fluent_ui.Button(
                    onPressed: () => _showUnbindKugouDialogFluent(context),
                    child: const Text('解绑'),
                  )
                : fluent_ui.FilledButton(
                    onPressed: () => _bindKugou(context, user.id),
                    child: const Text('去绑定'),
                  ),
          );
        },
      ),
    );
  }

  // ========== 绑定/解绑逻辑 ==========

  Future<bool> _waitUntilNeteaseBound({int maxAttempts = 6, Duration interval = const Duration(milliseconds: 500)}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final resp = await NeteaseLoginService().fetchBindings();
        final data = resp['data'] as Map<String, dynamic>?;
        final netease = data != null ? data['netease'] as Map<String, dynamic>? : null;
        final bound = (netease != null) && (netease['bound'] == true);
        if (bound) return true;
      } catch (_) {}
      await Future.delayed(interval);
    }
    return false;
  }

  Future<void> _bindNetease(BuildContext context, int userId) async {
    final success = await showNeteaseQrDialog(context, userId);
    if (success == true) {
      await _waitUntilNeteaseBound();
      _refresh();
      if (context.mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('网易云账号绑定成功！现在可以为您定制首页了'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _showUnbindDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded),
            SizedBox(width: 8),
            Text('解绑网易云账号'),
          ],
        ),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              
              if (context.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text('正在解绑...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }

              final ok = await NeteaseLoginService().unbindNetease();
              
              if (context.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(ok ? '已解绑网易云账号' : '解绑失败，请重试'),
                      backgroundColor: ok ? Colors.orange : Colors.red,
                    ),
                  );
                }
                
                if (ok) {
                  _refresh();
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }

  void _showUnbindDialogFluent(BuildContext context) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('解绑网易云账号'),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final ok = await NeteaseLoginService().unbindNetease();
              if (ok) {
                _refresh();
              }
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (messenger != null) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? '已解绑网易云账号' : '解绑失败，请重试'),
                    backgroundColor: ok ? Colors.orange : Colors.red,
                  ),
                );
              }
            },
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }

  Future<bool> _waitUntilKugouBound({int maxAttempts = 6, Duration interval = const Duration(milliseconds: 500)}) async {
    for (var i = 0; i < maxAttempts; i++) {
      try {
        final resp = await KugouLoginService().fetchBindings();
        final data = resp['data'] as Map<String, dynamic>?;
        final kugou = data != null ? data['kugou'] as Map<String, dynamic>? : null;
        final bound = (kugou != null) && (kugou['bound'] == true);
        if (bound) return true;
      } catch (_) {}
      await Future.delayed(interval);
    }
    return false;
  }

  Future<void> _bindKugou(BuildContext context, int userId) async {
    final success = await showKugouQrDialog(context, userId);
    if (success == true) {
      await _waitUntilKugouBound();
      _refresh();
      if (context.mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('酷狗音乐账号绑定成功！现在可以为您定制首页了'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _showUnbindKugouDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded),
            SizedBox(width: 8),
            Text('解绑酷狗音乐账号'),
          ],
        ),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              
              if (context.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text('正在解绑...'),
                        ],
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              }

              final ok = await KugouLoginService().unbindKugou();
              
              if (context.mounted) {
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(ok ? '已解绑酷狗音乐账号' : '解绑失败，请重试'),
                      backgroundColor: ok ? Colors.orange : Colors.red,
                    ),
                  );
                }
                
                if (ok) {
                  _refresh();
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }

  void _showUnbindKugouDialogFluent(BuildContext context) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('解绑酷狗音乐账号'),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final ok = await KugouLoginService().unbindKugou();
              if (ok) {
                _refresh();
              }
              final messenger = ScaffoldMessenger.maybeOf(context);
              if (messenger != null) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? '已解绑酷狗音乐账号' : '解绑失败，请重试'),
                    backgroundColor: ok ? Colors.orange : Colors.red,
                  ),
                );
              }
            },
            child: const Text('解绑'),
          ),
        ],
      ),
    );
  }
}
