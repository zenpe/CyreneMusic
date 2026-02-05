import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:window_manager/window_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../services/audio_source_service.dart';
import '../services/auth_service.dart';
import '../services/persistent_storage_service.dart';
import '../utils/theme_manager.dart';
import 'settings_page/audio_source_settings_page.dart';
import 'auth/fluent_auth_page.dart';

/// 桌面端初始配置引导页
/// 
/// 多步引导流程：主题设置 → 配置音源 → 登录 → 确认协议 → 进入主应用
class DesktopSetupPage extends StatefulWidget {
  const DesktopSetupPage({super.key});

  @override
  State<DesktopSetupPage> createState() => _DesktopSetupPageState();
}

class _DesktopSetupPageState extends State<DesktopSetupPage> with WindowListener {
  /// 引导步骤
  /// 0 = 欢迎/引导入口
  /// 1 = 主题设置中
  /// 2 = 音源配置中
  /// 3 = 登录中
  /// 4 = 协议确认中
  int _currentStep = 0;
  
  /// 窗口状态
  bool _isWindowMaximized = false;

  @override
  void initState() {
    super.initState();
    // 监听音源配置和登录状态变化
    AudioSourceService().addListener(_onStateChanged);
    AuthService().addListener(_onStateChanged);
    
    // Windows 平台初始化窗口监听
    if (Platform.isWindows) {
      windowManager.addListener(this);
      windowManager.isMaximized().then((value) {
        if (mounted) {
          setState(() {
            _isWindowMaximized = value;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    AudioSourceService().removeListener(_onStateChanged);
    AuthService().removeListener(_onStateChanged);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }
  
  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() {
      _isWindowMaximized = true;
    });
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() {
      _isWindowMaximized = false;
    });
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {
        // 如果音源已配置且在配置步骤，自动返回欢迎页
        if (_currentStep == 2 && AudioSourceService().isConfigured) {
          _currentStep = 0;
        }
        // 如果登录已完成且在登录步骤，自动进入协议页
        if (_currentStep == 3 && AuthService().isLoggedIn) {
          _currentStep = 4;
        }
      });
    }
  }
  
  // 窗口控制方法
  void _handleCaptionMinimize() {
    if (!Platform.isWindows) return;
    windowManager.minimize();
  }

  void _handleCaptionMaximizeOrRestore() {
    if (!Platform.isWindows) return;
    windowManager.isMaximized().then((isMaximized) {
      if (isMaximized) {
        windowManager.unmaximize();
      } else {
        windowManager.maximize();
      }
      if (mounted) {
        setState(() {
          _isWindowMaximized = !isMaximized;
        });
      }
    });
  }

  void _handleCaptionClose() {
    if (!Platform.isWindows) return;
    windowManager.close();
  }

  /// 构建标题栏（包含拖动区域和窗口控制按钮）
  Widget _buildTitleBar(BuildContext context, fluent.FluentThemeData theme) {
    final brightness = theme.brightness;
    final typography = theme.typography;
    
    return SizedBox(
      height: 50,
      child: Stack(
        children: [
          // 可拖动区域
          Positioned.fill(
            child: DragToMoveArea(
              child: Container(color: Colors.transparent),
            ),
          ),
          // 标题（左侧）
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/tray_icon.png',
                    width: 16,
                    height: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Cyrene Music',
                    style: (typography.subtitle ?? typography.bodyLarge)?.copyWith(fontSize: 12) 
                        ?? const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          // 窗口控制按钮（右侧）
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WindowCaptionButton.minimize(
                  brightness: brightness,
                  onPressed: _handleCaptionMinimize,
                ),
                _isWindowMaximized
                    ? WindowCaptionButton.unmaximize(
                        brightness: brightness,
                        onPressed: _handleCaptionMaximizeOrRestore,
                      )
                    : WindowCaptionButton.maximize(
                        brightness: brightness,
                        onPressed: _handleCaptionMaximizeOrRestore,
                      ),
                WindowCaptionButton.close(
                  brightness: brightness,
                  onPressed: _handleCaptionClose,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 判断是否使用透明背景（窗口效果启用时）
    final useWindowEffect = Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
    final backgroundColor = useWindowEffect 
        ? Colors.transparent 
        : (isDark ? const Color(0xFF1F1F1F) : const Color(0xFFF3F3F3));

    // 构建页面内容
    Widget pageContent;
    
    if (_currentStep == 1) {
      pageContent = _buildThemeSettingsPage(context, theme, isDark);
    } else if (_currentStep == 2) {
      pageContent = _buildAudioSourcePage(context, theme, isDark);
    } else if (_currentStep == 3) {
      pageContent = _buildLoginPage(context, theme, isDark);
    } else if (_currentStep == 4) {
      pageContent = _buildAgreementPage(context, theme, isDark);
    } else {
      pageContent = _buildWelcomePage(context, theme, isDark);
    }

    // 将标题栏和页面内容组合
    return Container(
      color: backgroundColor,
      child: Column(
        children: [
          _buildTitleBar(context, theme),
          Expanded(child: pageContent),
        ],
      ),
    );
  }

  /// 构建欢迎引导页面
  Widget _buildWelcomePage(BuildContext context, fluent.FluentThemeData theme, bool isDark) {
    final themeConfigured = PersistentStorageService().getBool('theme_configured') ?? false;
    final audioConfigured = AudioSourceService().isConfigured;
    final isLoggedIn = AuthService().isLoggedIn;

    // 决定当前显示的引导内容
    String title;
    String subtitle;
    String buttonText;
    VoidCallback onButtonPressed;
    bool showSkip = true;

    if (!themeConfigured) {
      // 第一步：主题设置
      title = '欢迎使用 Cyrene Music';
      subtitle = '首先，让我们设置您喜欢的外观风格';
      buttonText = '主题设置';
      onButtonPressed = () => setState(() => _currentStep = 1);
    } else if (!audioConfigured) {
      // 第二步：配置音源
      title = '主题设置完成 ✓';
      subtitle = '接下来，配置音源以解锁全部功能';
      buttonText = '配置音源';
      onButtonPressed = () => setState(() => _currentStep = 2);
    } else if (!isLoggedIn) {
      // 第三步：登录
      title = '音源配置完成 ✓';
      subtitle = '登录账号以同步您的收藏和播放记录';
      buttonText = '登录 / 注册';
      onButtonPressed = () => setState(() => _currentStep = 3);
    } else {
      // 全部完成，进入协议页
      title = '准备就绪!';
      subtitle = '开始探索音乐世界吧';
      buttonText = '下一步';
      onButtonPressed = () => setState(() => _currentStep = 4);
      showSkip = false;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              
              // App Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: theme.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/icons/new_ico.png',
                      width: 80,
                      height: 80,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 进度指示器
              _buildStepIndicator(themeConfigured, audioConfigured, isLoggedIn, isDark, theme),
              
              const SizedBox(height: 24),
              
              // 标题
              Text(
                title,
                style: theme.typography.title?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // 副标题
              Text(
                subtitle,
                style: theme.typography.body?.copyWith(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(flex: 2),
              
              // 主按钮
              SizedBox(
                width: double.infinity,
                child: fluent.FilledButton(
                  onPressed: onButtonPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      buttonText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 跳过按钮
              if (showSkip)
                fluent.HyperlinkButton(
                  onPressed: () => _showSkipConfirmation(context),
                  child: Text(
                    '稍后再说',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ),
              
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建步骤指示器
  Widget _buildStepIndicator(bool themeConfigured, bool audioConfigured, bool isLoggedIn, bool isDark, fluent.FluentThemeData theme) {
    final accentColor = theme.accentColor;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 主题设置步骤
        _buildStepDot(
          isCompleted: themeConfigured,
          isCurrent: !themeConfigured,
          isDark: isDark,
          currentStepColor: accentColor,
        ),
        Container(
          width: 24,
          height: 2,
          color: themeConfigured 
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
        // 音源配置步骤
        _buildStepDot(
          isCompleted: audioConfigured,
          isCurrent: themeConfigured && !audioConfigured,
          isDark: isDark,
          currentStepColor: accentColor,
        ),
        Container(
          width: 24,
          height: 2,
          color: audioConfigured 
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
        // 登录步骤
        _buildStepDot(
          isCompleted: isLoggedIn,
          isCurrent: themeConfigured && audioConfigured && !isLoggedIn,
          isDark: isDark,
          currentStepColor: accentColor,
        ),
        Container(
          width: 24,
          height: 2,
          color: isLoggedIn 
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
        // 协议确认步骤
        _buildStepDot(
          isCompleted: false,
          isCurrent: themeConfigured && audioConfigured && isLoggedIn,
          isDark: isDark,
          currentStepColor: accentColor,
        ),
      ],
    );
  }

  Widget _buildStepDot({
    required bool isCompleted,
    required bool isCurrent,
    required bool isDark,
    required Color currentStepColor,
  }) {
    Color color;
    if (isCompleted) {
      color = Colors.green;
    } else if (isCurrent) {
      color = currentStepColor;
    } else {
      color = isDark ? Colors.white24 : Colors.black12;
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: isCompleted
          ? const Icon(fluent.FluentIcons.check_mark, size: 8, color: Colors.white)
          : null,
    );
  }

  /// 构建主题设置页面
  Widget _buildThemeSettingsPage(BuildContext context, fluent.FluentThemeData theme, bool isDark) {
    return Column(
      children: [
        // 页面头部（带返回按钮）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.back),
                onPressed: () => setState(() => _currentStep = 0),
              ),
              const SizedBox(width: 8),
              Text(
                '主题设置',
                style: theme.typography.subtitle,
              ),
            ],
          ),
        ),
        // 主题设置内容
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: fluent.ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  // 主题色设置
                  _buildThemeColorSection(theme, isDark),
                  const SizedBox(height: 24),
                  
                  // 窗口效果设置
                  _buildWindowEffectSection(theme, isDark),
                  const SizedBox(height: 32),
                  
                  // 完成按钮
                  SizedBox(
                    width: double.infinity,
                    child: fluent.FilledButton(
                      onPressed: () async {
                        // 标记主题配置完成
                        await PersistentStorageService().setBool('theme_configured', true);
                        setState(() => _currentStep = 0);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '完成设置',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建主题色设置区域
  Widget _buildThemeColorSection(fluent.FluentThemeData theme, bool isDark) {
    return fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题色',
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 16),
          
          // 跟随系统选项
          Row(
            children: [
              Expanded(
                child: Text(
                  '跟随系统主题色',
                  style: theme.typography.body,
                ),
              ),
              fluent.ToggleSwitch(
                checked: ThemeManager().followSystemColor,
                onChanged: (value) async {
                  await ThemeManager().setFollowSystemColor(value, context: context);
                  setState(() {});
                },
              ),
            ],
          ),
          
          // 自定义主题色
          if (!ThemeManager().followSystemColor) ...[
            const SizedBox(height: 16),
            Text(
              '选择主题色',
              style: theme.typography.caption?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final colorScheme in ThemeColors.presets)
                  GestureDetector(
                    onTap: () {
                      ThemeManager().setSeedColor(colorScheme.color);
                      setState(() {});
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.color,
                        shape: BoxShape.circle,
                        border: ThemeManager().seedColor.value == colorScheme.color.value
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: ThemeManager().seedColor.value == colorScheme.color.value
                            ? [
                                BoxShadow(
                                  color: colorScheme.color.withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: ThemeManager().seedColor.value == colorScheme.color.value
                          ? const Icon(fluent.FluentIcons.check_mark, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                // 自定义颜色按钮
                GestureDetector(
                  onTap: () => _showCustomColorPickerDialog(theme, isDark),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? Colors.white12 : Colors.black12,
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      fluent.FluentIcons.add,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 构建窗口效果设置区域
  Widget _buildWindowEffectSection(fluent.FluentThemeData theme, bool isDark) {
    return fluent.Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '窗口效果',
            style: theme.typography.bodyStrong,
          ),
          const SizedBox(height: 8),
          
          // 警告提示
          fluent.InfoBar(
            title: const Text('兼容性提示'),
            content: const Text('Windows 11 以下系统推荐使用"默认"效果，云母或亚克力可能会出现显示异常！'),
            severity: fluent.InfoBarSeverity.warning,
            isLong: true,
          ),
          const SizedBox(height: 16),
          
          // 窗口效果选择
          _buildWindowEffectOption(
            theme: theme,
            isDark: isDark,
            effect: WindowEffect.disabled,
            title: '默认',
            description: '兼容性最佳，适合所有 Windows 版本',
            icon: fluent.FluentIcons.checkbox_composite,
          ),
          const SizedBox(height: 8),
          _buildWindowEffectOption(
            theme: theme,
            isDark: isDark,
            effect: WindowEffect.mica,
            title: '云母',
            description: '现代毛玻璃效果，仅支持 Windows 11',
            icon: fluent.FluentIcons.blur,
            enabled: ThemeManager().isMicaSupported,
          ),
          const SizedBox(height: 8),
          _buildWindowEffectOption(
            theme: theme,
            isDark: isDark,
            effect: WindowEffect.acrylic,
            title: '亚克力',
            description: '半透明模糊效果，Windows 10 及以上',
            icon: fluent.FluentIcons.picture_library,
          ),
        ],
      ),
    );
  }

  /// 构建窗口效果选项
  Widget _buildWindowEffectOption({
    required fluent.FluentThemeData theme,
    required bool isDark,
    required WindowEffect effect,
    required String title,
    required String description,
    required IconData icon,
    bool enabled = true,
  }) {
    final isSelected = ThemeManager().windowEffect == effect;
    
    return fluent.HoverButton(
      onPressed: enabled
          ? () async {
              await ThemeManager().setWindowEffect(effect);
              setState(() {});
            }
          : null,
      builder: (context, states) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.accentColor.withOpacity(0.15)
                : (states.isHovering && enabled
                    ? (isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03))
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.accentColor
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 24,
                color: enabled
                    ? (isSelected ? theme.accentColor : (isDark ? Colors.white70 : Colors.black54))
                    : (isDark ? Colors.white24 : Colors.black26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.typography.body?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: enabled ? null : (isDark ? Colors.white38 : Colors.black38),
                          ),
                        ),
                        if (!enabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black12,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '需要 Win11',
                              style: TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.typography.caption?.copyWith(
                        color: enabled
                            ? (isDark ? Colors.white54 : Colors.black45)
                            : (isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(
                  fluent.FluentIcons.check_mark,
                  size: 16,
                  color: theme.accentColor,
                ),
            ],
          ),
        );
      },
    );
  }

  /// 显示自定义颜色选择器对话框
  void _showCustomColorPickerDialog(fluent.FluentThemeData theme, bool isDark) {
    Color tempColor = ThemeManager().seedColor;
    
    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('自定义主题色'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 420,
            maxHeight: 480,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: tempColor,
                onColorChanged: (color) {
                  tempColor = color;
                },
                enableAlpha: false,
                displayThumbColor: true,
                pickerAreaHeightPercent: 0.75,
                portraitOnly: true,
                labelTypes: const [],
                hexInputBar: false,
              ),
            ),
          ),
        ),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          fluent.FilledButton(
            onPressed: () {
              ThemeManager().setSeedColor(tempColor);
              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 构建音源配置页面
  Widget _buildAudioSourcePage(BuildContext context, fluent.FluentThemeData theme, bool isDark) {
    return Column(
      children: [
        // 页面头部（带返回按钮）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.back),
                onPressed: () => setState(() => _currentStep = 0),
              ),
              const SizedBox(width: 8),
              Text(
                '配置音源',
                style: theme.typography.subtitle,
              ),
            ],
          ),
        ),
        const Expanded(
          child: AudioSourceSettingsContent(
            embed: true,
          ),
        ),
      ],
    );
  }

  /// 构建登录页面
  Widget _buildLoginPage(BuildContext context, fluent.FluentThemeData theme, bool isDark) {
    return Column(
      children: [
        // 页面头部（带返回按钮）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              fluent.IconButton(
                icon: const Icon(fluent.FluentIcons.back),
                onPressed: () => setState(() => _currentStep = 0),
              ),
              const SizedBox(width: 8),
              Text(
                '登录',
                style: theme.typography.subtitle,
              ),
            ],
          ),
        ),
        const Expanded(
          child: FluentAuthPage(initialTab: 0),
        ),
      ],
    );
  }

  /// 构建协议确认页面
  Widget _buildAgreementPage(BuildContext context, fluent.FluentThemeData theme, bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Emoji 😋
            const Center(
              child: Text(
                '😋',
                style: TextStyle(fontSize: 64),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '配置完成',
              style: theme.typography.title?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在开始之前，请认真看完它：',
              style: theme.typography.body?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.redAccent,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 协议正文容器
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: fluent.Card(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      _buildSectionTitle('CyreneMusic 使用协议'),
                      _buildSectionBody('词语约定：\n“本项目”指 CyreneMusic 应用及其相关开源代码；\n“使用者”指下载、安装、运行或以任何方式使用本项目的个人或组织；\n“音源”指由使用者自行导入或配置的第三方音频数据来源（包括但不限于 API、链接、本地文件路径等）；\n“版权数据”指包括但不限于音频、专辑封面、歌曲名、艺术家信息等受知识产权保护的内容。'),
                      
                      _buildSectionTitle('一、数据来源与播放机制'),
                      _buildSectionBody('1.1 本项目 本身不具备获取音频流的能力。所有音频播放均依赖于使用者自行导入或配置的“音源”。本项目仅将用户输入的歌曲信息（如标题、艺术家等）传递给所选音源，并播放其返回的音频链接。'),
                      _buildSectionBody('1.2 本项目 不对音源返回内容的合法性、准确性、完整性或可用性作任何保证。若音源返回错误、无关、失效或侵权内容，由此产生的任何问题均由使用者及音源提供方承担，本项目开发者不承担任何责任。'),
                      _buildSectionBody('1.3 使用者应自行确保所导入音源的合法性，并对其使用行为负全部法律责任。'),
                      
                      _buildSectionTitle('二、账号与数据同步'),
                      _buildSectionBody('2.1 本平台提供的账号系统 仅用于云端保存歌单、播放历史等用户偏好数据，不用于身份认证、商业推广、数据分析或其他用途。'),
                      _buildSectionBody('2.2 所有同步至云端的数据均由使用者主动上传，本项目不对这些数据的内容、合法性或安全性负责。'),
                      
                      _buildSectionTitle('三、版权与知识产权'),
                      _buildSectionBody('3.1 本项目 不存储、不分发、不缓存任何音频文件或版权数据。所有版权数据均由使用者通过外部音源实时获取。'),
                      _buildSectionBody('3.2 使用者在使用本项目过程中接触到的任何版权内容（如歌曲、专辑图等），其权利归属于原著作权人。使用者应遵守所在国家/地区的版权法律法规。'),
                      _buildSectionBody('3.3 强烈建议使用者在24小时内清除本地缓存的版权数据（如有），以避免潜在侵权风险。本项目不主动缓存音频，但部分系统或浏览器可能自动缓存，使用者需自行管理。'),
                      
                      _buildSectionTitle('四、开源与许可'),
                      _buildSectionBody('4.1 本项目为 完全开源软件，基于 Apache License 2.0 发布。使用者可自由使用、修改、分发本项目代码，但须遵守 Apache 2.0 许可证条款。'),
                      _buildSectionBody('4.2 本项目中使用的第三方资源（如图标、字体等）均注明来源。若存在未授权使用情况，请联系开发者及时移除。'),
                      
                      _buildSectionTitle('五、免责声明'),
                      _buildSectionBody('5.1 使用者理解并同意：因使用本项目或依赖外部音源所导致的任何直接或间接损失（包括但不限于数据丢失、设备损坏、法律纠纷、隐私泄露等），均由使用者自行承担。'),
                      _buildSectionBody('5.2 本项目开发者 不对本项目的功能完整性、稳定性、安全性或适配性作任何明示或暗示的担保。'),
                      
                      _buildSectionTitle('六、使用限制'),
                      _buildSectionBody('6.1 本项目 仅用于技术学习、个人非商业用途。禁止将本项目用于任何违反当地法律法规的行为（如盗版传播、侵犯版权、非法爬取等）。'),
                      _buildSectionBody('6.2 若使用者所在司法管辖区禁止使用此类工具，使用者应立即停止使用。因违规使用所引发的一切后果，由使用者自行承担。'),
                      
                      _buildSectionTitle('七、尊重版权'),
                      _buildSectionBody('7.1 音乐创作不易，请尊重艺术家与版权方的劳动成果。支持正版音乐，优先使用合法授权的音源服务。'),
                      
                      _buildSectionTitle('八、协议接受'),
                      _buildSectionBody('8.1 一旦您下载、安装、运行或以任何方式使用 CyreneMusic，即视为您已阅读、理解并无条件接受本协议全部条款。'),
                      _buildSectionBody('8.2 本协议可能随项目更新而修订，修订后将发布于项目仓库。继续使用即视为接受最新版本。'),
                      
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '最新更新时间：2026年2月4日',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 确认按钮
            SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: fluent.FilledButton(
                  onPressed: () async {
                    // 持久化协议确认为 true
                    final storage = PersistentStorageService();
                    await storage.setBool('terms_accepted', true);
                    
                    // 触发监听以切换 DesktopAppGate
                    AudioSourceService().notifyListeners();
                    AuthService().notifyListeners();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '接受协议并进入',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildSectionBody(String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        body,
        style: const TextStyle(
          fontSize: 14,
          height: 1.5,
          color: Colors.grey,
        ),
      ),
    );
  }

  void _showSkipConfirmation(BuildContext context) {
    final audioConfigured = AudioSourceService().isConfigured;
    String message;
    
    if (!audioConfigured) {
      message = '不配置音源将无法播放在线音乐。您可以稍后在设置中配置。';
    } else {
      message = '不登录将无法同步收藏和播放记录。您可以稍后在设置中登录。';
    }

    fluent.showDialog(
      context: context,
      builder: (context) => fluent.ContentDialog(
        title: const Text('跳过配置'),
        content: Text(message),
        actions: [
          fluent.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回'),
          ),
          fluent.FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _skipSetup();
            },
            child: const Text('确认跳过'),
          ),
        ],
      ),
    );
  }

  void _skipSetup() {
    // 直接标记协议为已确认并跳到主界面
    PersistentStorageService().setBool('terms_accepted', true);
    // 通知跳过 - 触发状态更新来进入主应用
    AudioSourceService().notifyListeners();
    AuthService().notifyListeners();
  }
}
