import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/donate_service.dart';
import '../../services/location_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/fluent_settings_card.dart';
import '../../utils/theme_manager.dart';

class DonateSettings extends StatefulWidget {
  const DonateSettings({super.key});

  @override
  State<DonateSettings> createState() => _DonateSettingsState();
}

class _DonateSettingsState extends State<DonateSettings> {
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    if (isFluent) {
      return FluentSettingsGroup(
        title: '支持与赞助',
        children: [
          FluentSettingsTile(
            icon: fluent_ui.FluentIcons.heart,
            title: '赞助项目',
            subtitle: '您的支持是我们持续维护与改进的动力',
            trailing: const Icon(Icons.chevron_right),
            onTap: _onDonateTap,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, '支持与赞助'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('赞助项目'),
            subtitle: const Text('您的支持是我们持续维护与改进的动力'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _onDonateTap,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Future<void> _onDonateTap() async {
    print('[Donate] Open donate dialog');
    final result = await _showDonateDialog(context);
    if (result == null) return;

    final String method = result.method; // 'alipay' | 'wxpay'
    final double amount = result.amount;

    print('[Donate] Selected method=$method amount=${amount.toStringAsFixed(2)}');
    setState(() => _submitting = true);

    try {
      // Ensure client IP
      String? ip = LocationService().currentLocation?.ip;
      ip ??= (await LocationService().fetchLocation())?.ip;
      if (ip == null || ip.isEmpty) {
        print('[Donate] Failed to get client IP');
        _showSnack('获取IP失败，请稍后重试');
        return;
      }

      // Generate order number
      final outTradeNo = _generateOutTradeNo();
      print('[Donate] clientip=$ip, creating order: $outTradeNo');
      
      // 获取当前用户ID（如果已登录）
      final userId = AuthService().currentUser?.id;
      
      // 先创建赞助记录
      if (userId != null) {
        try {
          await DonateService.createDonationRecord(
            userId: userId,
            outTradeNo: outTradeNo,
            amount: amount,
            paymentType: method,
          );
          print('[Donate] 赞助记录已创建');
        } catch (e) {
          print('[Donate] 创建赞助记录失败: $e');
          // 继续执行，不影响支付流程
        }
      }
      
      final data = await DonateService.createOrder(
        type: method,
        money: amount.toStringAsFixed(2),
        name: 'CyreneMusic赞助${amount.toStringAsFixed(0)}元',
        clientIp: ip,
        outTradeNo: outTradeNo,
      );

      if (!mounted) return;

      print('[Donate] Response: $data');
      // v2: code == 0 表示成功；兼容旧版 code == 1
      final bool ok = data['code'] == 0 || data['code'] == 1;
      if (ok) {
        // v2 首选: pay_type + pay_info
        final String? payInfo = data['pay_info'] as String?;
        // 兼容旧字段
        final String? qrcode = (data['qrcode'] as String?) ?? (data['payurl'] as String?) ?? (data['urlscheme'] as String?);

        final String? qrData = (payInfo != null && payInfo.isNotEmpty)
            ? payInfo
            : (qrcode != null && qrcode.isNotEmpty)
                ? qrcode
                : null;

        if (qrData != null) {
          print('[Donate] Showing QR dialog with polling');
          final paymentSuccess = await _showQrDialogWithPolling(context, qrData, outTradeNo);
          if (paymentSuccess && mounted) {
            _showSnack('感谢您的赞助！');
            
            // 支付成功后，重新登录以刷新用户状态（包括赞助状态）
            final currentUser = AuthService().currentUser;
            if (currentUser != null) {
              print('[Donate] 支付成功，刷新用户状态...');
              // 触发 AuthService 的监听器，让用户卡片重新查询赞助状态
              AuthService().notifyListeners();
            }
          }
        } else {
          print('[Donate] No pay data returned');
          _showSnack('下单成功，但未返回支付数据');
        }
      } else {
        print('[Donate] Create order failed: ${data['msg']}');
        _showSnack('下单失败: ${data['msg'] ?? '未知错误'}');
      }
    } catch (e) {
      if (!mounted) return;
      print('[Donate] Exception: $e');
      _showSnack('请求失败: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await canLaunchUrl(uri)) {
      throw Exception('无法打开支付链接');
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _generateOutTradeNo() {
    final now = DateTime.now().toUtc();
    final ts = now.millisecondsSinceEpoch;
    final rand = Random().nextInt(900000) + 100000; // 6 digits
    return '$ts$rand';
  }
}

class _DonateFormResult {
  final String method; // 'alipay' | 'wxpay'
  final double amount;
  _DonateFormResult(this.method, this.amount);
}

Future<_DonateFormResult?> _showDonateDialog(BuildContext context) async {
  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
  final bool isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
  double amount = 6.0;
  String method = 'alipay';
  final TextEditingController customCtrl = TextEditingController();
  String? errorText;

  // iOS Cupertino 风格对话框
  if (isCupertino) {
    return await showCupertinoModalPopup<_DonateFormResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
            return Material(
              type: MaterialType.transparency,
              child: Container(
                height: MediaQuery.of(context).size.height * 0.75,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                children: [
                  // 顶部拖动指示器和标题
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.2),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey3,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                '取消',
                                style: TextStyle(color: ThemeManager.iosBlue),
                              ),
                            ),
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.heart_fill,
                                  color: CupertinoColors.systemRed,
                                  size: 20,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '赞助支持',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                  ),
                                ),
                              ],
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                // 优先使用自定义金额
                                final a = _resolveAmount(amount, customCtrl.text);
                                if (a == null) {
                                  setState(() => errorText = '请输入有效金额（最低1元，最多两位小数）');
                                  return;
                                }
                                Navigator.pop(context, _DonateFormResult(method, a));
                              },
                              child: Text(
                                '确定',
                                style: TextStyle(
                                  color: ThemeManager.iosBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 内容区域
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 说明文字
                          Text(
                            '赞助后您可以获得独特的用户标识',
                            style: TextStyle(
                              fontSize: 15,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '是否赞助不影响任何功能',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '赞助任意金额您的名字将被永久保留在赞助墙上。',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: ThemeManager.iosBlue,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // 金额选择
                          Text(
                            '选择金额',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _buildCupertinoAmountCard(context, 3.0, '来瓶可乐', amount == 3.0 && customCtrl.text.isEmpty, isDark, () => setState(() {
                                amount = 3.0;
                                customCtrl.clear();
                              })),
                              _buildCupertinoAmountCard(context, 6.0, '投喂面包', amount == 6.0 && customCtrl.text.isEmpty, isDark, () => setState(() {
                                amount = 6.0;
                                customCtrl.clear();
                              })),
                              _buildCupertinoAmountCard(context, 10.0, '名垂千古', amount == 10.0 && customCtrl.text.isEmpty, isDark, () => setState(() {
                                amount = 10.0;
                                customCtrl.clear();
                              })),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // 自定义金额输入
                          CupertinoTextField(
                            controller: customCtrl,
                            placeholder: '自定义金额 (单位：元)',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.08) : CupertinoColors.systemGrey6,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            onChanged: (value) => setState(() {
                              // 当用户输入自定义金额时，保持预设金额变量但视觉上取消选中
                            }),
                          ),
                          const SizedBox(height: 20),
                          // 支付方式选择
                          Text(
                            '支付方式',
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.08) : CupertinoColors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                _buildCupertinoPaymentTile(
                                  context,
                                  '支付宝',
                                  CupertinoIcons.money_dollar_circle,
                                  const Color(0xFF1677FF),
                                  method == 'alipay',
                                  isDark,
                                  () => setState(() => method = 'alipay'),
                                ),
                                Container(
                                  height: 0.5,
                                  margin: const EdgeInsets.only(left: 50),
                                  color: isDark ? Colors.white.withOpacity(0.1) : CupertinoColors.systemGrey5,
                                ),
                                _buildCupertinoPaymentTile(
                                  context,
                                  '微信支付',
                                  CupertinoIcons.chat_bubble_2,
                                  const Color(0xFF07C160),
                                  method == 'wxpay',
                                  isDark,
                                  () => setState(() => method = 'wxpay'),
                                ),
                              ],
                            ),
                          ),
                          if (errorText != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              errorText!,
                              style: TextStyle(
                                color: CupertinoColors.systemRed,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
            );
          },
        );
      },
    );
  }

  if (isFluent) {
    return await fluent_ui.showDialog<_DonateFormResult>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final typo = fluent_ui.FluentTheme.of(context).typography;
            return fluent_ui.ContentDialog(
              title: Row(
                children: [
                  const Icon(Icons.favorite, size: 18),
                  const SizedBox(width: 8),
                  Text('赞助支持', style: typo.subtitle),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('赞助后您可以获得独特的用户标识', style: typo.body),
                    const SizedBox(height: 4),
                    Text('是否赞助不影响任何功能', style: typo.caption),
                    const SizedBox(height: 4),
                    Text('赞助任意金额您的名字将被永久保留在赞助墙上。', style: typo.body?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text('选择金额', style: typo.caption),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => amount = 3.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: amount == 3.0 ? fluent_ui.Colors.blue : fluent_ui.Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: SizedBox(
                              width: 150,
                              child: fluent_ui.Card(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥3', style: typo.body?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('来瓶可乐', style: typo.caption),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => amount = 6.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: amount == 6.0 ? fluent_ui.Colors.blue : fluent_ui.Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: SizedBox(
                              width: 150,
                              child: fluent_ui.Card(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥6', style: typo.body?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('投喂面包', style: typo.caption),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => amount = 10.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: amount == 10.0 ? fluent_ui.Colors.blue : fluent_ui.Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: SizedBox(
                              width: 150,
                              child: fluent_ui.Card(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥10', style: typo.body?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('名垂千古', style: typo.caption),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: fluent_ui.TextBox(
                        controller: customCtrl,
                        placeholder: '自定义金额 (元)',
                        inputFormatters: [],
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('支付方式', style: typo.caption),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        fluent_ui.RadioButton(
                          content: const Text('支付宝'),
                          checked: method == 'alipay',
                          onChanged: (v) => setState(() => method = 'alipay'),
                        ),
                        const SizedBox(width: 12),
                        fluent_ui.RadioButton(
                          content: const Text('微信支付'),
                          checked: method == 'wxpay',
                          onChanged: (v) => setState(() => method = 'wxpay'),
                        ),
                      ],
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(errorText!, style: typo.caption?.copyWith(color: fluent_ui.Colors.red)),
                    ],
                  ],
                ),
              ),
              actions: [
                fluent_ui.Button(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                fluent_ui.FilledButton(
                  onPressed: () {
                    final a = _resolveAmount(amount, customCtrl.text);
                    if (a == null) {
                      setState(() => errorText = '请输入有效金额，最小1元，最多两位小数');
                      return;
                    }
                    Navigator.pop(context, _DonateFormResult(method, a));
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  return await showDialog<_DonateFormResult>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.favorite),
                SizedBox(width: 8),
                Text('赞助支持'),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('赞助后您可以获得独特的用户标识', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('是否赞助不影响任何功能', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '赞助任意金额您的名字将被永久保留在赞助墙上。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text('选择金额', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InkWell(
                        onTap: () => setState(() => amount = 3.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: amount == 3.0 ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: SizedBox(
                            width: 160,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥3', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('来瓶可乐', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => amount = 6.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: amount == 6.0 ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: SizedBox(
                            width: 160,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥6', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('投喂面包', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => setState(() => amount = 10.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: amount == 10.0 ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: SizedBox(
                            width: 160,
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('¥10', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('名垂千古', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: customCtrl,
                      decoration: const InputDecoration(
                        hintText: '自定义金额 (元)'
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('支付方式', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Radio<String>(
                        value: 'alipay',
                        groupValue: method,
                        onChanged: (v) => setState(() => method = v!),
                      ),
                      const Text('支付宝'),
                      const SizedBox(width: 12),
                      Radio<String>(
                        value: 'wxpay',
                        groupValue: method,
                        onChanged: (v) => setState(() => method = v!),
                      ),
                      const Text('微信支付'),
                    ],
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final a = _resolveAmount(amount, customCtrl.text);
                  if (a == null) {
                    setState(() => errorText = '请输入有效金额，最小1元，最多两位小数');
                    return;
                  }
                  Navigator.pop(context, _DonateFormResult(method, a));
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
    },
  );
}

// Parse custom input if any; validate 2 decimals, min 1 yuan
double? _tryParseMoney(String s) {
  if (s.trim().isEmpty) return null;
  final reg = RegExp(r'^\d{1,6}(?:\.\d{1,2})?$');
  if (!reg.hasMatch(s.trim())) return null;
  final amount = double.tryParse(s.trim());
  if (amount == null || amount < 1.0) return null; // 最小1元
  return amount;
}

double? _resolveAmount(double preset, String custom) {
  final c = _tryParseMoney(custom);
  if (c != null) return c;
  return preset;
}

/// 显示二维码对话框（不带轮询，用于支付宝等）
Future<void> _showQrDialog(BuildContext context, String data) async {
  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
  final bool isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
  
  // iOS Cupertino 风格
  if (isCupertino) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    await showCupertinoModalPopup(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '扫码支付',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '关闭',
                  style: TextStyle(color: ThemeManager.iosBlue),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
    return;
  }
  
  if (isFluent) {
    await fluent_ui.showDialog(
      context: context,
      builder: (context) => fluent_ui.ContentDialog(
        title: const Text('扫码支付'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              fluent_ui.Card(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: Center(
                    child: QrImageView(
                      data: data,
                      version: QrVersions.auto,
                      size: 200,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                data,
                style: fluent_ui.FluentTheme.of(context).typography.caption,
              ),
            ],
          ),
        ),
        actions: [
          fluent_ui.Button(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('扫码支付'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Center(
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              data,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 显示二维码对话框并轮询支付状态
/// 返回 true 表示支付成功，false 表示用户手动关闭
Future<bool> _showQrDialogWithPolling(
  BuildContext context,
  String qrData,
  String outTradeNo,
) async {
  final bool isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
  final bool isCupertino = (Platform.isIOS || Platform.isAndroid) && ThemeManager().isCupertinoFramework;
  
  // 创建一个 Completer 用于控制对话框关闭
  final completer = Completer<void>();
  Timer? pollTimer;
  bool isPolling = true;
  bool paymentSuccess = false;

  // 开始轮询支付状态
  void startPolling() {
    print('[Donate] Start polling order status: $outTradeNo');
    pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!isPolling) {
        timer.cancel();
        return;
      }

      try {
        final result = await DonateService.queryOrder(outTradeNo: outTradeNo);
        print('[Donate] Poll result: $result');
        
        final code = result['code'];
        if (code == 0 || code == 1) {
          // v2/v1 统一：status == 1 表示支付成功
          final status = result['status'];
          if (status == "1" || status == 1) {
            print('[Donate] Payment success! Closing dialog...');
            timer.cancel();
            isPolling = false;
            paymentSuccess = true;
            if (!completer.isCompleted) {
              completer.complete();
            }
          }
        }
      } catch (e) {
        print('[Donate] Poll error: $e');
        // 继续轮询，不中断
      }
    });
  }

  startPolling();

  // 显示对话框 - Cupertino 版本
  if (isCupertino) {
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;
    final dialogFuture = showCupertinoModalPopup(
      context: context,
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '扫码支付',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '请使用手机扫码支付',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? CupertinoColors.white : CupertinoColors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '支付成功后将自动关闭',
                style: TextStyle(
                  fontSize: 12,
                  color: CupertinoColors.systemGrey,
                ),
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  '关闭',
                  style: TextStyle(color: ThemeManager.iosBlue),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );

    // 等待对话框关闭或支付成功
    await Future.any([
      dialogFuture.then((_) {
        print('[Donate] Dialog closed by user');
        isPolling = false;
        pollTimer?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      }),
      completer.future.then((_) {
        if (paymentSuccess && context.mounted) {
          Navigator.of(context).pop();
        }
      }),
    ]);
    
    pollTimer?.cancel();
    return paymentSuccess;
  }

  // 显示对话框 - Fluent UI 版本
  final dialogFuture = isFluent
      ? fluent_ui.showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => fluent_ui.ContentDialog(
            title: const Text('扫码支付'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fluent_ui.Card(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(
                        child: QrImageView(
                          data: qrData,
                          version: QrVersions.auto,
                          size: 200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请使用手机扫码支付',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支付成功后将自动关闭',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              fluent_ui.Button(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        )
      : showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            title: const Text('扫码支付'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 200,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请使用手机扫码支付',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '支付成功后将自动关闭',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );

  // 等待对话框关闭或支付成功
  await Future.any([
    dialogFuture.then((_) {
      print('[Donate] Dialog closed by user');
      isPolling = false;
      pollTimer?.cancel();
    }),
    completer.future.then((_) {
      print('[Donate] Payment completed, closing dialog');
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }),
  ]);

  // 清理
  isPolling = false;
  pollTimer?.cancel();
  
  return paymentSuccess;
}

extension _SnackExt on _DonateSettingsState {
  void _showSnack(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
      return;
    }
    // Fallback for Fluent UI pages without ScaffoldMessenger
    final isFluent = fluent_ui.FluentTheme.maybeOf(context) != null;
    if (isFluent) {
      fluent_ui.showDialog(
        context: context,
        builder: (context) => fluent_ui.ContentDialog(
          content: Text(text),
          actions: [
            fluent_ui.Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }
}

/// 构建 iOS 风格的金额选择卡片
Widget _buildCupertinoAmountCard(
  BuildContext context,
  double amount,
  String description,
  bool isSelected,
  bool isDark,
  VoidCallback onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: (MediaQuery.of(context).size.width - 52) / 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? ThemeManager.iosBlue.withOpacity(0.15)
            : (isDark ? Colors.white.withOpacity(0.08) : CupertinoColors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? ThemeManager.iosBlue
              : (isDark ? Colors.white.withOpacity(0.1) : CupertinoColors.systemGrey5),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '¥${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isSelected
                  ? ThemeManager.iosBlue
                  : (isDark ? CupertinoColors.white : CupertinoColors.black),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 12,
              color: isSelected
                  ? ThemeManager.iosBlue
                  : CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 构建 iOS 风格的支付方式选择项
Widget _buildCupertinoPaymentTile(
  BuildContext context,
  String title,
  IconData icon,
  Color iconColor,
  bool isSelected,
  bool isDark,
  VoidCallback onTap,
) {
  return CupertinoButton(
    padding: EdgeInsets.zero,
    onPressed: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              color: CupertinoColors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? CupertinoColors.white : CupertinoColors.black,
              ),
            ),
          ),
          Icon(
            isSelected
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.circle,
            color: isSelected ? ThemeManager.iosBlue : CupertinoColors.systemGrey3,
            size: 22,
          ),
        ],
      ),
    ),
  );
}
