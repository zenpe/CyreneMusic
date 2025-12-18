import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'dart:io';
import '../../services/auth_overlay_service.dart';
import '../../services/auth_service.dart';
import '../../utils/theme_manager.dart';
import 'qr_login_dialog.dart';

/// 显示认证页面（改为内嵌 Stack 页面，而非对话框）
Future<bool?> showAuthDialog(BuildContext context, {int initialTab = 0}) {
  // 桌面端（Windows/macOS/Linux）：走内容区覆盖层服务，避免新路由拦截焦点
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    return AuthOverlayService().show(initialTab: initialTab);
  }

  // 移动端：保持整页路由体验
  final isCupertino = ThemeManager().isCupertinoFramework;
  return Navigator.push<bool>(
    context,
    isCupertino
        ? CupertinoPageRoute(
            builder: (context) => AuthPage(initialTab: initialTab),
          )
        : MaterialPageRoute(
            builder: (context) => AuthPage(initialTab: initialTab),
          ),
  );
}

/// 统一的认证页面 - Material Expressive 设计
class AuthPage extends StatefulWidget {
  final int initialTab;
  
  const AuthPage({super.key, this.initialTab = 0});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedSegment = 0;
  
  bool get _isCupertino => ThemeManager().isCupertinoFramework;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _selectedSegment = widget.initialTab;
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _selectedSegment = _tabController.index);
      }
    });
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isCupertino) {
      return _buildCupertinoPage(context, colorScheme, isDark);
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: const Text('账号'),
      ),
      body: Stack(
        children: [
          // 背景装饰渐变（与对话框样式一致，改为全屏）
          // 使用 IgnorePointer 确保不拦截触摸事件（修复 WSA 上点击无响应的问题）
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.5,
                    colors: [
                      colorScheme.primaryContainer.withOpacity(0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.bottomLeft,
                    radius: 1.5,
                    colors: [
                      colorScheme.secondaryContainer.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 主内容
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo 和标题
                  _buildHeader(colorScheme),
                  const SizedBox(height: 24),
                  // Tab 指示器
                  _buildTabBar(colorScheme),
                  const SizedBox(height: 16),
                  // Tab 内容
                  SizedBox(
                    height: 480,
                    child: TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _LoginView(),
                        _RegisterView(),
                        _ForgotPasswordView(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 桌面覆盖层下的返回按钮（避免依赖系统返回）
                  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
                    Align(
                      alignment: Alignment.center,
                      child: TextButton.icon(
                        onPressed: () {
                          // 如果使用覆盖层，则关闭覆盖层；否则正常返回
                          if (AuthOverlayService().isVisible) {
                            AuthOverlayService().hide(false);
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('完成'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// iOS Cupertino 风格页面
  Widget _buildCupertinoPage(BuildContext context, ColorScheme colorScheme, bool isDark) {
    // 使用 Material 包装解决 Text 组件黄色下划线问题
    return Material(
      type: MaterialType.transparency,
      child: CupertinoPageScaffold(
        backgroundColor: isDark ? const Color(0xFF000000) : CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('账号'),
          backgroundColor: (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white).withOpacity(0.9),
          border: null,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // iOS 分段控件
                _buildCupertinoSegmentedControl(isDark),
                const SizedBox(height: 24),
                // Tab 内容
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildCupertinoTabContent(isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCupertinoSegmentedControl(bool isDark) {
    return CupertinoSlidingSegmentedControl<int>(
      groupValue: _selectedSegment,
      onValueChanged: (value) {
        if (value != null) {
          setState(() => _selectedSegment = value);
          _tabController.animateTo(value);
        }
      },
      children: const {
        0: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('登录'),
        ),
        1: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('注册'),
        ),
        2: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('找回密码'),
        ),
      },
    );
  }

  Widget _buildCupertinoTabContent(bool isDark) {
    switch (_selectedSegment) {
      case 0:
        return _CupertinoLoginView(key: const ValueKey('login'), isDark: isDark);
      case 1:
        return _CupertinoRegisterView(key: const ValueKey('register'), isDark: isDark);
      case 2:
        return _CupertinoForgotPasswordView(key: const ValueKey('forgot'), isDark: isDark);
      default:
        return _CupertinoLoginView(key: const ValueKey('login'), isDark: isDark);
    }
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Column(
      children: [
        // Logo with gradient - Material 3 style
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primary,
                colorScheme.tertiary,
              ],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.music_note_rounded,
            size: 42,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        
        // Title with gradient
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.tertiary,
            ],
          ).createShader(bounds),
          child: Text(
            'Cyrene Music',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 32,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '发现美好音乐',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontSize: 15,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(ColorScheme colorScheme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24), // 胶囊外形 - 高度的一半
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.tertiary,
            ],
          ),
          borderRadius: BorderRadius.circular(20), // 胶囊内圆角
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 0.1,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          letterSpacing: 0.1,
        ),
        tabs: const [
          Tab(
            height: 40,
            child: Center(child: Text('登录')),
          ),
          Tab(
            height: 40,
            child: Center(child: Text('注册')),
          ),
          Tab(
            height: 40,
            child: Center(child: Text('找回密码')),
          ),
        ],
      ),
    );
  }
}

/// 登录视图
class _LoginView extends StatefulWidget {
  const _LoginView();

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        
        // 登录成功后，自动上报IP归属地
        AuthService().updateLocation().then((locationResult) {
          if (locationResult['success']) {
            print('✅ [AuthPage] IP归属地已更新: ${locationResult['data']?['location']}');
          }
        }).catchError((error) {
          print('❌ [AuthPage] IP归属地更新异常: $error');
        });
        
        // 覆盖层模式下关闭覆盖层，否则关闭路由
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: ListView(
        children: [
          // 账号输入框
          _buildTextField(
            controller: _accountController,
            label: '邮箱 / 用户名',
            icon: Icons.person_rounded,
            colorScheme: colorScheme,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入邮箱或用户名';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 密码输入框
          _buildTextField(
            controller: _passwordController,
            label: '密码',
            icon: Icons.lock_rounded,
            obscureText: _obscurePassword,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              return null;
            },
            onFieldSubmitted: (_) => _handleLogin(),
          ),
          const SizedBox(height: 32),

          // 登录按钮
          _buildGradientButton(
            label: '登录',
            isLoading: _isLoading,
            onPressed: _handleLogin,
            colorScheme: colorScheme,
          ),

          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLoading
                ? null
                : () async {
                    final result = await AuthService().loginWithLinuxDo();
                    if (!mounted) return;
                    if (result['success'] == true) {
                      // 登录成功后，自动上报IP归属地
                      AuthService().updateLocation();
                      
                      if (AuthOverlayService().isVisible) {
                        AuthOverlayService().hide(true);
                      } else {
                        Navigator.pop(context, true);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(result['message']),
                          backgroundColor: colorScheme.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
            icon: const Icon(Icons.forum_outlined),
            label: const Text('通过linux do授权'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF007AFF),
              side: const BorderSide(color: Color(0xFF007AFF)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),

          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) ...[
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final ok = await showQrLoginDialog(context);
                      if (!mounted) return;
                      if (ok == true) {
                        if (AuthOverlayService().isVisible) {
                          AuthOverlayService().hide(true);
                        } else {
                          Navigator.pop(context, true);
                        }
                      }
                    },
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('手机扫码登录'),
            ),
          ],
          
          const SizedBox(height: 16),
          
          // 提示文字
          Center(
            child: Text(
              '第一次使用？切换到注册标签页创建账号',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// 注册视图
class _RegisterView extends StatefulWidget {
  _RegisterView({Key? key}) : super(key: key);

  @override
  State<_RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<_RegisterView> {
  final _formKey = GlobalKey<FormState>();
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

  String _getFullEmail() {
    return '${_qqNumberController.text.trim()}@qq.com';
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
    if (_qqNumberController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先填写 QQ 号和用户名'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        _startCountdown();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入验证码'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_checkingStatus) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_registrationEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.block_rounded,
              size: 64,
              color: colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              '因滥用，我们暂时关闭了公开注册！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        children: [
          // QQ 号输入
          _buildTextField(
            controller: _qqNumberController,
            label: 'QQ 号',
            icon: Icons.chat_bubble_rounded,
            colorScheme: colorScheme,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入 QQ 号';
              }
              if (!RegExp(r'^\d+$').hasMatch(value.trim())) {
                return 'QQ 号应为纯数字';
              }
              if (value.trim().length < 5 || value.trim().length > 11) {
                return 'QQ 号长度应为 5-11 位';
              }
              return null;
            },
          ),
          
          // 显示完整邮箱
          if (_qqNumberController.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.mail_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '注册邮箱：${_getFullEmail()}',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),

          // 用户名
          _buildTextField(
            controller: _usernameController,
            label: '用户名',
            icon: Icons.person_rounded,
            colorScheme: colorScheme,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入用户名';
              }
              if (!RegExp(r'^[\u4e00-\u9fa5a-zA-Z0-9_]{2,20}$').hasMatch(value)) {
                return '2-20个字符，支持中文、字母、数字、下划线';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 密码
          _buildTextField(
            controller: _passwordController,
            label: '密码',
            icon: Icons.lock_rounded,
            obscureText: _obscurePassword,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入密码';
              }
              if (value.length < 8) {
                return '密码至少8个字符';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 确认密码
          _buildTextField(
            controller: _confirmPasswordController,
            label: '确认密码',
            icon: Icons.lock_rounded,
            obscureText: _obscureConfirmPassword,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请确认密码';
              }
              if (value != _passwordController.text) {
                return '两次密码不一致';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 验证码输入和发送按钮
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _codeController,
                  label: '验证码',
                  icon: Icons.verified_user_rounded,
                  colorScheme: colorScheme,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildGradientButton(
                  label: _codeSent ? '$_countdown秒' : '发送',
                  isLoading: false,
                  onPressed: _codeSent || _isLoading ? null : _sendCode,
                  colorScheme: colorScheme,
                  height: 56,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // 注册按钮
          _buildGradientButton(
            label: '注册',
            isLoading: _isLoading,
            onPressed: _handleRegister,
            colorScheme: colorScheme,
          ),
          
          const SizedBox(height: 16),
          
          // 用户协议
          Center(
            child: Text(
              '注册即表示您同意我们的服务条款和隐私政策',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

/// 找回密码视图
class _ForgotPasswordView extends StatefulWidget {
  const _ForgotPasswordView();

  @override
  State<_ForgotPasswordView> createState() => _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends State<_ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入邮箱'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().sendResetCode(
      email: _emailController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        _startCountdown();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请输入验证码'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Form(
      key: _formKey,
      child: ListView(
        children: [
          // 提示信息 - Material 3 风格
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.primary.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '我们将向您的邮箱发送验证码',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 邮箱
          _buildTextField(
            controller: _emailController,
            label: '注册邮箱',
            icon: Icons.mail_rounded,
            colorScheme: colorScheme,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入邮箱';
              }
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                return '邮箱格式不正确';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 验证码输入和发送按钮
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildTextField(
                  controller: _codeController,
                  label: '验证码',
                  icon: Icons.verified_user_rounded,
                  colorScheme: colorScheme,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildGradientButton(
                  label: _codeSent ? '$_countdown秒' : '发送',
                  isLoading: false,
                  onPressed: _codeSent || _isLoading ? null : _sendCode,
                  colorScheme: colorScheme,
                  height: 56,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 新密码
          _buildTextField(
            controller: _passwordController,
            label: '新密码',
            icon: Icons.lock_rounded,
            obscureText: _obscurePassword,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请输入新密码';
              }
              if (value.length < 8) {
                return '密码至少8个字符';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // 确认新密码
          _buildTextField(
            controller: _confirmPasswordController,
            label: '确认新密码',
            icon: Icons.lock_rounded,
            obscureText: _obscureConfirmPassword,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '请确认新密码';
              }
              if (value != _passwordController.text) {
                return '两次密码不一致';
              }
              return null;
            },
          ),
          const SizedBox(height: 32),

          // 重置密码按钮
          _buildGradientButton(
            label: '重置密码',
            isLoading: _isLoading,
            onPressed: _handleReset,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }
}

// 通用组件：Material Design 3 渐变按钮
Widget _buildGradientButton({
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
  required ColorScheme colorScheme,
  double? height,
}) {
  return Container(
    height: height ?? 52,
    decoration: BoxDecoration(
      gradient: onPressed == null
          ? null
          : LinearGradient(
              colors: [
                colorScheme.primary,
                colorScheme.tertiary,
              ],
            ),
      borderRadius: BorderRadius.circular(12), // Material 3 标准按钮圆角
      boxShadow: onPressed == null
          ? null
          : [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
    ),
    child: Material(
      color: onPressed == null ? colorScheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: onPressed == null ? colorScheme.onSurface.withOpacity(0.5) : Colors.white,
                  ),
                ),
        ),
      ),
    ),
  );
}

// 通用组件：Material Design 3 风格的文本输入框
Widget _buildTextField({
  required TextEditingController controller,
  required String label,
  required IconData icon,
  required ColorScheme colorScheme,
  bool obscureText = false,
  Widget? suffixIcon,
  String? Function(String?)? validator,
  TextInputType? keyboardType,
  void Function(String)? onFieldSubmitted,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscureText,
    keyboardType: keyboardType,
    validator: validator,
    onFieldSubmitted: onFieldSubmitted,
    style: const TextStyle(
      fontSize: 16,
      letterSpacing: 0.15,
    ),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      prefixIcon: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primaryContainer.withOpacity(0.6),
              colorScheme.tertiaryContainer.withOpacity(0.6),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: colorScheme.primary, size: 20),
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12), // Material 3 标准圆角
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.error,
          width: 1,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: colorScheme.error,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
  );
}

// ============ iOS Cupertino 风格视图 ============

/// iOS 风格登录视图
class _CupertinoLoginView extends StatefulWidget {
  final bool isDark;
  const _CupertinoLoginView({super.key, required this.isDark});

  @override
  State<_CupertinoLoginView> createState() => _CupertinoLoginViewState();
}

class _CupertinoLoginViewState extends State<_CupertinoLoginView> {
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_accountController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      _showCupertinoAlert('请填写完整信息');
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
        _showCupertinoToast(result['message'], isSuccess: true);
        AuthService().updateLocation();
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        _showCupertinoAlert(result['message']);
      }
    }
  }

  void _showCupertinoAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCupertinoToast(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? CupertinoColors.activeGreen : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 账号
        _buildCupertinoTextField(
          controller: _accountController,
          placeholder: '邮箱 / 用户名',
          icon: CupertinoIcons.person_fill,
          isDark: widget.isDark,
        ),
        const SizedBox(height: 16),

        // 密码
        _buildCupertinoTextField(
          controller: _passwordController,
          placeholder: '密码',
          icon: CupertinoIcons.lock_fill,
          obscureText: _obscurePassword,
          isDark: widget.isDark,
          suffix: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash_fill,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // 登录按钮
        _buildCupertinoButton(
          label: '登录',
          isLoading: _isLoading,
          onPressed: _handleLogin,
        ),
        
        const SizedBox(height: 12),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: _isLoading
              ? null
              : () async {
                  final result = await AuthService().loginWithLinuxDo();
                  if (!mounted) return;
                  if (result['success'] == true) {
                    // 登录成功后，自动上报IP归属地
                    AuthService().updateLocation();

                    if (AuthOverlayService().isVisible) {
                      AuthOverlayService().hide(true);
                    } else {
                      Navigator.pop(context, true);
                    }
                  } else {
                    _showCupertinoAlert(result['message']);
                  }
                },
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: CupertinoColors.activeBlue),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('通过linux do授权'),
          ),
        ),

        const SizedBox(height: 20),
        
        // 提示文字
        Center(
          child: Text(
            '第一次使用？切换到注册标签页创建账号',
            style: TextStyle(
              color: CupertinoColors.systemGrey,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// iOS 风格注册视图
class _CupertinoRegisterView extends StatefulWidget {
  final bool isDark;
  _CupertinoRegisterView({Key? key, required this.isDark}) : super(key: key);

  @override
  State<_CupertinoRegisterView> createState() => _CupertinoRegisterViewState();
}

class _CupertinoRegisterViewState extends State<_CupertinoRegisterView> {
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
    if (_qqNumberController.text.trim().isEmpty || _usernameController.text.trim().isEmpty) {
      _showCupertinoAlert('请先填写 QQ 号和用户名');
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
        _showCupertinoToast(result['message'], isSuccess: true);
        _startCountdown();
      } else {
        _showCupertinoAlert(result['message']);
      }
    }
  }

  Future<void> _handleRegister() async {
    if (_qqNumberController.text.trim().isEmpty ||
        _usernameController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showCupertinoAlert('请填写完整信息');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showCupertinoAlert('两次密码不一致');
      return;
    }
    if (_codeController.text.trim().isEmpty) {
      _showCupertinoAlert('请输入验证码');
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
        _showCupertinoToast(result['message'], isSuccess: true);
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        _showCupertinoAlert(result['message']);
      }
    }
  }

  void _showCupertinoAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCupertinoToast(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? CupertinoColors.activeGreen : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingStatus) {
      return const Center(
        child: CupertinoActivityIndicator(),
      );
    }

    if (!_registrationEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 64,
              color: CupertinoColors.systemRed,
            ),
            const SizedBox(height: 24),
            Text(
              '因滥用，我们暂时关闭了公开注册！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // QQ 邮箱（QQ号 + @qq.com 后缀）
        Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // 左侧图标
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Icon(CupertinoIcons.mail_solid, color: CupertinoColors.systemGrey, size: 20),
              ),
              // QQ 号输入框
              Expanded(
                child: CupertinoTextField(
                  controller: _qqNumberController,
                  placeholder: '请输入QQ号',
                  keyboardType: TextInputType.number,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: const BoxDecoration(),
                  style: TextStyle(
                    color: widget.isDark ? CupertinoColors.white : CupertinoColors.black,
                    fontSize: 16,
                  ),
                  placeholderStyle: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 16,
                  ),
                ),
              ),
              // @qq.com 后缀
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  '@qq.com',
                  style: TextStyle(
                    color: CupertinoColors.systemGrey,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 用户名
        _buildCupertinoTextField(
          controller: _usernameController,
          placeholder: '用户名',
          icon: CupertinoIcons.person_fill,
          isDark: widget.isDark,
        ),
        const SizedBox(height: 14),

        // 密码
        _buildCupertinoTextField(
          controller: _passwordController,
          placeholder: '密码',
          icon: CupertinoIcons.lock_fill,
          obscureText: _obscurePassword,
          isDark: widget.isDark,
          suffix: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash_fill,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 确认密码
        _buildCupertinoTextField(
          controller: _confirmPasswordController,
          placeholder: '确认密码',
          icon: CupertinoIcons.lock_fill,
          obscureText: _obscureConfirmPassword,
          isDark: widget.isDark,
          suffix: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            child: Icon(
              _obscureConfirmPassword ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash_fill,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 验证码
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildCupertinoTextField(
                controller: _codeController,
                placeholder: '验证码',
                icon: CupertinoIcons.checkmark_shield_fill,
                isDark: widget.isDark,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildCupertinoButton(
                label: _codeSent ? '$_countdown秒' : '发送',
                isLoading: false,
                onPressed: _codeSent || _isLoading ? null : _sendCode,
                height: 50,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 注册按钮
        _buildCupertinoButton(
          label: '注册',
          isLoading: _isLoading,
          onPressed: _handleRegister,
        ),
        
        const SizedBox(height: 16),
        
        Center(
          child: Text(
            '注册即表示您同意我们的服务条款和隐私政策',
            style: TextStyle(color: CupertinoColors.systemGrey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// iOS 风格找回密码视图
class _CupertinoForgotPasswordView extends StatefulWidget {
  final bool isDark;
  const _CupertinoForgotPasswordView({super.key, required this.isDark});

  @override
  State<_CupertinoForgotPasswordView> createState() => _CupertinoForgotPasswordViewState();
}

class _CupertinoForgotPasswordViewState extends State<_CupertinoForgotPasswordView> {
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
      _showCupertinoAlert('请输入邮箱');
      return;
    }

    setState(() => _isLoading = true);
    final result = await AuthService().sendResetCode(email: _emailController.text.trim());
    setState(() => _isLoading = false);

    if (mounted) {
      if (result['success']) {
        _showCupertinoToast(result['message'], isSuccess: true);
        _startCountdown();
      } else {
        _showCupertinoAlert(result['message']);
      }
    }
  }

  Future<void> _handleReset() async {
    if (_emailController.text.trim().isEmpty ||
        _codeController.text.trim().isEmpty ||
        _passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showCupertinoAlert('请填写完整信息');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showCupertinoAlert('两次密码不一致');
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
        _showCupertinoToast(result['message'], isSuccess: true);
        if (AuthOverlayService().isVisible) {
          AuthOverlayService().hide(true);
        } else {
          Navigator.pop(context, true);
        }
      } else {
        _showCupertinoAlert(result['message']);
      }
    }
  }

  void _showCupertinoAlert(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('提示'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  void _showCupertinoToast(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? CupertinoColors.activeGreen : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 提示信息
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.info_circle_fill, color: CupertinoColors.activeBlue, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '我们将向您的邮箱发送验证码',
                  style: TextStyle(
                    color: CupertinoColors.activeBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 邮箱
        _buildCupertinoTextField(
          controller: _emailController,
          placeholder: '注册邮箱',
          icon: CupertinoIcons.mail_solid,
          isDark: widget.isDark,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),

        // 验证码
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _buildCupertinoTextField(
                controller: _codeController,
                placeholder: '验证码',
                icon: CupertinoIcons.checkmark_shield_fill,
                isDark: widget.isDark,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: _buildCupertinoButton(
                label: _codeSent ? '$_countdown秒' : '发送',
                isLoading: false,
                onPressed: _codeSent || _isLoading ? null : _sendCode,
                height: 50,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 新密码
        _buildCupertinoTextField(
          controller: _passwordController,
          placeholder: '新密码',
          icon: CupertinoIcons.lock_fill,
          obscureText: _obscurePassword,
          isDark: widget.isDark,
          suffix: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash_fill,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 确认新密码
        _buildCupertinoTextField(
          controller: _confirmPasswordController,
          placeholder: '确认新密码',
          icon: CupertinoIcons.lock_fill,
          obscureText: _obscureConfirmPassword,
          isDark: widget.isDark,
          suffix: CupertinoButton(
            padding: EdgeInsets.zero,
            minSize: 0,
            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            child: Icon(
              _obscureConfirmPassword ? CupertinoIcons.eye_fill : CupertinoIcons.eye_slash_fill,
              color: CupertinoColors.systemGrey,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // 重置按钮
        _buildCupertinoButton(
          label: '重置密码',
          isLoading: _isLoading,
          onPressed: _handleReset,
        ),
      ],
    );
  }
}

// ============ iOS Cupertino 辅助组件 ============

/// iOS 风格文本输入框
Widget _buildCupertinoTextField({
  required TextEditingController controller,
  required String placeholder,
  required IconData icon,
  required bool isDark,
  bool obscureText = false,
  Widget? suffix,
  TextInputType? keyboardType,
}) {
  return Container(
    decoration: BoxDecoration(
      color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      obscureText: obscureText,
      keyboardType: keyboardType,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Icon(icon, color: CupertinoColors.systemGrey, size: 20),
      ),
      suffix: suffix != null
          ? Padding(
              padding: const EdgeInsets.only(right: 8),
              child: suffix,
            )
          : null,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      style: TextStyle(
        color: isDark ? CupertinoColors.white : CupertinoColors.black,
        fontSize: 16,
      ),
      placeholderStyle: TextStyle(
        color: CupertinoColors.systemGrey,
        fontSize: 16,
      ),
    ),
  );
}

/// iOS 风格简洁按钮
Widget _buildCupertinoButton({
  required String label,
  required bool isLoading,
  required VoidCallback? onPressed,
  double? height,
}) {
  return SizedBox(
    height: height ?? 50,
    width: double.infinity,
    child: CupertinoButton.filled(
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(10),
      onPressed: onPressed,
      child: isLoading
          ? const CupertinoActivityIndicator(color: CupertinoColors.white)
          : Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
    ),
  );
}

