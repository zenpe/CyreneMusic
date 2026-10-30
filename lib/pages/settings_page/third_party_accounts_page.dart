import '../../utils/app_feedback.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../features/auth/auth_feature.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../widgets/cupertino/cupertino_settings_widgets.dart';
import '../../services/netease_login_service.dart';

import '../../utils/theme_manager.dart';
import '../../widgets/material/material_settings_widgets.dart';
import 'netease_login_page.dart';

import 'netease_playlists_page.dart';

/// 第三方账号管理二级页面内容
class ThirdPartyAccountsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embed;

  const ThirdPartyAccountsContent({super.key, this.onBack, this.embed = false});

  @override
  State<ThirdPartyAccountsContent> createState() =>
      _ThirdPartyAccountsContentState();

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
        Text('第三方账号', style: typography.title),
      ],
    );
  }
}

class _ThirdPartyAccountsContentState extends State<ThirdPartyAccountsContent> {
  final AuthFacade _authFacade = AuthFacade();
  int _refreshKey = 0;
  bool _unbindBusy = false;
  String? _unbindError;
  late Future<Map<String, dynamic>> _bindingsFuture;

  Future<Map<String, dynamic>> _loadBindings() => _authFacade.isLoggedIn
      ? NeteaseLoginService().fetchBindings()
      : Future.value(<String, dynamic>{});

  void _refresh() {
    if (mounted) {
      setState(() {
        _bindingsFuture = _loadBindings();
        _refreshKey++;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _bindingsFuture = _loadBindings();
    _authFacade.addAuthStateListener(_onAuthChanged);
    // 监听第三方登录服务的状态变化
    NeteaseLoginService().addListener(_onBindingChanged);
  }

  @override
  void dispose() {
    _authFacade.removeAuthStateListener(_onAuthChanged);
    NeteaseLoginService().removeListener(_onBindingChanged);
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
    final isCupertino =
        (Platform.isIOS || Platform.isAndroid) &&
        ThemeManager().isCupertinoFramework;

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
  Widget _buildNotLoggedIn(
    BuildContext context,
    bool isFluent,
    bool isCupertino,
  ) {
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
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
                Text('未登录', style: Theme.of(context).textTheme.titleLarge),
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
      children: [
        // 提示信息
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                    '绑定网易云账号后，可导入个人歌单并获取网易云推荐；酷狗暂不支持',
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
          children: [_buildNeteaseCard(context, user)],
        ),

        MD3SettingsSection(
          title: '酷狗音乐',
          children: [_buildKugouCard(context, user)],
        ),
      ],
    );
  }

  /// 构建 Cupertino UI 内容
  Widget _buildCupertinoContent(BuildContext context, dynamic user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? CupertinoColors.black
        : CupertinoColors.systemGroupedBackground;

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
                color: ThemeManager.iosBlue.withValues(alpha: 0.1),
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
                      '绑定网易云账号后，可导入个人歌单并获取网易云推荐；酷狗暂不支持',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? CupertinoColors.white
                            : CupertinoColors.black,
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
              children: [_buildCupertinoNeteaseCard(context, user)],
            ),
            const SizedBox(height: 16),

            // 酷狗音乐
            CupertinoSettingsSection(
              header: '酷狗音乐',
              children: [_buildCupertinoKugouCard(context, user)],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建网易云音乐卡片 (Cupertino)
  Widget _buildCupertinoNeteaseCard(BuildContext context, dynamic user) {
    return _neteaseAccountTile(context, user);
  }

  /// 构建酷狗音乐卡片 (Cupertino)
  Widget _buildCupertinoKugouCard(BuildContext context, dynamic user) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(CupertinoIcons.music_note),
          SizedBox(width: 12),
          Expanded(child: Text('酷狗音乐')),
          Text('暂不支持', style: TextStyle(color: CupertinoColors.systemGrey)),
        ],
      ),
    );
  }

  /// 显示 Cupertino 风格解绑对话框
  void _showUnbindDialogCupertino(
    BuildContext context,
    String serviceName,
    Future<bool> Function() unbindAction,
  ) {
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
          content: const Text('绑定网易云账号后，可导入个人歌单并获取网易云推荐；酷狗暂不支持'),
          severity: fluent_ui.InfoBarSeverity.info,
        ),
        const SizedBox(height: 24),

        // 网易云音乐
        FluentSettingsGroup(
          title: '网易云音乐',
          children: [_buildFluentNeteaseCard(context, user)],
        ),
        const SizedBox(height: 16),

        // 酷狗音乐
        FluentSettingsGroup(
          title: '酷狗音乐',
          children: [_buildFluentKugouCard(context, user)],
        ),
      ],
    );
  }

  Widget _buildNeteaseCard(BuildContext context, dynamic user) {
    return _neteaseAccountTile(context, user);
  }

  Widget _buildKugouCard(BuildContext context, dynamic user) {
    return const MD3SettingsTile(
      leading: Icon(Icons.music_note_outlined),
      title: '酷狗音乐',
      subtitle: '暂不支持',
      trailing: TextButton(onPressed: null, child: Text('暂不支持')),
    );
  }

  /// 构建网易云音乐卡片 (Fluent)
  Widget _buildFluentNeteaseCard(BuildContext context, dynamic user) {
    return _neteaseAccountTile(context, user);
  }

  /// 构建酷狗音乐卡片 (Fluent)
  Widget _buildFluentKugouCard(BuildContext context, dynamic user) {
    return const fluent_ui.ListTile(
      leading: Icon(fluent_ui.FluentIcons.music_note),
      title: Text('酷狗音乐'),
      subtitle: Text('暂不支持'),
      trailing: fluent_ui.Button(onPressed: null, child: Text('暂不支持')),
    );
  }

  // ========== 绑定/解绑逻辑 ==========

  Future<bool> _tryUnbind() async {
    if (_unbindBusy || !mounted) return false;
    setState(() { _unbindBusy = true; _unbindError = null; });
    var succeeded = false;
    try {
      succeeded = await NeteaseLoginService().unbindNetease();
    } catch (_) {
      succeeded = false;
    } finally {
      if (mounted) {
        setState(() {
          _unbindBusy = false;
          _unbindError = succeeded ? null : '解绑失败，请重试';
        });
      }
    }
    if (succeeded) _refresh();
    return succeeded;
  }

  Future<void> _bindNetease(BuildContext context, int userId) async {
    final success = await showNeteaseLogin(context, userId);
    if (success == true) {
      _refresh();
      if (context.mounted) {
        final messenger = AppFeedback.maybeOf(context);
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('解绑网易云账号'),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消')),
          FilledButton(
            onPressed: () { Navigator.pop(dialogContext); _tryUnbind(); },
            child: const Text('解绑')),
      ]));
  }

  void _showUnbindDialogFluent(BuildContext context) {
    fluent_ui.showDialog<void>(
      context: context,
      builder: (dialogContext) => fluent_ui.ContentDialog(
        title: const Text('解绑网易云账号'),
        content: const Text('解绑后将无法为您定制首页推荐内容，确定要解绑吗？'),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消')),
          fluent_ui.FilledButton(
            onPressed: () { Navigator.pop(dialogContext); _tryUnbind(); },
            child: const Text('解绑')),
      ]));
  }

  Widget _accountButton(String title, VoidCallback action) {
    if (ThemeManager().isDesktopFluentUI) {
      return fluent_ui.Button(onPressed: action, child: Text(title));
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoButton(onPressed: action, child: Text(title));
    }
    return TextButton(onPressed: action, child: Text(title));
  }

  Widget _neteaseAccountTile(BuildContext context, dynamic user) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_refreshKey),
      future: _bindingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('绑定状态获取失败：${snapshot.error}'),
                _accountButton('重试', _refresh),
              ],
            ),
          );
        }
        final b = (snapshot.data?['data'] as Map?)?['netease'] as Map?;
        final bound = b?['bound'] == true;
        final expired = b?['status'] == 'expired';
        final avatar = b?['avatarUrl'] as String?;
        final content = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_unbindBusy) const Text('正在解绑…'),
              if (_unbindError != null) Semantics(liveRegion: true, child: Row(children: [
                Expanded(child: Text(_unbindError!)),
                _accountButton('重试', () { _tryUnbind(); }),
              ])),
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: avatar != null && avatar.isNotEmpty
                        ? NetworkImage(avatar)
                        : null,
                    child: avatar == null || avatar.isEmpty
                        ? const Icon(Icons.cloud_outlined)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('网易云音乐'),
                        Text(
                          bound
                              ? '${b?['nickname'] ?? '已绑定'} · ID ${b?['uid'] ?? ''}'
                              : expired
                              ? '${b?['nickname'] ?? '网易云'} · 登录已过期'
                              : '未绑定',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              IgnorePointer(ignoring: _unbindBusy, child: Opacity(opacity: _unbindBusy ? .5 : 1, child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _accountButton(
                    bound
                        ? '更换账号'
                        : expired
                        ? '重新绑定'
                        : '去绑定',
                    () => _bindNetease(context, user.id),
                  ),
                  if (bound)
                    _accountButton('个人歌单', () {
                      final themes = InheritedTheme.capture(
                        from: context,
                        to: Navigator.of(context).context,
                      );
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              themes.wrap(const NeteasePlaylistsPage()),
                        ),
                      );
                    }),
                  if (bound || expired)
                    _accountButton('解绑', () {
                      if (ThemeManager().isDesktopFluentUI) {
                        _showUnbindDialogFluent(context);
                      } else if (ThemeManager().isCupertinoFramework) {
                        _showUnbindDialogCupertino(
                          context,
                          '网易云音乐',
                          _tryUnbind,
                        );
                      } else {
                        _showUnbindDialog(context);
                      }
                    }),
                ],
              ))),
            ],
          ),
        );
        if (ThemeManager().isDesktopFluentUI) {
          return fluent_ui.Card(padding: EdgeInsets.zero, child: content);
        }
        if (ThemeManager().isCupertinoFramework) return content;
        return Card(child: content);
      },
    );
  }
}
