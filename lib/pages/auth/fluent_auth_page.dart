import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../services/auth_service.dart';
import 'qr_login_dialog.dart';
import 'linuxdo_webview_login_page.dart';

/// 桌面端 Fluent UI 风格认证页面
/// 
/// 包含登录、注册、找回密码三个 Tab
/// 支持账号密码登录、Linux Do 授权登录、手机扫码登录
class FluentAuthPage extends StatefulWidget {
  final int initialTab;
  
  const FluentAuthPage({super.key, this.initialTab = 0});

  @override
  State<FluentAuthPage> createState() => _FluentAuthPageState();
}

class _FluentAuthPageState extends State<FluentAuthPage> {
  late int _selectedTab;
  
  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo 和标题
          _buildHeader(theme),
          const SizedBox(height: 32),
          
          // Tab 选择器
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTabButton(theme, 0, '登录'),
              const SizedBox(width: 8),
              _buildTabButton(theme, 1, '注册'),
              const SizedBox(width: 8),
              _buildTabButton(theme, 2, '找回密码'),
            ],
          ),
          const SizedBox(height: 24),
          
          // Tab 内容
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTabButton(fluent.FluentThemeData theme, int index, String label) {
    final isSelected = _selectedTab == index;
    return fluent.Button(
      style: fluent.ButtonStyle(
        backgroundColor: fluent.WidgetStateProperty.all(
          isSelected ? theme.accentColor : Colors.transparent,
        ),
      ),
      onPressed: () => setState(() => _selectedTab = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader(fluent.FluentThemeData theme) {
    return Column(
      children: [
        // Logo
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: theme.accentColor.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: ClipOval(
              child: Image.asset(
                'assets/icons/new_ico.png',
                width: 50,
                height: 50,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // 标题
        Text(
          'Cyrene Music',
          style: theme.typography.title?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '发现美好音乐',
          style: theme.typography.body?.copyWith(
            color: theme.brightness == Brightness.dark 
                ? Colors.white70 
                : Colors.black54,
          ),
        ),
      ],
    );
  }
  
  Widget _buildTabContent() {
    switch (_selectedTab) {
      case 0:
        return _FluentLoginView(key: const ValueKey('login'));
      case 1:
        return _FluentRegisterView(key: const ValueKey('register'));
      case 2:
        return _FluentForgotPasswordView(key: const ValueKey('forgot'));
      default:
        return _FluentLoginView(key: const ValueKey('login'));
    }
  }
}

/// Fluent UI 登录视图
class _FluentLoginView extends StatefulWidget {
  const _FluentLoginView({super.key});

  @override
  State<_FluentLoginView> createState() => _FluentLoginViewState();
}

class _FluentLoginViewState extends State<_FluentLoginView> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLinuxDoLoading = false;
  String _linuxDoLoadingText = '正在授权...';
  bool _obscurePassword = true;
  bool _linuxDoEnabled = true;

  @override
  void initState() {
    super.initState();
    _checkLinuxDoStatus();
  }

  Future<void> _checkLinuxDoStatus() async {
    final result = await AuthService().checkLinuxDoStatus();
    if (mounted) {
      setState(() {
        _linuxDoEnabled = result['enabled'] ?? true;
      });
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_accountController.text.trim().isEmpty || 
        _passwordController.text.isEmpty) {
      _showInfoBar('请填写完整信息', fluent.InfoBarSeverity.warning);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().login(
      account: _accountController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.success);
        // 登录成功后，自动上报IP归属地
        AuthService().updateLocation();
      } else {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.error);
      }
    }
  }
  
  void _showInfoBar(String message, fluent.InfoBarSeverity severity) {
    fluent.displayInfoBar(
      context,
      builder: (context, close) => fluent.InfoBar(
        title: Text(message),
        severity: severity,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 账号输入
          fluent.InfoLabel(
            label: '邮箱 / 用户名',
            child: fluent.TextBox(
              controller: _accountController,
              placeholder: '请输入邮箱或用户名',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.contact, size: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 密码输入
          fluent.InfoLabel(
            label: '密码',
            child: fluent.TextBox(
              controller: _passwordController,
              placeholder: '请输入密码',
              obscureText: _obscurePassword,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.lock, size: 16),
              ),
              suffix: fluent.IconButton(
                icon: Icon(
                  _obscurePassword 
                      ? fluent.FluentIcons.view 
                      : fluent.FluentIcons.hide3,
                  size: 16,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              onSubmitted: (_) => _handleLogin(),
            ),
          ),
          const SizedBox(height: 24),
          
          // 登录按钮
          fluent.FilledButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('登录', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
          ),
          
          // Linux Do 授权登录
          if (_linuxDoEnabled) ...[
            const SizedBox(height: 12),
            fluent.Button(
              onPressed: (_isLoading || _isLinuxDoLoading) ? null : _handleLinuxDoLogin,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isLinuxDoLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: fluent.ProgressRing(strokeWidth: 2),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(fluent.FluentIcons.comment, size: 16),
                    ),
                  Text(_isLinuxDoLoading ? _linuxDoLoadingText : '通过 Linux Do 授权'),
                ],
              ),
            ),
          ],
          
          // 手机扫码登录
          const SizedBox(height: 12),
          fluent.Button(
            onPressed: _isLoading ? null : () async {
              final ok = await showQrLoginDialog(context);
              if (ok == true && mounted) {
                _showInfoBar('登录成功', fluent.InfoBarSeverity.success);
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(fluent.FluentIcons.q_r_code, size: 16),
                ),
                Text('手机扫码登录'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          Center(
            child: Text(
              '第一次使用？切换到注册标签页创建账号',
              style: theme.typography.caption?.copyWith(
                color: theme.brightness == Brightness.dark 
                    ? Colors.white54 
                    : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _handleLinuxDoLogin() async {
    setState(() {
      _isLinuxDoLoading = true;
      _linuxDoLoadingText = '正在打开授权页面...';
    });
    
    // 使用 WebView 方式进行登录
    final code = await showLinuxDoWebViewLogin(context);
    
    if (!mounted) return;
    
    if (code == null) {
      // 用户取消或获取授权码失败
      setState(() => _isLinuxDoLoading = false);
      return;
    }
    
    // 获取到授权码，进行登录
    setState(() => _linuxDoLoadingText = '正在验证授权...');
    
    final result = await AuthService().loginWithLinuxDoCode(code);
    
    if (!mounted) return;
    
    if (result['success'] == true) {
      setState(() => _linuxDoLoadingText = '授权成功，正在登录...');
      AuthService().updateLocation();
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _isLinuxDoLoading = false);
        _showInfoBar('登录成功', fluent.InfoBarSeverity.success);
      }
    } else {
      setState(() => _isLinuxDoLoading = false);
      _showInfoBar(result['message'] ?? '授权失败', fluent.InfoBarSeverity.error);
    }
  }
}

/// Fluent UI 注册视图
class _FluentRegisterView extends StatefulWidget {
  const _FluentRegisterView({super.key});

  @override
  State<_FluentRegisterView> createState() => _FluentRegisterViewState();
}

class _FluentRegisterViewState extends State<_FluentRegisterView> {
  final _qqNumberController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _codeController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _codeSent = false;
  int _countdown = 0;
  Timer? _timer;
  bool _registrationEnabled = true;
  bool _checkingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkRegistrationStatus();
  }

  @override
  void dispose() {
    _qqNumberController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkRegistrationStatus() async {
    final result = await AuthService().checkRegistrationStatus();
    if (mounted) {
      setState(() {
        _registrationEnabled = result['enabled'] ?? false;
        _checkingStatus = false;
      });
    }
  }

  String _getFullEmail() => '${_qqNumberController.text.trim()}@qq.com';

  void _startCountdown() {
    setState(() {
      _countdown = 60;
      _codeSent = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _codeSent = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    if (_qqNumberController.text.trim().isEmpty || 
        _usernameController.text.trim().isEmpty) {
      _showInfoBar('请先填写 QQ 号和用户名', fluent.InfoBarSeverity.warning);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().sendRegisterCode(
      email: _getFullEmail(),
      username: _usernameController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.success);
        _startCountdown();
      } else {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.error);
      }
    }
  }

  Future<void> _handleRegister() async {
    // 验证表单
    if (_qqNumberController.text.trim().isEmpty) {
      _showInfoBar('请输入 QQ 号', fluent.InfoBarSeverity.warning);
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(_qqNumberController.text.trim())) {
      _showInfoBar('QQ 号应为纯数字', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_usernameController.text.trim().isEmpty) {
      _showInfoBar('请输入用户名', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_passwordController.text.isEmpty || _passwordController.text.length < 8) {
      _showInfoBar('密码至少8个字符', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showInfoBar('两次密码不一致', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      _showInfoBar('请输入验证码', fluent.InfoBarSeverity.warning);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().register(
      email: _getFullEmail(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      code: _codeController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.success);
      } else {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.error);
      }
    }
  }
  
  void _showInfoBar(String message, fluent.InfoBarSeverity severity) {
    fluent.displayInfoBar(
      context,
      builder: (context, close) => fluent.InfoBar(
        title: Text(message),
        severity: severity,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    if (_checkingStatus) {
      return const Center(child: fluent.ProgressRing());
    }

    if (!_registrationEnabled) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.hasBoundedHeight && constraints.maxHeight < 180;
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
                        fluent.FluentIcons.blocked2,
                        size: compact ? 52 : 64,
                        color: Colors.red,
                      ),
                      SizedBox(height: compact ? 14 : 24),
                      Text(
                        '因滥用，我们暂时关闭了公开注册！',
                        textAlign: TextAlign.center,
                        style: theme.typography.subtitle,
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

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // QQ 号输入
          fluent.InfoLabel(
            label: 'QQ 号',
            child: fluent.TextBox(
              controller: _qqNumberController,
              placeholder: '请输入 QQ 号',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.chat, size: 16),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          
          if (_qqNumberController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Text(
                '注册邮箱：${_getFullEmail()}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.accentColor,
                ),
              ),
            ),
          const SizedBox(height: 16),
          
          // 用户名
          fluent.InfoLabel(
            label: '用户名',
            child: fluent.TextBox(
              controller: _usernameController,
              placeholder: '2-20个字符，支持中文、字母、数字、下划线',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.contact, size: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 密码
          fluent.InfoLabel(
            label: '密码',
            child: fluent.TextBox(
              controller: _passwordController,
              placeholder: '至少8个字符',
              obscureText: _obscurePassword,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.lock, size: 16),
              ),
              suffix: fluent.IconButton(
                icon: Icon(
                  _obscurePassword 
                      ? fluent.FluentIcons.view 
                      : fluent.FluentIcons.hide3,
                  size: 16,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 确认密码
          fluent.InfoLabel(
            label: '确认密码',
            child: fluent.TextBox(
              controller: _confirmPasswordController,
              placeholder: '请再次输入密码',
              obscureText: _obscureConfirmPassword,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.lock, size: 16),
              ),
              suffix: fluent.IconButton(
                icon: Icon(
                  _obscureConfirmPassword 
                      ? fluent.FluentIcons.view 
                      : fluent.FluentIcons.hide3,
                  size: 16,
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 验证码
          Row(
            children: [
              Expanded(
                flex: 3,
                child: fluent.InfoLabel(
                  label: '验证码',
                  child: fluent.TextBox(
                    controller: _codeController,
                    placeholder: '请输入验证码',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(fluent.FluentIcons.shield, size: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: fluent.Button(
                  onPressed: _codeSent || _isLoading ? null : _sendCode,
                  child: Text(_codeSent ? '$_countdown秒' : '发送验证码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          
          // 注册按钮
          fluent.FilledButton(
            onPressed: _isLoading ? null : _handleRegister,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('注册', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
          ),
          
          const SizedBox(height: 12),
          Center(
            child: Text(
              '注册即表示您同意我们的服务条款和隐私政策',
              style: theme.typography.caption?.copyWith(
                color: theme.brightness == Brightness.dark 
                    ? Colors.white54 
                    : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fluent UI 找回密码视图
class _FluentForgotPasswordView extends StatefulWidget {
  const _FluentForgotPasswordView({super.key});

  @override
  State<_FluentForgotPasswordView> createState() => _FluentForgotPasswordViewState();
}

class _FluentForgotPasswordViewState extends State<_FluentForgotPasswordView> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _codeSent = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _countdown = 60;
      _codeSent = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          _codeSent = false;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    if (_emailController.text.trim().isEmpty) {
      _showInfoBar('请输入邮箱', fluent.InfoBarSeverity.warning);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().sendResetCode(
      email: _emailController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.success);
        _startCountdown();
      } else {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.error);
      }
    }
  }

  Future<void> _handleReset() async {
    // 验证表单
    if (_emailController.text.trim().isEmpty) {
      _showInfoBar('请输入邮箱', fluent.InfoBarSeverity.warning);
      return;
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(_emailController.text.trim())) {
      _showInfoBar('邮箱格式不正确', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      _showInfoBar('请输入验证码', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_passwordController.text.isEmpty || _passwordController.text.length < 8) {
      _showInfoBar('密码至少8个字符', fluent.InfoBarSeverity.warning);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showInfoBar('两次密码不一致', fluent.InfoBarSeverity.warning);
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().resetPassword(
      email: _emailController.text.trim(),
      code: _codeController.text.trim(),
      newPassword: _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.success);
      } else {
        _showInfoBar(result['message'], fluent.InfoBarSeverity.error);
      }
    }
  }
  
  void _showInfoBar(String message, fluent.InfoBarSeverity severity) {
    fluent.displayInfoBar(
      context,
      builder: (context, close) => fluent.InfoBar(
        title: Text(message),
        severity: severity,
        onClose: close,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 提示信息
          fluent.InfoBar(
            title: const Text('我们将向您的邮箱发送验证码'),
            severity: fluent.InfoBarSeverity.info,
            isLong: true,
          ),
          const SizedBox(height: 20),
          
          // 邮箱
          fluent.InfoLabel(
            label: '注册邮箱',
            child: fluent.TextBox(
              controller: _emailController,
              placeholder: '请输入注册时使用的邮箱',
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.mail, size: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 验证码
          Row(
            children: [
              Expanded(
                flex: 3,
                child: fluent.InfoLabel(
                  label: '验证码',
                  child: fluent.TextBox(
                    controller: _codeController,
                    placeholder: '请输入验证码',
                    prefix: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(fluent.FluentIcons.shield, size: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: fluent.Button(
                  onPressed: _codeSent || _isLoading ? null : _sendCode,
                  child: Text(_codeSent ? '$_countdown秒' : '发送验证码'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // 新密码
          fluent.InfoLabel(
            label: '新密码',
            child: fluent.TextBox(
              controller: _passwordController,
              placeholder: '至少8个字符',
              obscureText: _obscurePassword,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.lock, size: 16),
              ),
              suffix: fluent.IconButton(
                icon: Icon(
                  _obscurePassword 
                      ? fluent.FluentIcons.view 
                      : fluent.FluentIcons.hide3,
                  size: 16,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // 确认新密码
          fluent.InfoLabel(
            label: '确认新密码',
            child: fluent.TextBox(
              controller: _confirmPasswordController,
              placeholder: '请再次输入新密码',
              obscureText: _obscureConfirmPassword,
              prefix: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(fluent.FluentIcons.lock, size: 16),
              ),
              suffix: fluent.IconButton(
                icon: Icon(
                  _obscureConfirmPassword 
                      ? fluent.FluentIcons.view 
                      : fluent.FluentIcons.hide3,
                  size: 16,
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // 重置密码按钮
          fluent.FilledButton(
            onPressed: _isLoading ? null : _handleReset,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('重置密码', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
          ),
        ],
      ),
    );
  }
}
