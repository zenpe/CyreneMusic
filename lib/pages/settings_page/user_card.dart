import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../services/auth_service.dart';
import '../../services/location_service.dart';
import '../../services/donate_service.dart';
import '../../utils/theme_manager.dart';
import '../auth/auth_page.dart';
import '../auth/qr_login_dialog.dart';
import '../auth/qr_login_scan_page.dart';

/// 用户卡片组件
class UserCard extends StatefulWidget {
  const UserCard({super.key});

  @override
  State<UserCard> createState() => _UserCardState();
}

class _UserCardState extends State<UserCard> {
  bool _isSponsor = false;
  int? _sponsorRank; // 赞助排名：1=金牌，2=银牌，3=铜牌，其他=赞助用户
  bool _loadingSponsorStatus = false;
  final TextEditingController _usernameController = TextEditingController();
  bool _isUpdatingUsername = false;
  String? _usernameError;

  @override
  void initState() {
    super.initState();
    AuthService().addListener(_onAuthChanged);
    LocationService().addListener(_onLocationChanged);
    _checkSponsorStatus();
  }

  /// 在 Fluent UI 中以 ContentDialog 方式显示登录界面
  Future<bool?> _showLoginDialogFluent(BuildContext context) async {
    // 控制器与状态
    // 登录
    final loginAccountController = TextEditingController();
    final loginPasswordController = TextEditingController();
    bool loginLoading = false;
    String? loginError;

    // 注册
    final regQqController = TextEditingController();
    final regUsernameController = TextEditingController();
    final regPasswordController = TextEditingController();
    final regConfirmController = TextEditingController();
    final regCodeController = TextEditingController();
    bool regLoading = false;
    String? regError;
    bool regCodeSent = false;
    int regCountdown = 0;
    Timer? regTimer;

    // 找回密码
    final fpEmailController = TextEditingController();
    final fpCodeController = TextEditingController();
    final fpPasswordController = TextEditingController();
    final fpConfirmController = TextEditingController();
    bool fpLoading = false;
    String? fpError;
    bool fpCodeSent = false;
    int fpCountdown = 0;
    Timer? fpTimer;

    int tabIndex = 0; // 0 登录, 1 注册, 2 找回

    // 注册状态
    bool regEnabled = true;
    bool checkingReg = true;
    bool firstLoad = true;

    void cleanup() {
      regTimer?.cancel();
      fpTimer?.cancel();
      loginAccountController.dispose();
      loginPasswordController.dispose();
      regQqController.dispose();
      regUsernameController.dispose();
      regPasswordController.dispose();
      regConfirmController.dispose();
      regCodeController.dispose();
      fpEmailController.dispose();
      fpCodeController.dispose();
      fpPasswordController.dispose();
      fpConfirmController.dispose();
    }

    String _regEmail() => '${regQqController.text.trim()}@qq.com';

    return fluent_ui.showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          if (firstLoad) {
            firstLoad = false;
            AuthService().checkRegistrationStatus().then((result) {
              if (context.mounted) {
                setState(() {
                  regEnabled = result['enabled'] ?? false;
                  checkingReg = false;
                });
              }
            });
          }

          return fluent_ui.ContentDialog(
            title: SizedBox(
              width: 520,
              child: _buildCapsuleTabs(
                context,
                tabIndex,
                (i) => setState(() => tabIndex = i),
              ),
            ),
            content: SizedBox(
              width: 560,
              height: 480,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: SingleChildScrollView(
                  child: () {
                    switch (tabIndex) {
                      case 0:
                        return _buildLoginView(
                          context,
                          errorText: loginError,
                          accountController: loginAccountController,
                          passwordController: loginPasswordController,
                          loading: loginLoading,
                          onCleanup: cleanup,
                          onSubmit: () async {
                            setState(() {
                              loginLoading = true;
                              loginError = null;
                            });
                            final result = await AuthService().login(
                              account: loginAccountController.text.trim(),
                              password: loginPasswordController.text,
                            );
                            setState(() => loginLoading = false);
                            if (result['success'] == true) {
                              cleanup();
                              Navigator.pop(context, true);
                            } else {
                              setState(() {
                                loginError = result['message']?.toString() ?? '登录失败';
                              });
                            }
                          },
                          toRegister: () => setState(() => tabIndex = 1),
                          toForgot: () => setState(() => tabIndex = 2),
                        );
                      case 1:
                        return _buildRegisterView(
                          context,
                          regEnabled: regEnabled,
                          checkingReg: checkingReg,
                          errorText: regError,
                        qqController: regQqController,
                        usernameController: regUsernameController,
                        passwordController: regPasswordController,
                        confirmController: regConfirmController,
                        codeController: regCodeController,
                        loading: regLoading,
                        codeSent: regCodeSent,
                        countdown: regCountdown,
                        onSendCode: () async {
                          if (regQqController.text.trim().isEmpty || regUsernameController.text.trim().isEmpty) {
                            setState(() => regError = '请先填写 QQ 号和用户名');
                            return;
                          }
                          setState(() {
                            regError = null;
                            regLoading = true;
                          });
                          final result = await AuthService().sendRegisterCode(
                            email: _regEmail(),
                            username: regUsernameController.text.trim(),
                          );
                          setState(() => regLoading = false);
                          if (result['success'] == true) {
                            setState(() {
                              regCodeSent = true;
                              regCountdown = 60;
                            });
                            regTimer?.cancel();
                            regTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                              if (regCountdown <= 1) {
                                t.cancel();
                                setState(() => regCodeSent = false);
                              } else {
                                setState(() => regCountdown -= 1);
                              }
                            });
                          } else {
                            setState(() => regError = result['message']?.toString() ?? '发送验证码失败');
                          }
                        },
                        onSubmit: () async {
                          if (regPasswordController.text != regConfirmController.text) {
                            setState(() => regError = '两次密码不一致');
                            return;
                          }
                          if (regCodeController.text.trim().isEmpty) {
                            setState(() => regError = '请输入验证码');
                            return;
                          }
                          setState(() {
                            regError = null;
                            regLoading = true;
                          });
                          final result = await AuthService().register(
                            email: _regEmail(),
                            username: regUsernameController.text.trim(),
                            password: regPasswordController.text,
                            code: regCodeController.text.trim(),
                          );
                          setState(() => regLoading = false);
                          if (result['success'] == true) {
                            cleanup();
                            Navigator.pop(context, true);
                          } else {
                            setState(() => regError = result['message']?.toString() ?? '注册失败');
                          }
                        },
                      );
                  case 2:
                  default:
                    return _buildForgotView(
                      context,
                      errorText: fpError,
                      emailController: fpEmailController,
                      codeController: fpCodeController,
                      passwordController: fpPasswordController,
                      confirmController: fpConfirmController,
                      loading: fpLoading,
                      codeSent: fpCodeSent,
                      countdown: fpCountdown,
                      onSendCode: () async {
                        if (fpEmailController.text.trim().isEmpty) {
                          setState(() => fpError = '请输入邮箱');
                          return;
                        }
                        setState(() {
                          fpError = null;
                          fpLoading = true;
                        });
                        final result = await AuthService().sendResetCode(
                          email: fpEmailController.text.trim(),
                        );
                        setState(() => fpLoading = false);
                        if (result['success'] == true) {
                          setState(() {
                            fpCodeSent = true;
                            fpCountdown = 60;
                          });
                          fpTimer?.cancel();
                          fpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                            if (fpCountdown <= 1) {
                              t.cancel();
                              setState(() => fpCodeSent = false);
                            } else {
                              setState(() => fpCountdown -= 1);
                            }
                          });
                        } else {
                          setState(() => fpError = result['message']?.toString() ?? '发送验证码失败');
                        }
                      },
                      onSubmit: () async {
                        if (fpPasswordController.text != fpConfirmController.text) {
                          setState(() => fpError = '两次密码不一致');
                          return;
                        }
                        if (fpCodeController.text.trim().isEmpty) {
                          setState(() => fpError = '请输入验证码');
                          return;
                        }
                        setState(() {
                          fpError = null;
                          fpLoading = true;
                        });
                        final result = await AuthService().resetPassword(
                          email: fpEmailController.text.trim(),
                          code: fpCodeController.text.trim(),
                          newPassword: fpPasswordController.text,
                        );
                        setState(() => fpLoading = false);
                        if (result['success'] == true) {
                          cleanup();
                          Navigator.pop(context, true);
                        } else {
                          setState(() => fpError = result['message']?.toString() ?? '重置密码失败');
                        }
                      },
                    );
                    }
                  }(),
                ),
              ),
            ),
            actions: [
              fluent_ui.Button(
                onPressed: () {
                  cleanup();
                  Navigator.pop(context, false);
                },
                child: const Text('关闭'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 胶囊状选项卡（Login / Register / Forgot），丝滑动画
  Widget _buildCapsuleTabs(BuildContext context, int current, ValueChanged<int> onChanged) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color bg = (isDark ? Colors.white : Colors.black).withOpacity(0.06);
    final Color border = (isDark ? Colors.white : Colors.black).withOpacity(0.08);

    final labels = const ['登录', '注册', '找回密码'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final itemCount = labels.length;
        final innerPadding = 4.0; // 2 px 左右内边距总计
        final itemWidth = (totalWidth - innerPadding) / itemCount;

        return Container(
          height: 40,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // 滑动的胶囊指示器
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left: (current.clamp(0, itemCount - 1)) * itemWidth,
                width: itemWidth,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              // 标签文本点击区域
              Row(
                children: List.generate(itemCount, (i) {
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: i == current ? primary : onSurface,
                          ),
                          child: Text(labels[i]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoginView(
    BuildContext context, {
    required String? errorText,
    required TextEditingController accountController,
    required TextEditingController passwordController,
    required bool loading,
    required VoidCallback onCleanup,
    required Future<void> Function() onSubmit,
    required VoidCallback toRegister,
    required VoidCallback toForgot,
  }) {
    final typo = fluent_ui.FluentTheme.of(context).typography;
    return fluent_ui.Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(fluent_ui.FluentIcons.contact, size: 18),
              const SizedBox(width: 8),
              Text('登录到 Cyrene', style: typo.subtitle),
            ],
          ),
          const SizedBox(height: 12),
          if (errorText != null) ...[
            fluent_ui.InfoBar(
              title: const Text('错误'),
              content: Text(errorText),
              severity: fluent_ui.InfoBarSeverity.error,
            ),
            const SizedBox(height: 8),
          ],
          fluent_ui.InfoLabel(
            label: '账号',
            child: fluent_ui.TextBox(
              controller: accountController,
              placeholder: '邮箱 / 用户名',
              prefix: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(fluent_ui.FluentIcons.contact),
              ),
              prefixMode: fluent_ui.OverlayVisibilityMode.always,
            ),
          ),
          const SizedBox(height: 12),
          fluent_ui.InfoLabel(
            label: '密码',
            child: fluent_ui.PasswordBox(
              controller: passwordController,
              placeholder: '输入密码',
              onSubmitted: (_) => onSubmit(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    fluent_ui.HyperlinkButton(child: const Text('去注册'), onPressed: toRegister),
                    const SizedBox(height: 2),
                    fluent_ui.HyperlinkButton(child: const Text('忘记密码'), onPressed: toForgot),
                    const SizedBox(height: 2),
                    fluent_ui.HyperlinkButton(
                      child: const Text('Linux Do 登录'),
                      onPressed: loading
                          ? null
                          : () async {
                              final result = await AuthService().loginWithLinuxDo();
                              if (result['success'] == true && context.mounted) {
                                onCleanup();
                                Navigator.pop(context, true);
                              } else if (result['success'] == false && context.mounted) {
                                // 可以通过回调处理错误，或者在这里显示提示
                              }
                            },
                    ),
                    const SizedBox(height: 2),
                    fluent_ui.HyperlinkButton(
                      child: const Text('手机扫码登录'),
                      onPressed: () async {
                        final ok = await showQrLoginDialog(context);
                        if (ok == true) {
                          onCleanup();
                          if (context.mounted) {
                            Navigator.pop(context, true);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              fluent_ui.FilledButton(
                onPressed: loading ? null : onSubmit,
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: fluent_ui.ProgressRing(strokeWidth: 2))
                    : const Text('登录'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterView(
    BuildContext context, {
    required bool regEnabled,
    required bool checkingReg,
    required String? errorText,
    required TextEditingController qqController,
    required TextEditingController usernameController,
    required TextEditingController passwordController,
    required TextEditingController confirmController,
    required TextEditingController codeController,
    required bool loading,
    required bool codeSent,
    required int countdown,
    required Future<void> Function() onSendCode,
    required Future<void> Function() onSubmit,
  }) {
    final typo = fluent_ui.FluentTheme.of(context).typography;

    if (checkingReg) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: fluent_ui.ProgressRing(),
        ),
      );
    }

    if (!regEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              fluent_ui.FluentIcons.block_contact,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 24),
            Text(
              '因滥用，我们暂时关闭了公开注册！',
              textAlign: TextAlign.center,
              style: typo.subtitle?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return fluent_ui.Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('register'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(fluent_ui.FluentIcons.add_friend, size: 18),
              const SizedBox(width: 8),
              Text('创建账户', style: typo.subtitle),
            ],
          ),
          const SizedBox(height: 12),
          if (errorText != null) ...[
            fluent_ui.InfoBar(
              title: const Text('错误'),
              content: Text(errorText),
              severity: fluent_ui.InfoBarSeverity.error,
            ),
            const SizedBox(height: 8),
          ],
          fluent_ui.InfoLabel(
            label: 'QQ 号',
            child: fluent_ui.TextBox(
              controller: qqController,
              placeholder: '用于生成邮箱（QQ号@qq.com）',
              prefix: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(fluent_ui.FluentIcons.mail),
              ),
              prefixMode: fluent_ui.OverlayVisibilityMode.always,
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '用户名',
            child: fluent_ui.TextBox(
              controller: usernameController,
              placeholder: '2-20位，支持中文、字母、数字、下划线',
              prefix: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(fluent_ui.FluentIcons.contact),
              ),
              prefixMode: fluent_ui.OverlayVisibilityMode.always,
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '密码',
            child: fluent_ui.PasswordBox(
              controller: passwordController,
              placeholder: '至少 8 位',
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '确认密码',
            child: fluent_ui.PasswordBox(
              controller: confirmController,
              placeholder: '再次输入密码',
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '验证码',
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: fluent_ui.TextBox(
                    controller: codeController,
                    placeholder: '邮件验证码',
                    prefix: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(fluent_ui.FluentIcons.shield),
                    ),
                    prefixMode: fluent_ui.OverlayVisibilityMode.always,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: fluent_ui.FilledButton(
                    onPressed: (codeSent || loading) ? null : onSendCode,
                    child: loading
                        ? const SizedBox(width: 18, height: 18, child: fluent_ui.ProgressRing(strokeWidth: 2))
                        : Text(codeSent ? '${countdown}秒' : '发送'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              fluent_ui.FilledButton(
                onPressed: loading ? null : onSubmit,
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: fluent_ui.ProgressRing(strokeWidth: 2))
                    : const Text('注册'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForgotView(
    BuildContext context, {
    required String? errorText,
    required TextEditingController emailController,
    required TextEditingController codeController,
    required TextEditingController passwordController,
    required TextEditingController confirmController,
    required bool loading,
    required bool codeSent,
    required int countdown,
    required Future<void> Function() onSendCode,
    required Future<void> Function() onSubmit,
  }) {
    final typo = fluent_ui.FluentTheme.of(context).typography;
    return fluent_ui.Card(
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const ValueKey('forgot'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(fluent_ui.FluentIcons.lock, size: 18),
              const SizedBox(width: 8),
              Text('重置密码', style: typo.subtitle),
            ],
          ),
          const SizedBox(height: 12),
          if (errorText != null) ...[
            fluent_ui.InfoBar(
              title: const Text('错误'),
              content: Text(errorText),
              severity: fluent_ui.InfoBarSeverity.error,
            ),
            const SizedBox(height: 8),
          ],
          fluent_ui.InfoLabel(
            label: '注册邮箱',
            child: fluent_ui.TextBox(
              controller: emailController,
              placeholder: '例如 yourname@example.com',
              prefix: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(fluent_ui.FluentIcons.mail),
              ),
              prefixMode: fluent_ui.OverlayVisibilityMode.always,
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '验证码',
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: fluent_ui.TextBox(
                    controller: codeController,
                    placeholder: '邮件验证码',
                    prefix: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(fluent_ui.FluentIcons.shield),
                    ),
                    prefixMode: fluent_ui.OverlayVisibilityMode.always,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: fluent_ui.FilledButton(
                    onPressed: (codeSent || loading) ? null : onSendCode,
                    child: loading
                        ? const SizedBox(width: 18, height: 18, child: fluent_ui.ProgressRing(strokeWidth: 2))
                        : Text(codeSent ? '${countdown}秒' : '发送'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '新密码',
            child: fluent_ui.PasswordBox(
              controller: passwordController,
              placeholder: '至少 8 位',
            ),
          ),
          const SizedBox(height: 8),
          fluent_ui.InfoLabel(
            label: '确认新密码',
            child: fluent_ui.PasswordBox(
              controller: confirmController,
              placeholder: '再次输入密码',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Spacer(),
              fluent_ui.FilledButton(
                onPressed: loading ? null : onSubmit,
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: fluent_ui.ProgressRing(strokeWidth: 2))
                    : const Text('重置密码'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    AuthService().removeListener(_onAuthChanged);
    LocationService().removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
      _checkSponsorStatus(); // 登录状态变化时重新查询赞助状态
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
    final currentUser = AuthService().currentUser;
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

                      final result = await AuthService().updateUsername(newUsername);

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
    final currentUser = AuthService().currentUser;
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

                      final result = await AuthService().updateUsername(newUsername);

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

  /// 查询用户赞助状态
  Future<void> _checkSponsorStatus() async {
    final user = AuthService().currentUser;
    if (user == null) {
      setState(() {
        _isSponsor = false;
        _sponsorRank = null;
        _loadingSponsorStatus = false;
      });
      return;
    }

    setState(() => _loadingSponsorStatus = true);

    try {
      final result = await DonateService.getSponsorStatus(userId: user.id);
      if (result['code'] == 200 && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        setState(() {
          _isSponsor = data['isSponsor'] == true;
          _sponsorRank = data['sponsorRank'] as int?;
          _loadingSponsorStatus = false;
        });
        print('[UserCard] 赞助状态: $_isSponsor, 排名: $_sponsorRank');
      } else {
        setState(() {
          _isSponsor = false;
          _sponsorRank = null;
          _loadingSponsorStatus = false;
        });
      }
    } catch (e) {
      print('[UserCard] 查询赞助状态失败: $e');
      setState(() {
        _isSponsor = false;
        _sponsorRank = null;
        _loadingSponsorStatus = false;
      });
    }
  }

  /// 获取赞助标识文字
  String _getSponsorBadgeText() {
    if (_sponsorRank == 1) return '金牌赞助';
    if (_sponsorRank == 2) return '银牌赞助';
    if (_sponsorRank == 3) return '铜牌赞助';
    return '赞助用户';
  }

  /// 获取赞助标识渐变色
  List<Color> _getSponsorBadgeColors() {
    if (_sponsorRank == 1) return [const Color(0xFFFFD700), const Color(0xFFFFA500)]; // 金
    if (_sponsorRank == 2) return [const Color(0xFFC0C0C0), const Color(0xFF808080)]; // 银
    if (_sponsorRank == 3) return [const Color(0xFFCD7F32), const Color(0xFF8B4513)]; // 铜
    return [const Color(0xFF6366F1), const Color(0xFF8B5CF6)]; // 紫色（普通赞助用户）
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = AuthService().isLoggedIn;
    final user = AuthService().currentUser;
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
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

  /// 构建登录卡片（未登录状态）
  Widget _buildLoginCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录后可享受更多功能',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    final qqNumber = _extractQQNumber(user.email);
    final avatarUrl = _getQQAvatarUrl(qqNumber);
    
    return AnimatedBuilder(
      animation: LocationService(),
      builder: (context, child) {
        final location = LocationService().currentLocation;
        final isLoadingLocation = LocationService().isLoading;
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // QQ 头像
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: colorScheme.primaryContainer,
                      backgroundImage: avatarUrl != null 
                          ? NetworkImage(avatarUrl) 
                          : null,
                      child: avatarUrl == null 
                          ? Icon(
                              Icons.person,
                              size: 32,
                              color: colorScheme.onPrimaryContainer,
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 用户名 + 编辑图标 + 赞助角标
                          Row(
                            children: [
                              Text(
                                user.username,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                              if (_isSponsor) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _getSponsorBadgeColors(),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.workspace_premium,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _getSponsorBadgeText(),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
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
                                  user.email,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
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
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                )
                              else if (location != null)
                                Expanded(
                                  child: Text(
                                    location.shortDescription,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    IconButton(
                      onPressed: () => _handleLogout(context),
                      icon: const Icon(Icons.logout),
                      tooltip: '退出登录',
                    ),
                  ],
                ),
                if (Platform.isAndroid || Platform.isIOS) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => openQrLoginScanPage(context),
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      label: const Text('扫码登录桌面端'),
                    ),
                  ),
                ],
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

    // 在 Windows + Fluent UI 框架下，使用 Fluent 风格对话框承载登录
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;
    bool? result;
    if (isFluentUI) {
      result = await _showLoginDialogFluent(context);
    } else {
      result = await showAuthDialog(context);
    }

    print('👤 [UserCard] 登录页面返回，结果: $result');

    if (result == true && AuthService().isLoggedIn) {
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
              AuthService().logout();
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
                  // 用户名 + 赞助
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
                      if (_isSponsor) ...[
                        const SizedBox(width: 6),
                        const Icon(CupertinoIcons.checkmark_seal_fill, size: 16, color: CupertinoColors.systemYellow),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 15,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      decoration: TextDecoration.none,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

  /// 显示 Cupertino 用户操作菜单
  void _showCupertinoUserActions(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          if (Platform.isAndroid || Platform.isIOS)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(context);
                await openQrLoginScanPage(context);
              },
              child: const Text('扫码登录桌面端'),
            ),
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
              AuthService().logout();
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
    final currentUser = AuthService().currentUser;
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
                
                final result = await AuthService().updateUsername(newUsername);
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
    final qqNumber = _extractQQNumber(user.email);
    final avatarUrl = _getQQAvatarUrl(qqNumber);
    
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
                // QQ 头像
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
                    color: avatarUrl == null ? const Color(0xFF0078D4) : null,
                  ),
                  child: avatarUrl == null
                      ? const Icon(
                          fluent_ui.FluentIcons.contact,
                          size: 32,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名 + 编辑图标 + 赞助角标
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
                          if (_isSponsor) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _getSponsorBadgeColors(),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    fluent_ui.FluentIcons.trophy2,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getSponsorBadgeText(),
                                    style: fluent_ui.FluentTheme.of(context).typography.caption?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
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
                              user.email,
                              style: fluent_ui.FluentTheme.of(context).typography.caption,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
              AuthService().logout();
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

