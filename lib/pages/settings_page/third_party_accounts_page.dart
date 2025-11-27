import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../widgets/fluent_settings_card.dart';
import '../../services/auth_service.dart';
import '../../services/netease_login_service.dart';
import '../../services/kugou_login_service.dart';
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
  
  /// 构建 Fluent UI 面包屑导航
  Widget buildFluentBreadcrumb(BuildContext context) {
    return Row(
      children: [
        fluent_ui.Button(
          style: fluent_ui.ButtonStyle(
            padding: fluent_ui.WidgetStateProperty.all(EdgeInsets.zero),
          ),
          onPressed: onBack,
          child: const Text('设置'),
        ),
        const fluent_ui.Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(fluent_ui.FluentIcons.chevron_right, size: 12),
        ),
        const Text('第三方账号'),
      ],
    );
  }
}

class _ThirdPartyAccountsContentState extends State<ThirdPartyAccountsContent> {
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
    AuthService().addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService().currentUser;
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    
    // 如果未登录，显示提示信息
    if (user == null) {
      return _buildNotLoggedIn(context, isFluent);
    }

    if (isFluent) {
      return _buildFluentContent(context, user);
    }
    return _buildMaterialContent(context, user);
  }

  /// 构建未登录提示
  Widget _buildNotLoggedIn(BuildContext context, bool isFluent) {
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

  /// 构建 Material UI 内容
  Widget _buildMaterialContent(BuildContext context, dynamic user) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 提示信息
        Card(
          color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
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
        const SizedBox(height: 24),
        
        // 网易云音乐
        _buildSectionTitle(context, '网易云音乐'),
        const SizedBox(height: 8),
        _buildNeteaseCard(context, user),
        const SizedBox(height: 24),
        
        // 酷狗音乐
        _buildSectionTitle(context, '酷狗音乐'),
        const SizedBox(height: 8),
        _buildKugouCard(context, user),
      ],
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

  /// 构建网易云音乐卡片 (Material)
  Widget _buildNeteaseCard(BuildContext context, dynamic user) {
    return Card(
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshKey),
        future: NeteaseLoginService().fetchBindings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListTile(
              leading: CircleAvatar(child: Icon(Icons.cloud)),
              title: Text('网易云音乐'),
              subtitle: Text('加载中...'),
              trailing: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
          final netease = bindings?['netease'] as Map<String, dynamic>?;
          final bound = (netease != null) && (netease['bound'] == true);
          final nickname = netease?['nickname'] as String?;
          final avatarUrl = netease?['avatarUrl'] as String?;
          final neteaseUserId = netease?['userId'] as String?;

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child: avatarUrl == null ? const Icon(Icons.cloud) : null,
            ),
            title: const Text('网易云音乐'),
            subtitle: bound
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('昵称: ${nickname ?? '-'}'),
                      Text(
                        '用户ID: ${neteaseUserId ?? '-'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )
                : const Text('未绑定'),
            trailing: bound
                ? OutlinedButton.icon(
                    onPressed: () => _showUnbindDialog(context),
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('解绑'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => _bindNetease(context, user.id),
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('去绑定'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
          );
        },
      ),
    );
  }

  /// 构建酷狗音乐卡片 (Material)
  Widget _buildKugouCard(BuildContext context, dynamic user) {
    return Card(
      child: FutureBuilder<Map<String, dynamic>>(
        key: ValueKey(_refreshKey),
        future: KugouLoginService().fetchBindings(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const ListTile(
              leading: CircleAvatar(child: Icon(Icons.music_note)),
              title: Text('酷狗音乐'),
              subtitle: Text('加载中...'),
              trailing: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }

          final bindings = snapshot.data?['data'] as Map<String, dynamic>?;
          final kugou = bindings?['kugou'] as Map<String, dynamic>?;
          final bound = (kugou != null) && (kugou['bound'] == true);
          final username = kugou?['username'] as String?;
          final avatar = kugou?['avatar'] as String?;
          final kugouUserId = kugou?['userId'] as String?;

          return ListTile(
            leading: CircleAvatar(
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null ? const Icon(Icons.music_note) : null,
            ),
            title: const Text('酷狗音乐'),
            subtitle: bound
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('昵称: ${username ?? '-'}'),
                      Text(
                        '用户ID: ${kugouUserId ?? '-'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  )
                : const Text('未绑定'),
            trailing: bound
                ? OutlinedButton.icon(
                    onPressed: () => _showUnbindKugouDialog(context),
                    icon: const Icon(Icons.link_off, size: 18),
                    label: const Text('解绑'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: () => _bindKugou(context, user.id),
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('去绑定'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
          );
        },
      ),
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
          final neteaseUserId = netease?['userId'] as String?;

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
          final kugouUserId = kugou?['userId'] as String?;

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
