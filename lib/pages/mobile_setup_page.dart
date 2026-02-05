import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/audio_source_service.dart';
import '../services/auth_service.dart';
import '../services/persistent_storage_service.dart';
import '../utils/theme_manager.dart';
import 'settings_page/audio_source_settings_page.dart';
import 'auth/auth_page.dart';

/// 移动端初始配置引导页
/// 
/// 多步引导流程：主题选择 → 配置音源 → 登录 → 进入主应用
class MobileSetupPage extends StatefulWidget {
  const MobileSetupPage({super.key});

  @override
  State<MobileSetupPage> createState() => _MobileSetupPageState();
}

class _MobileSetupPageState extends State<MobileSetupPage> {
  /// 引导步骤
  /// 0 = 主题选择
  /// 1 = 欢迎/音源配置入口
  /// 2 = 音源配置中
  /// 3 = 登录中
  /// 4 = 协议确认中
  int _currentStep = 0;
  
  /// 主题是否已选择
  bool _themeSelected = false;

  @override
  void initState() {
    super.initState();
    // 检查主题是否已配置过
    _checkThemeConfigured();
    // 监听音源配置和登录状态变化
    AudioSourceService().addListener(_onStateChanged);
    AuthService().addListener(_onStateChanged);
  }
  
  /// 检查主题是否已配置过（通过检查本地存储）
  void _checkThemeConfigured() {
    final storage = PersistentStorageService();
    final hasThemeConfig = storage.containsKey('mobile_theme_framework');
    if (hasThemeConfig) {
      setState(() {
        _themeSelected = true;
        _currentStep = 1; // 跳到音源配置步骤
      });
    }
  }

  @override
  void dispose() {
    AudioSourceService().removeListener(_onStateChanged);
    AuthService().removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) {
      setState(() {
        // 如果音源已配置且在配置步骤，自动进入下一步
        if (_currentStep == 2 && AudioSourceService().isConfigured) {
          _currentStep = 1; // 返回欢迎页（音源入口）
        }
        // 如果登录已完成且在登录步骤，自动进入协议页
        if (_currentStep == 3 && AuthService().isLoggedIn) {
          _currentStep = 4; 
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 主题选择页面
    if (_currentStep == 0 && !_themeSelected) {
      return _buildThemeSelectionPage(context, isDark);
    }

    // 音源配置页面
    if (_currentStep == 2) {
      return AudioSourceSettingsContent(
        onBack: () => setState(() => _currentStep = 1),
        embed: false,
      );
    }

    // 登录页面
    if (_currentStep == 3) {
      return _buildLoginPage(context, isCupertino, isDark);
    }

    // 协议确认页面
    if (_currentStep == 4) {
      return _buildAgreementPage(context, isCupertino, colorScheme, isDark);
    }

    // 欢迎/引导页面（音源配置入口）
    return _buildWelcomePage(context, isCupertino, colorScheme, isDark);
  }

  /// 构建主题选择页面
  Widget _buildThemeSelectionPage(BuildContext context, bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              
              // App Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '🎨',
                    style: TextStyle(fontSize: 64),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 标题
              Text(
                '选择您的界面风格',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // 副标题
              Text(
                '您可以随时在设置中更改',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Material Design 选项
              _buildThemeOptionCard(
                context: context,
                title: 'Material Design',
                subtitle: 'Google 风格，现代简约',
                icon: Icons.android,
                color: Colors.green,
                isDark: isDark,
                onTap: () => _selectTheme(MobileThemeFramework.material),
              ),
              
              const SizedBox(height: 16),
              
              // Cupertino 选项
              _buildThemeOptionCard(
                context: context,
                title: 'Cupertino',
                subtitle: 'Apple 风格，精致优雅',
                icon: Icons.apple,
                color: ThemeManager.iosBlue,
                isDark: isDark,
                onTap: () => _selectTheme(MobileThemeFramework.cupertino),
              ),
              
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 构建主题选项卡片
  Widget _buildThemeOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
          ),
          boxShadow: isDark ? null : [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 28,
                color: color,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 选择主题
  void _selectTheme(MobileThemeFramework framework) async {
    final themeManager = ThemeManager();
    themeManager.setMobileThemeFramework(framework);
    
    // Material Design 启用 Material You 自适应主题色
    // Cupertino 使用固定的 iOS 蓝色，无需跟随系统
    if (framework == MobileThemeFramework.material) {
      await themeManager.setFollowSystemColor(true, context: context);
    } else {
      await themeManager.setFollowSystemColor(false);
    }
    
    setState(() {
      _themeSelected = true;
      _currentStep = 1; // 进入音源配置入口
    });
  }

  /// 构建欢迎引导页面
  Widget _buildWelcomePage(BuildContext context, bool isCupertino, ColorScheme colorScheme, bool isDark) {
    final audioConfigured = AudioSourceService().isConfigured;
    final isLoggedIn = AuthService().isLoggedIn;

    // 决定当前显示的引导内容
    String title;
    String subtitle;
    String buttonText;
    VoidCallback onButtonPressed;
    bool showSkip = true;

    if (!audioConfigured) {
      // 第一步：配置音源
      title = '欢迎使用 Cyrene Music';
      subtitle = '开始前，请先配置音源以解锁全部功能';
      buttonText = '配置音源';
      onButtonPressed = () => setState(() => _currentStep = 2);
    } else if (!isLoggedIn) {
      // 第二步：登录
      title = '音源配置完成 ✓';
      subtitle = '登录账号以同步您的收藏和播放记录';
      buttonText = '登录 / 注册';
      onButtonPressed = () => setState(() => _currentStep = 3);
    } else {
      // 全部完成（理论上不会到达这里，因为 main.dart 会跳转）
      title = '准备就绪!';
      subtitle = '开始探索音乐世界吧';
      buttonText = '下一步';
      onButtonPressed = () => setState(() => _currentStep = 4);
      showSkip = false;
    }

    return Scaffold(
      backgroundColor: isCupertino
          ? (isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground)
          : colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),
              
              // App Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '🤔',
                    style: TextStyle(
                      fontSize: 64,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 进度指示器
              _buildStepIndicator(_themeSelected, audioConfigured, isLoggedIn, isDark, colorScheme),
              
              const SizedBox(height: 24),
              
              // 标题
              Text(
                title,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              // 副标题
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(flex: 2),
              
              // 主按钮
              _buildMainButton(context, isCupertino, buttonText, onButtonPressed),
              
              const SizedBox(height: 16),
              
              // 跳过按钮
              if (showSkip)
                TextButton(
                  onPressed: () => _showSkipConfirmation(context, isCupertino),
                  child: Text(
                    '稍后再说',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black45,
                      fontSize: 14,
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
  Widget _buildStepIndicator(bool themeSelected, bool audioConfigured, bool isLoggedIn, bool isDark, ColorScheme colorScheme) {
    // 当前步骤的高亮色：Material 使用主题色，Cupertino 使用 iOS 蓝
    final themeManager = ThemeManager();
    final currentStepColor = themeManager.isCupertinoFramework 
        ? ThemeManager.iosBlue 
        : colorScheme.primary;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 主题选择步骤
        _buildStepDot(
          isCompleted: themeSelected,
          isCurrent: !themeSelected,
          isDark: isDark,
          currentStepColor: currentStepColor,
        ),
        Container(
          width: 32,
          height: 2,
          color: themeSelected 
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
        // 音源配置步骤
        _buildStepDot(
          isCompleted: audioConfigured,
          isCurrent: themeSelected && !audioConfigured,
          isDark: isDark,
          currentStepColor: currentStepColor,
        ),
        Container(
          width: 32,
          height: 2,
          color: audioConfigured 
              ? (isDark ? Colors.white54 : Colors.black38)
              : (isDark ? Colors.white24 : Colors.black12),
        ),
        // 登录步骤
        _buildStepDot(
          isCompleted: isLoggedIn,
          isCurrent: audioConfigured && !isLoggedIn,
          isDark: isDark,
          currentStepColor: currentStepColor,
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
          ? const Icon(Icons.check, size: 8, color: Colors.white)
          : null,
    );
  }

  /// 构建登录页面
  Widget _buildLoginPage(BuildContext context, bool isCupertino, bool isDark) {
    return Scaffold(
      backgroundColor: isCupertino
          ? (isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground)
          : Theme.of(context).colorScheme.surface,
      appBar: isCupertino
          ? CupertinoNavigationBar(
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _currentStep = 1),
                child: const Icon(CupertinoIcons.back),
              ),
              middle: const Text('登录'),
              backgroundColor: Colors.transparent,
              border: null,
            ) as PreferredSizeWidget?
          : AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _currentStep = 1),
              ),
              title: const Text('登录'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
      body: const AuthPage(initialTab: 0),
    );
  }

  Widget _buildMainButton(BuildContext context, bool isCupertino, String text, VoidCallback onPressed) {
    if (isCupertino) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoButton.filled(
          onPressed: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showSkipConfirmation(BuildContext context, bool isCupertino) {
    final audioConfigured = AudioSourceService().isConfigured;
    String message;
    
    if (!audioConfigured) {
      message = '不配置音源将无法播放在线音乐。您可以稍后在设置中配置。';
    } else {
      message = '不登录将无法同步收藏和播放记录。您可以稍后在设置中登录。';
    }

    if (isCupertino) {
      showCupertinoDialog(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: const Text('跳过配置'),
          content: Text(message),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _skipSetup();
              },
              child: const Text('确认跳过'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('跳过配置'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
            TextButton(
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
  }

  /// 构建协议确认页面
  Widget _buildAgreementPage(BuildContext context, bool isCupertino, ColorScheme colorScheme, bool isDark) {
    return Scaffold(
      backgroundColor: isCupertino
          ? (isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground)
          : colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
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
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '在开始之前，请认真看完它：',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            // 协议正文容器
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
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
            const SizedBox(height: 24),
            // 确认按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _buildMainButton(
                context, 
                isCupertino, 
                '接受协议并进入', 
                () async {
                  // 持久化协议确认为 true
                  final storage = PersistentStorageService();
                  await storage.setBool('terms_accepted', true);
                  
                  // 触发监听以切换 MobileAppGate
                  AudioSourceService().notifyListeners();
                  AuthService().notifyListeners();
                }
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

  void _skipSetup() {
    // 通知跳过 - 触发 main.dart 中的状态更新来进入主应用
    // 这里通过 notifyListeners 来触发 AnimatedBuilder 重建
    AudioSourceService().notifyListeners();
    AuthService().notifyListeners();
  }
}
