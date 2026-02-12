import 'dart:io';
import 'dart:math';

import 'api/api_client.dart';

class DonateService {

  static String _generateOutTradeNo() {
    final now = DateTime.now().toUtc();
    final ts = now.millisecondsSinceEpoch;
    final rand = Random().nextInt(900000) + 100000; // 6 digits
    return '$ts$rand';
  }

  static String deviceType() {
    if (Platform.isAndroid || Platform.isIOS) return 'mobile';
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return 'pc';
    return 'pc';
  }

  // v2 签名在后端进行，前端不再参与

  static Future<Map<String, dynamic>> createOrder({
    required String type, // 'alipay' | 'wxpay'
    required String money, // e.g. '1.00'
    required String name, // product name
    required String clientIp,
    String? outTradeNo,
    String? notifyUrl,
    String? returnUrl,
    String? device,
    String? param,
  }) async {
    final req = <String, dynamic>{
      'type': type,
      'name': name,
      'money': money,
      'clientip': clientIp,
      'out_trade_no': outTradeNo ?? _generateOutTradeNo(),
      'method': 'web',
      'device': (device ?? deviceType()),
      if (param != null) 'param': param,
      if (notifyUrl != null) 'notify_url': notifyUrl,
      if (returnUrl != null) 'return_url': returnUrl,
    };

    try {
      print('[DonateService] POST /pay/create');
      print('[DonateService] Request: $req');

      final result = await ApiClient().postJson(
        '/pay/create',
        data: req,
        timeout: const Duration(seconds: 15),
      );

      print('[DonateService] Status: ${result.statusCode}');
      print('[DonateService] Body: ${result.text}');

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('[DonateService] Exception: $e');
      rethrow;
    }
  }

  /// 查询订单状态（v2）
  /// 返回: {'code': 0, 'status': 1} 表示支付成功；兼容旧返回{'code': 1, 'status': '1'}
  static Future<Map<String, dynamic>> queryOrder({
    required String outTradeNo,
  }) async {
    final req = <String, dynamic>{
      'out_trade_no': outTradeNo,
    };

    try {
      print('[DonateService] Query order: $outTradeNo');

      final result = await ApiClient().postJson(
        '/pay/query',
        data: req,
        timeout: const Duration(seconds: 10),
      );

      print('[DonateService] Query Status: ${result.statusCode}');
      print('[DonateService] Query Body: ${result.text}');

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('[DonateService] Query Exception: $e');
      rethrow;
    }
  }

  /// 创建赞助记录
  static Future<Map<String, dynamic>> createDonationRecord({
    required int userId,
    required String outTradeNo,
    required double amount,
    required String paymentType,
  }) async {
    final req = <String, dynamic>{
      'userId': userId,
      'outTradeNo': outTradeNo,
      'amount': amount,
      'paymentType': paymentType,
    };

    try {
      print('[DonateService] Creating donation record: $outTradeNo');

      final result = await ApiClient().postJson(
        '/sponsors/create',
        data: req,
        timeout: const Duration(seconds: 10),
      );

      print('[DonateService] Create donation Status: ${result.statusCode}');
      print('[DonateService] Create donation Body: ${result.text}');

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('[DonateService] Create donation Exception: $e');
      rethrow;
    }
  }

  /// 查询用户赞助状态
  static Future<Map<String, dynamic>> getSponsorStatus({
    required int userId,
  }) async {
    try {
      print('[DonateService] Query sponsor status for user: $userId');

      final result = await ApiClient().getJson(
        '/sponsors/status/$userId',
        timeout: const Duration(seconds: 10),
      );

      print('[DonateService] Sponsor status: ${result.statusCode}');
      print('[DonateService] Sponsor body: ${result.text}');

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('[DonateService] Query sponsor status Exception: $e');
      rethrow;
    }
  }

  /// 获取所有赞助用户列表
  static Future<Map<String, dynamic>> getSponsorList() async {
    try {
      print('[DonateService] Query sponsor list');

      final result = await ApiClient().getJson(
        '/sponsors/list',
        timeout: const Duration(seconds: 10),
      );

      print('[DonateService] Sponsor list status: ${result.statusCode}');
      print('[DonateService] Sponsor list body: ${result.text}');

      return result.data as Map<String, dynamic>;
    } catch (e) {
      print('[DonateService] Query sponsor list Exception: $e');
      rethrow;
    }
  }
}
