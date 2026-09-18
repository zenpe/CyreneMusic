import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../features/auth/auth_feature.dart';
import '../../services/location_service.dart';
import '../../services/avatar_fetch_service.dart';
import '../../utils/theme_manager.dart';
import '../auth/auth_page.dart';

/// 全局函数：在 Fluent UI 中显示登录对话框
/// 可在任意地方调用此函数来显示登录对话框
Future<bool?> showFluentLoginDialog(BuildContext context) {
  return showAuthDialog(context);
}

/// 用户卡片组件
class UserCard extends StatefulWidget {
  const UserCard({super.key});

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  final AuthFacade _authFacade = AuthFacade();
  final TextEditingController _usernameController = TextEditingController();
  bool _isUpdatingUsername = false;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    _authFacade.addAuthStateListener(_onAuthChanged);
    LocationService().addListener(_onLocationChanged);
  }


  @override
  void dispose() {
    _usernameController.dispose();
    _authFacade.removeAuthStateListener(_onAuthChanged);
    LocationService().removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  void _onLocationChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  /// 显示修改用户名对话框 - Material UI
  Future<void> _showUpdateUsernameDialogMaterial(BuildContext context) async {
    final currentUser = _authFacade.currentUser;
    if (currentUser == null) return;

    _usernameController.text = currentUser.username;
    _usernameError = null;
    _isUpdatingUsername = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('修改用户名'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: '新用户名',
                  hintText: '2-20位，支持中文、字母、数字、下划线',
                  errorText: _usernameError,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person),
                ),
                enabled: !_isUpdatingUsername,
              ),
              const SizedBox(height: 8),
              Text(
                '注意：用户名支持2-20个字符，可以包含中文、字母、数字和下划线',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isUpdatingUsername ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: _isUpdatingUsername
                  ? null
                  : () async {
                      final newUsername = _usernameController.text.trim();
                      
                      if (newUsername.isEmpty) {
                        setDialogState(() {
                          _usernameError = '用户名不能为空';
                        });
                        return;
                      }

                      if (newUsername == currentUser.username) {
                        setDialogState(() {
                          _usernameError = '新用户名与当前用户名相同';
                        });
                        return;
                      }

                      setDialogState(() {
                        _isUpdatingUsername = true;
                        _usernameError = null;
                      });

                      final result = await _authFacade.updateUsername(newUsername);

                      if (!mounted) return;

                      if (result['success'] == true) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('用户名更新成功'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        setDialogState(() {
                          _isUpdatingUsername = false;
                          _usernameError = result['message'] ?? '更新失败';
                        });
                      }
                    },
              child: _isUpdatingUsername
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示修改用户名对话框 - Fluent UI
  Future<void> _showUpdateUsernameDialogFluent(BuildContext context) async {
    final currentUser = _authFacade.currentUser;
    if (currentUser == null) return;

    _usernameController.text = currentUser.username;
    _usernameError = null;
    _isUpdatingUsername = false;

    await fluent_ui.showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => fluent_ui.ContentDialog(
          title: const Text('修改用户名'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fluent_ui.InfoLabel(
                label: '新用户名',
                child: fluent_ui.TextBox(
                  controller: _usernameController,
                  placeholder: '2-20位，支持中文、字母、数字、下划线',
                  enabled: !_isUpdatingUsername,
                  prefix: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(fluent_ui.FluentIcons.contact),
                  ),
                  prefixMode: fluent_ui.OverlayVisibilityMode.always,
                ),
              ),
              if (_usernameError != null) ...[
                const SizedBox(height: 8),
                fluent_ui.InfoBar(
                  title: const Text('错误'),
                  content: Text(_usernameError!),
                  severity: fluent_ui.InfoBarSeverity.error,
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '注意：用户名支持2-20个字符，可以包含中文、字母、数字和下划线',
                style: fluent_ui.FluentTheme.of(context).typography.caption,
              ),
            ],
          ),
          actions: [
            fluent_ui.Button(
              onPressed: _isUpdatingUsername ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            fluent_ui.FilledButton(
              onPressed: _isUpdatingUsername
                  ? null
                  : () async {
                      final newUsername = _usernameController.text.trim();
                      
                      if (newUsername.isEmpty) {
                        setDialogState(() {
                          _usernameError = '用户名不能为空';
                        });
                        return;
                      }

                      if (newUsername == currentUser.username) {
                        setDialogState(() {
                          _usernameError = '新用户名与当前用户名相同';
                        });
                        return;
                      }

                      setDialogState(() {
                        _isUpdatingUsername = true;
                        _usernameError = null;
                      });

                      final result = await _authFacade.updateUsername(newUsername);

                      if (!mounted) return;

                      if (result['success'] == true) {
                        Navigator.pop(dialogContext);
                        fluent_ui.displayInfoBar(
                          context,
                          builder: (context, close) => fluent_ui.InfoBar(
                            title: const Text('成功'),
                            content: const Text('用户名更新成功'),
                            severity: fluent_ui.InfoBarSeverity.success,
                          ),
                        );
                      } else {
                        setDialogState(() {
                          _isUpdatingUsername = false;
                          _usernameError = result['message'] ?? '更新失败';
                        });
                      }
                    },
              child: _isUpdatingUsername
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: fluent_ui.ProgressRing(strokeWidth: 2),
                    )
                  : const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = _authFacade.isLoggedIn;
    final user = _authFacade.currentUser;
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertinoUI = ThemeManager().isCupertinoFramework;
    
    if (!isLoggedIn || user == null) {
      if (isFluentUI) return _buildLoginCardFluent(context);
      if (isCupertinoUI) return _buildLoginCardCupertino(context);
      return _buildLoginCard(context);
    }
    
    if (isFluentUI) return _buildUserInfoCardFluent(context, user);
    if (isCupertinoUI) return _buildUserInfoCardCupertino(context, user);
    return _buildUserInfoCard(context, user);
  }

  Widget _buildLoginCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline,
                size: 32,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '未登录',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录后可享受更多功能',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => _handleLogin(context),
              child: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建用户信息卡片（已登录状态）
  Widget _buildUserInfoCard(BuildContext context, User user) {
    final colorScheme = Theme.of(context).colorScheme;
    // 优先使用服务器返回的头像 URL（如 Linux Do 用户），否则尝试从 QQ 邮箱生成
    final qqNumber = _extractQQNumber(user.email);
    final avatarUrl = user.avatarUrl ?? _getQQAvatarUrl(qqNumber);
    print('🖼️ [UserCard] user.avatarUrl: ${user.avatarUrl}');
    print('🖼️ [UserCard] 最终使用的 avatarUrl: $avatarUrl');
    
    return AnimatedBuilder(
      animation: LocationService(),
      builder: (context, child) {
        final location = LocationService().currentLocation;
        final isLoadingLocation = LocationService().isLoading;
        final theme = Theme.of(context);
      
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 用户头像
                    ClipOval(
                      child: Container(
                        width: 60,
                        height: 60,
                        color: colorScheme.primaryContainer,
                        child: avatarUrl != null
                            ? (avatarUrl.contains('linux.do')
                                // Linux DO 头像需要使用 AvatarFetchService 加载以绕过 Cloudflare
                                ? FutureBuilder<Uint8List?>(
                                    future: AvatarFetchService().fetchAvatar(
                                      avatarUrl,
                                      cacheKey: 'linuxdo_${user.id}',
                                    ),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: colorScheme.onPrimaryContainer,
                                            ),
                                          ),
                                        );
                                      }
                                      if (snapshot.hasData && snapshot.data != null) {
                                        return Image.memory(
                                          snapshot.data!,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Icon(
                                            Icons.person,
                                            size: 32,
                                            color: colorScheme.onPrimaryContainer,
                                          ),
                                        );
                                      }
                                      return Icon(
                                        Icons.person,
                                        size: 32,
                                        color: colorScheme.onPrimaryContainer,
                                      );
                                    },
                                  )
                                // 其他头像（如 QQ 头像）可以直接使用 Image.network
                                : Image.network(
                                    avatarUrl,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.person,
                                      size: 32,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ))
                            : Icon(
                                Icons.person,
                                size: 32,
                                color: colorScheme.onPrimaryContainer,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 用户名 + 编辑图标
                          Row(
                            children: [
                              Text(
                                user.username,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _showUpdateUsernameDialogMaterial(context),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (user.displayEmail != null) ...[
                            const SizedBox(height: 4),
                            // 邮箱
                            Row(
                              children: [
                                Icon(
                                  Icons.email_outlined,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    user.displayEmail!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 2),
                          // IP 归属地
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              if (isLoadingLocation)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '获取中...',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              else if (location != null)
                                Expanded(
                                  child: Text(
                                    location.shortDescription,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )
                              else
                                Expanded(
                                  child: Row(
                                    children: [
                                      Text(
                                        '获取失败',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: colorScheme.error,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      InkWell(
                                        onTap: () {
                                          print('🔄 [UserCard] 手动刷新IP归属地...');
                                          LocationService().fetchLocation();
                                        },
                                        child: Icon(
                                          Icons.refresh,
                                          size: 14,
                                          color: colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 退出按钮
                    IconButton(
                      onPressed: () => _authFacade.logout(),
                      icon: Icon(Icons.logout_rounded, color: colorScheme.error),
                      tooltip: '退出登录',
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

  /// 从邮箱中提取 QQ 号
  String? _extractQQNumber(String email) {
    final qqEmailPattern = RegExp(r'^(\d+)@qq\.com$');
    final match = qqEmailPattern.firstMatch(email.toLowerCase());
    
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    
    return null;
  }

  /// 获取 QQ 头像 URL
  String? _getQQAvatarUrl(String? qqNumber) {
    if (qqNumber == null || qqNumber.isEmpty) {
      return null;
    }
    
    return 'https://q1.qlogo.cn/g?b=qq&nk=$qqNumber&s=100';
  }

  /// 处理登录
  Future<void> _handleLogin(BuildContext context) async {
    print('👤 [UserCard] 打开登录页面...');
    final result = await showAuthDialog(context);

    print('👤 [UserCard] 登录页面返回，结果: $result');

    if (result == true && _authFacade.isLoggedIn) {
      print('👤 [UserCard] 登录成功，开始获取IP归属地...');
      LocationService().fetchLocation();
    }
  }

  /// 处理退出登录
  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              _authFacade.logout();
              LocationService().clearLocation();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已退出登录')),
              );
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }

  // ==================== Cupertino UI 版本 ====================

  /// 构建登录卡片 - Cupertino UI 版本
  Widget _buildLoginCardCupertino(BuildContext context) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _handleLogin(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: CupertinoColors.systemGrey4,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.person_fill, size: 36, color: CupertinoColors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '登录到 Cyrene',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: CupertinoColors.label.resolveFrom(context),
                      fontFamily: '.SF Pro Text',
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录以同步数据',
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      fontFamily: '.SF Pro Text',
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, color: CupertinoColors.systemGrey3),
          ],
        ),
      ),
    );
  }

  /// 构建用户信息卡片 - Cupertino UI 版本
  Widget _buildUserInfoCardCupertino(BuildContext context, User user) {
    final qqNumber = _extractQQNumber(user.email);
    final avatarUrl = _getQQAvatarUrl(qqNumber);
    
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => _showCupertinoUserActions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Row(
          children: [
            // 头像
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(avatarUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
                color: avatarUrl == null ? CupertinoColors.systemBlue : null,
              ),
              child: avatarUrl == null
                  ? const Icon(CupertinoIcons.person_fill, size: 32, color: CupertinoColors.white)
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 用户名
                  Row(
                    children: [
                      Text(
                        user.username,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.label.resolveFrom(context),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                  if (user.displayEmail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      user.displayEmail!,
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                        decoration: TextDecoration.none,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_forward, color: CupertinoColors.systemGrey3),
          ],
        ),
      ),
    );
  }

  /// 显示 Cupertino 用户操作菜单
  void _showCupertinoUserActions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _showUpdateUsernameDialogCupertino(context);
            },
            child: const Text('修改用户名'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              LocationService().fetchLocation();
            },
            child: const Text('刷新位置信息'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () {
             Navigator.pop(context);
             _handleLogoutCupertino(context);
          },
          child: const Text('退出登录'),
        ),
      ),
    );
  }

  /// 退出登录确认 - Cupertino
  void _handleLogoutCupertino(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              _authFacade.logout();
              LocationService().clearLocation();
              Navigator.pop(context);
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
  
  /// 修改用户名对话框 - Cupertino
  void _showUpdateUsernameDialogCupertino(BuildContext context) {
    final currentUser = _authFacade.currentUser;
    if (currentUser == null) return;
    
    _usernameController.text = currentUser.username;
    
    showCupertinoDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => CupertinoAlertDialog(
          title: const Text('修改用户名'),
          content: Container(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            constraints: const BoxConstraints(minHeight: 80),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoTextField(
                  controller: _usernameController,
                  placeholder: '2-20位，中文/字母/数字/下划线',
                  autofocus: true,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                ),
              ],
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () async {
                final newUsername = _usernameController.text.trim();
                if (newUsername.isEmpty || newUsername == currentUser.username) return;
                
                final result = await _authFacade.updateUsername(newUsername);
                if (result['success'] == true && mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Fluent UI 版本 ====================

  /// 构建登录卡片 - Fluent UI 版本
  Widget _buildLoginCardFluent(BuildContext context) {
    return fluent_ui.Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFF0078D4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                fluent_ui.FluentIcons.contact,
                size: 32,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '未登录',
                    style: fluent_ui.FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录后可享受更多功能',
                    style: fluent_ui.FluentTheme.of(context).typography.caption,
                  ),
                ],
              ),
            ),
            fluent_ui.FilledButton(
              onPressed: () => _handleLogin(context),
              child: const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建用户信息卡片 - Fluent UI 版本
  Widget _buildUserInfoCardFluent(BuildContext context, User user) {
    // 优先使用服务器返回的头像 URL（如 Linux Do 用户），否则尝试从 QQ 邮箱生成
    final qqNumber = _extractQQNumber(user.email);
    final avatarUrl = user.avatarUrl ?? _getQQAvatarUrl(qqNumber);
    final isLinuxDoAvatar = avatarUrl != null && avatarUrl.contains('linux.do');
    
    print('🖼️ [UserCard-Fluent] user.avatarUrl: ${user.avatarUrl}');
    print('🖼️ [UserCard-Fluent] 最终使用的 avatarUrl: $avatarUrl');
    print('🖼️ [UserCard-Fluent] 是否为 Linux Do 头像: $isLinuxDoAvatar');
    
    return AnimatedBuilder(
      animation: LocationService(),
      builder: (context, child) {
        final location = LocationService().currentLocation;
        final isLoadingLocation = LocationService().isLoading;
        
        return fluent_ui.Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                // 用户头像
                ClipOval(
                  child: Container(
                    width: 60,
                    height: 60,
                    color: const Color(0xFF0078D4),
                    child: isLinuxDoAvatar
                        ? _LinuxDoAvatarWidget(
                            url: avatarUrl!,
                            userId: user.id,
                          )
                        : avatarUrl != null
                            ? Image.network(
                                avatarUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    fluent_ui.FluentIcons.contact,
                                    size: 32,
                                    color: Colors.white,
                                  );
                                },
                              )
                            : const Icon(
                                fluent_ui.FluentIcons.contact,
                                size: 32,
                                color: Colors.white,
                              ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名 + 编辑图标
                      Row(
                        children: [
                          Text(
                            user.username,
                            style: fluent_ui.FluentTheme.of(context).typography.subtitle,
                          ),
                          const SizedBox(width: 4),
                          fluent_ui.IconButton(
                            icon: const Icon(fluent_ui.FluentIcons.edit, size: 14),
                            onPressed: () => _showUpdateUsernameDialogFluent(context),
                          ),
                        ],
                      ),
                      if (user.displayEmail != null) ...[
                        const SizedBox(height: 4),
                        // 邮箱
                        Row(
                          children: [
                            const Icon(
                              fluent_ui.FluentIcons.mail,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                user.displayEmail!,
                                style: fluent_ui.FluentTheme.of(context).typography.caption,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 2),
                      // IP 归属地
                      Row(
                        children: [
                          const Icon(
                            fluent_ui.FluentIcons.location,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          if (isLoadingLocation)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: fluent_ui.ProgressRing(strokeWidth: 2),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '获取中...',
                                  style: fluent_ui.FluentTheme.of(context).typography.caption,
                                ),
                              ],
                            )
                          else if (location != null)
                            Expanded(
                              child: Text(
                                location.shortDescription,
                                style: fluent_ui.FluentTheme.of(context).typography.caption,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )
                          else
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    '获取失败',
                                    style: fluent_ui.FluentTheme.of(context).typography.caption?.copyWith(
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  fluent_ui.IconButton(
                                    icon: const Icon(fluent_ui.FluentIcons.refresh, size: 14),
                                    onPressed: () {
                                      print('🔄 [UserCard] 手动刷新IP归属地...');
                                      LocationService().fetchLocation();
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                fluent_ui.IconButton(
                  icon: const Icon(fluent_ui.FluentIcons.sign_out),
                  onPressed: () => _handleLogoutFluent(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 处理退出登录 - Fluent UI 版本
  void _handleLogoutFluent(BuildContext context) {
    fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent_ui.FilledButton(
            onPressed: () {
              _authFacade.logout();
              LocationService().clearLocation();
              Navigator.pop(context);
            },
            child: const Text('退出'),
          ),
        ],
      ),
    );
  }
}


/// Linux Do 头像组件
/// 
/// 使用 WebView 服务获取头像，绕过 Cloudflare 保护
class _LinuxDoAvatarWidget extends StatefulWidget {
  final String url;
  final int userId;

  const _LinuxDoAvatarWidget({
    required this.url,
    required this.userId,
  });

  @override
  State<_LinuxDoAvatarWidget> createState() => _LinuxDoAvatarWidgetState();
}

class _LinuxDoAvatarWidgetState extends State<_LinuxDoAvatarWidget> {
  Uint8List? _avatarData;
  bool _isLoading = true;
  bool _hasFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
  }

  @override
  void didUpdateWidget(_LinuxDoAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _loadAvatar();
    }
  }

  Future<void> _loadAvatar() async {
    setState(() {
      _isLoading = true;
      _hasFailed = false;
    });

    try {
      final data = await AvatarFetchService().fetchAvatar(
        widget.url,
        cacheKey: 'linuxdo_${widget.userId}',
      );

      if (mounted) {
        setState(() {
          _avatarData = data;
          _isLoading = false;
          _hasFailed = data == null;
        });
      }
    } catch (e) {
      print('❌ [LinuxDoAvatar] 加载失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: fluent_ui.ProgressRing(strokeWidth: 2),
        ),
      );
    }

    if (_hasFailed || _avatarData == null) {
      return const Icon(
        fluent_ui.FluentIcons.contact,
        size: 32,
        color: Colors.white,
      );
    }

    return Image.memory(
      _avatarData!,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(
          fluent_ui.FluentIcons.contact,
          size: 32,
          color: Colors.white,
        );
      },
    );
  }
}
