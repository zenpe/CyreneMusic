import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import '../../services/donate_service.dart';
import '../../services/auth_service.dart';
import '../../utils/theme_manager.dart';

/// 赞助墙组件 - 展示所有赞助用户
class SponsorWall extends StatefulWidget {
  const SponsorWall({super.key});

  @override
  State<SponsorWall> createState() => _SponsorWallState();
}

class _SponsorWallState extends State<SponsorWall> {
  List<Map<String, dynamic>> _sponsors = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSponsors();
    // 监听认证状态变化，当用户状态改变时刷新赞助列表
    AuthService().addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthService().removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    // 延迟刷新，确保数据库已更新
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        print('[SponsorWall] 检测到用户状态变化，刷新赞助列表');
        _loadSponsors();
      }
    });
  }

  Future<void> _loadSponsors() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await DonateService.getSponsorList();
      if (result['code'] == 200 && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        final sponsors = data['sponsors'] as List<dynamic>?;
        
        if (sponsors != null) {
          setState(() {
            _sponsors = sponsors.cast<Map<String, dynamic>>();
            _loading = false;
          });
          print('[SponsorWall] 加载了 ${_sponsors.length} 位赞助用户');
        } else {
          setState(() {
            _sponsors = [];
            _loading = false;
          });
        }
      } else {
        setState(() {
          _error = result['message'] ?? '加载失败';
          _loading = false;
        });
      }
    } catch (e) {
      print('[SponsorWall] 加载赞助用户失败: $e');
      setState(() {
        _error = '加载失败';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFluentUI = ThemeManager().isDesktopFluentUI;
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
    
    if (isFluentUI) {
      return _buildFluentUI(context);
    }
    
    if (isCupertino) {
      return _buildCupertinoUI(context);
    }
    
    return _buildMaterialUI(context);
  }

  /// iOS Cupertino UI 版本
  Widget _buildCupertinoUI(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
          child: Text(
            '赞助墙 - 感谢以下用户的支持',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(context, isCupertino: true, isDark: isDark),
          ),
        ),
      ],
    );
  }

  /// Material UI 版本
  Widget _buildMaterialUI(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.workspace_premium,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '赞助墙 - 感谢以下用户的支持',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(context, colorScheme: colorScheme),
          ),
        ),
      ],
    );
  }

  /// Fluent UI 版本
  Widget _buildFluentUI(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              const Icon(
                fluent_ui.FluentIcons.trophy2,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                '赞助墙 - 感谢以下用户的支持',
                style: fluent_ui.FluentTheme.of(context).typography.subtitle,
              ),
            ],
          ),
        ),
        fluent_ui.Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildContent(context, isFluent: true),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, {ColorScheme? colorScheme, bool isFluent = false, bool isCupertino = false, bool isDark = false}) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: isFluent ? Colors.red : colorScheme?.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: isFluent
                    ? fluent_ui.FluentTheme.of(context).typography.body
                    : Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              isFluent
                  ? fluent_ui.Button(
                      onPressed: _loadSponsors,
                      child: const Text('重试'),
                    )
                  : OutlinedButton(
                      onPressed: _loadSponsors,
                      child: const Text('重试'),
                    ),
            ],
          ),
        ),
      );
    }

    if (_sponsors.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.favorite_border,
                size: 48,
                color: isFluent ? Colors.grey : colorScheme?.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                '暂无赞助用户',
                style: isFluent
                    ? fluent_ui.FluentTheme.of(context).typography.body
                    : Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: _sponsors.map((sponsor) {
        return _buildSponsorCard(context, sponsor, isFluent: isFluent, isCupertino: isCupertino, isDark: isDark, colorScheme: colorScheme);
      }).toList(),
    );
  }

  Widget _buildSponsorCard(
    BuildContext context,
    Map<String, dynamic> sponsor, {
    bool isFluent = false,
    bool isCupertino = false,
    bool isDark = false,
    ColorScheme? colorScheme,
  }) {
    final username = sponsor['username'] as String? ?? '匿名用户';
    final avatarUrl = sponsor['avatarUrl'] as String?;
    final sponsorSince = sponsor['sponsorSince'] as String?;

    // 解析时间
    String timeText = '';
    if (sponsorSince != null) {
      try {
        final date = DateTime.parse(sponsorSince);
        timeText = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      } catch (e) {
        timeText = '';
      }
    }

    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCupertino
            ? (isDark ? Colors.white.withOpacity(0.08) : Colors.grey.withOpacity(0.1))
            : (isFluent
                ? Colors.white.withOpacity(0.05)
                : colorScheme?.surfaceVariant.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCupertino
              ? (isDark ? Colors.white.withOpacity(0.12) : Colors.grey.withOpacity(0.2))
              : (isFluent
                  ? Colors.white.withOpacity(0.1)
                  : colorScheme?.outline.withOpacity(0.3) ?? Colors.grey.withOpacity(0.3)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头像
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: avatarUrl != null
                  ? DecorationImage(
                      image: NetworkImage(avatarUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
              color: avatarUrl == null
                  ? (isCupertino 
                      ? const Color(0xFF007AFF) 
                      : (isFluent ? const Color(0xFF0078D4) : colorScheme?.primary))
                  : null,
            ),
            child: avatarUrl == null
                ? Icon(
                    isCupertino 
                        ? Icons.person
                        : (isFluent ? fluent_ui.FluentIcons.contact : Icons.person),
                    size: 28,
                    color: Colors.white,
                  )
                : null,
          ),
          const SizedBox(height: 8),
          // 用户名
          Text(
            username,
            style: isCupertino
                ? TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  )
                : (isFluent
                    ? fluent_ui.FluentTheme.of(context).typography.body?.copyWith(
                          fontWeight: FontWeight.bold,
                        )
                    : Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (timeText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              timeText,
              style: isCupertino
                  ? TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    )
                  : (isFluent
                      ? fluent_ui.FluentTheme.of(context).typography.caption
                      : Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme?.onSurfaceVariant,
                          )),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
