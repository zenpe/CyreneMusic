import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'developer_mode_service.dart';
import 'auth_overlay_service.dart';
import 'api/api_client.dart';
import 'api/auth_token_store.dart';
import 'location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

/// 用户信息模型
class User {
  final int id;
  final String email;
  final String username;
  final bool isVerified;
  final String? lastLogin;
  final String? avatarUrl;
  final bool isSponsor;
  final String? sponsorSince;

  User({
    required this.id,
    required this.email,
    required this.username,
    required this.isVerified,
    this.lastLogin,
    this.avatarUrl,
    this.isSponsor = false,
    this.sponsorSince,
  });

  /// 获取用于显示的邮箱
  ///
  /// 如果是 Linux DO 邮箱（通常由于过长且不具辨识度），则不显示
  String? get displayEmail {
    if (email.toLowerCase().contains('linux.do')) {
      return null;
    }
    return email;
  }


  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
      isVerified: json['isVerified'] as bool? ?? false,
      lastLogin: json['lastLogin'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      isSponsor: json['isSponsor'] as bool? ?? false,
      sponsorSince: json['sponsorSince'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'isVerified': isVerified,
      'lastLogin': lastLogin,
      'avatarUrl': avatarUrl,
      'isSponsor': isSponsor,
      'sponsorSince': sponsorSince,
    };
  }
}

/// 认证服务 - 管理用户登录状态
class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal() {
    AuthTokenStore.onUnauthorized = handleUnauthorized;
    _loadUserFromStorage();
  }

  User? _currentUser;
  bool _isLoggedIn = false;
  String? _authToken;
  bool _isHandlingUnauthorized = false;

  // 用于跟踪 Linux Do OAuth 登录的本地服务器
  // 确保在启动新登录前关闭旧服务器，避免端口占用
  HttpServer? _oauthServer;
  Completer<String?>? _oauthCompleter;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;

  String? get token => _authToken;

  /// 从本地存储加载用户信息
  Future<void> _loadUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('current_user');
      final savedToken = prefs.getString('auth_token');
      AuthTokenStore.token = savedToken;

      if (userJson != null && userJson.isNotEmpty) {
        final userData = jsonDecode(userJson);
        _currentUser = User.fromJson(userData);
        _authToken = savedToken;
        _isLoggedIn = _authToken != null && _authToken!.isNotEmpty;
        print('👤 [AuthService] 从本地存储加载用户: ${_currentUser?.username}');
        notifyListeners();
      }
    } catch (e) {
      print('❌ [AuthService] 加载用户信息失败: $e');
    }
  }

  /// 保存用户信息到本地存储
  Future<void> _saveUserToStorage(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user', jsonEncode(user.toJson()));
      print('💾 [AuthService] 用户信息已保存到本地');
    } catch (e) {
      print('❌ [AuthService] 保存用户信息失败: $e');
    }
  }

  Future<void> _saveTokenToStorage(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', token);
      AuthTokenStore.token = token;
    } catch (_) {}
  }

  /// 清除本地存储的用户信息
  Future<void> _clearUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user');
      print('🗑️ [AuthService] 已清除本地用户信息');
    } catch (e) {
      print('❌ [AuthService] 清除用户信息失败: $e');
    }
  }

  Future<void> _clearTokenFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_token');
      AuthTokenStore.token = null;
    } catch (_) {}
  }

  Future<void> loginWithToken({required String token, Map<String, dynamic>? userJson}) async {
    _authToken = token;
    await _saveTokenToStorage(token);

    if (userJson != null && userJson.isNotEmpty) {
      _currentUser = User.fromJson(userJson);
      _isLoggedIn = true;
      await _saveUserToStorage(_currentUser!);
      notifyListeners();
      return;
    }

    // 兜底：通过后端校验 token 并获取用户信息
    final ok = await validateToken();
    if (!ok) {
      await logout();
    }
  }

  /// 检查注册状态
  Future<Map<String, dynamic>> checkRegistrationStatus() async {
    try {
      final result = await ApiClient().getJson(
        '/auth/registration-status',
        auth: false,
      );

      if (result.ok) {
        final body = result.bodyData as Map<String, dynamic>?;
        return {
          'success': true,
          'enabled': body?['enabled'] ?? false,
        };
      } else {
        return {
          'success': false,
          'enabled': false,
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 检查注册状态失败: $e');
      return {
        'success': false,
        'enabled': false,
      };
    }
  }

  /// 检查 Linux Do 登录状态
  Future<Map<String, dynamic>> checkLinuxDoStatus() async {
    try {
      final result = await ApiClient().getJson(
        '/auth/linuxdo-status',
        auth: false,
      );

      if (result.ok) {
        final body = result.bodyData as Map<String, dynamic>?;
        return {
          'success': true,
          'enabled': body?['enabled'] ?? true, // 默认启用
        };
      } else {
        return {
          'success': false,
          'enabled': true, // 请求失败时默认启用
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 检查 Linux Do 登录状态失败: $e');
      return {
        'success': false,
        'enabled': true, // 异常时默认启用
      };
    }
  }

  /// 发送注册验证码
  Future<Map<String, dynamic>> sendRegisterCode({
    required String email,
    required String username,
  }) async {
    try {
      final result = await ApiClient().postJson(
        '/auth/register/send-code',
        data: {
          'email': email,
          'username': username,
        },
        auth: false,
      );

      if (result.ok) {
        DeveloperModeService().addLog('✅ [AuthService] 验证码发送成功');
        return {
          'success': true,
          'message': result.message,
          'data': result.bodyData,
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 验证码发送失败');
        return {
          'success': false,
          'message': result.message ?? '发送验证码失败',
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 网络错误: $e');
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// 用户注册
  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    required String code,
  }) async {
    try {
      final result = await ApiClient().postJson(
        '/auth/register',
        data: {
          'email': email,
          'username': username,
          'password': password,
          'code': code,
        },
        auth: false,
      );

      if (result.ok) {
        DeveloperModeService().addLog('✅ [AuthService] 用户注册成功: $username');
        return {
          'success': true,
          'message': result.message,
          'data': result.bodyData,
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 注册失败');
        return {
          'success': false,
          'message': result.message ?? '注册失败',
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 网络错误: $e');
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// 用户登录
  Future<Map<String, dynamic>> login({
    required String account,
    required String password,
  }) async {
    try {
      final result = await ApiClient().postJson(
        '/auth/login',
        data: {
          'account': account,
          'password': password,
        },
        auth: false,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        _currentUser = User.fromJson(data['data']);
        _authToken = data['data']['token'];
        _isLoggedIn = true;

        // 保存用户信息到本地
        await _saveUserToStorage(_currentUser!);
        if (_authToken != null) {
          await _saveTokenToStorage(_authToken!);
        }

        notifyListeners();

        return {
          'success': true,
          'message': result.message,
          'user': _currentUser,
        };
      } else {
        return {
          'success': false,
          'message': result.message ?? '登录失败',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// Linux Do 授权登录
  Future<Map<String, dynamic>> loginWithLinuxDo() async {
    const clientId = '92bIhRkScTeJvJkb3a6w69xX7RoO7wbB';
    const redirectUri = 'http://127.0.0.1:40555/oauth/callback';
    const authUrl = 'https://connect.linux.do/oauth2/authorize?response_type=code&client_id=$clientId&redirect_uri=$redirectUri&state=login';

    try {
      print('🚀 [AuthService] 准备启动本地服务器...');
      DeveloperModeService().addLog('🚀 [AuthService] 准备启动本地服务器...');

      // 先关闭可能存在的旧服务器（用户多次点击登录时）
      if (_oauthServer != null) {
        print('🔄 [AuthService] 检测到旧服务器，正在关闭...');
        DeveloperModeService().addLog('🔄 [AuthService] 关闭旧的 OAuth 服务器...');
        try {
          await _oauthServer!.close(force: true);
        } catch (_) {}
        _oauthServer = null;
      }

      // 取消旧的 completer（如果存在）
      if (_oauthCompleter != null && !_oauthCompleter!.isCompleted) {
        _oauthCompleter!.complete(null);
      }
      _oauthCompleter = Completer<String?>();

      // 绑定到 127.0.0.1 端口 40555，使用 shared: true 避免端口占用问题
      _oauthServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        40555,
        shared: true, // 允许共享端口，解决多次绑定问题
      );
      print('🌐 [AuthService] 本地监听器运行中: http://127.0.0.1:40555');
      DeveloperModeService().addLog('🌐 [AuthService] 本地监听器运行中: http://127.0.0.1:40555');

      _oauthServer!.listen((HttpRequest request) async {
        final path = request.uri.path;
        final params = request.uri.queryParameters;
        print('📩 [AuthService] 收到 HTTP 请求: $path, 参数: $params');
        DeveloperModeService().addLog('📩 [AuthService] 收到本地 HTTP 请求: $path, 参数: $params');

        if (path == '/oauth/callback' || path == 'oauth/callback') {
          final code = params['code'];
          print('✅ [AuthService] 识别到授权码: ${code?.substring(0, 5)}...');
          DeveloperModeService().addLog('✅ [AuthService] 识别到回调! code: ${code?.substring(0, 5)}...');

          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.html
            ..write('''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>验证成功 - Cyrene Music</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background-color: #f5f5f7;
            color: #1d1d1f;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: white;
            border-radius: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.08);
            max-width: 90%;
            width: 400px;
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
            color: #007aff;
        }
        h1 {
            font-size: 24px;
            margin-bottom: 16px;
            font-weight: 600;
        }
        p {
            font-size: 16px;
            color: #86868b;
            line-height: 1.5;
            margin-bottom: 24px;
        }
        .notice {
            color: #007aff;
            font-weight: 500;
        }
        .btn {
            display: inline-block;
            margin-top: 20px;
            padding: 12px 24px;
            background-color: #007aff;
            color: white;
            text-decoration: none;
            border-radius: 10px;
            font-weight: 500;
            transition: opacity 0.2s;
        }
        .btn:active {
            opacity: 0.8;
        }
        .countdown {
            font-size: 14px;
            color: #86868b;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">✅</div>
        <h1>验证成功</h1>
        <p>授权码已成功捕获。</p>
        <p class="notice" id="notice">正在为您返回 Cyrene Music...</p>
        <div class="countdown" id="timer">正在处理授权信息...</div>
    </div>
    <script>
        var isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);

        if (isMobile) {
            // 移动端：不自动跳转 Deep Link，因为这可能导致应用状态丢失
            // 授权码已被本地服务器捕获，用户只需返回应用即可
            document.getElementById('notice').innerText = '授权成功！';
            document.getElementById('timer').innerText = '请手动返回 Cyrene Music 应用完成登录';
        } else {
            // 桌面端提示
            document.getElementById('timer').innerText = "授权成功，应用窗口已尝试自动激活";
        }
    </script>
</body>
</html>
''');

          await request.response.close();
          print('📤 [AuthService] 已发送响应给浏览器');

          // 桌面端：收到回调后自动激活并置顶窗口
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
            try {
              await windowManager.show();
              await windowManager.focus();
              print('🪟 [AuthService] 已尝试激活并置顶桌面端窗口');
            } catch (e) {
              print('⚠️ [AuthService] 激活窗口失败: $e');
            }
          }

          if (!_oauthCompleter!.isCompleted) {
            _oauthCompleter!.complete(code);
            print('🔔 [AuthService] Completer 已触发完结');
          }
        } else {
          request.response
            ..statusCode = 404
            ..write('Not Found');
          await request.response.close();
        }
      }, onError: (e) {
        print('❌ [AuthService] HttpServer 监听出错: $e');
      });

      // 直接尝试启动浏览器，不依赖 canLaunchUrl 的预检查
      // 原因: canLaunchUrl 在 Android 11+ 和某些 Windows 设备上可能误报 false
      print('🔗 [AuthService] 正在打开浏览器...');
      DeveloperModeService().addLog('🔗 [AuthService] 正在打开浏览器: $authUrl');

      try {
        final launched = await launchUrl(
          Uri.parse(authUrl),
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          print('❌ [AuthService] launchUrl 返回 false');
          DeveloperModeService().addLog('❌ [AuthService] launchUrl 返回 false，浏览器可能未正确启动');
          // 不立即抛出异常，给用户一个机会手动打开链接
          // 某些设备上 launchUrl 返回 false 但浏览器实际上已经打开
        }
      } catch (launchError) {
        print('❌ [AuthService] 启动浏览器失败: $launchError');
        DeveloperModeService().addLog('❌ [AuthService] 启动浏览器失败: $launchError');
        throw '无法启动浏览器: $launchError';
      }

      print('⏳ [AuthService] 等待授权码返回...');
      final code = await _oauthCompleter!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          print('⏰ [AuthService] 登录超时');
          return null;
        },
      );

      if (code == null) {
        return {'success': false, 'message': '登录超时'};
      }

      print('🔑 [AuthService] 获得授权码，开始请求后端登录...');
      final result = await ApiClient().postJson(
        '/auth/linuxdo/login',
        data: {'code': code},
        auth: false,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        print('🔍 [AuthService] 后端返回数据: ${jsonEncode(data['data'])}');
        print('🖼️ [AuthService] 头像URL: ${data['data']?['avatarUrl']}');
        DeveloperModeService().addLog('🖼️ [Auth] Linux Do 头像 URL: ${data['data']?['avatarUrl']}');

        _currentUser = User.fromJson(data['data']);
        _authToken = data['data']['token'];
        _isLoggedIn = true;

        await _saveUserToStorage(_currentUser!);
        if (_authToken != null) {
          await _saveTokenToStorage(_authToken!);
        }

        notifyListeners();
        print('🎉 [AuthService] Linux Do 最终登录成功: ${_currentUser?.username}');
        return {'success': true, 'message': '登录成功'};
      } else {
        final data = result.data as Map<String, dynamic>?;
        print('❌ [AuthService] 后端通过授权码登录失败: ${data?['message']}');
        return {'success': false, 'message': data?['message'] ?? '验证失败'};
      }
    } catch (e) {
      print('💥 [AuthService] 异常: $e');
      return {'success': false, 'message': '登录异常: $e'};
    } finally {
      print('🏁 [AuthService] 关闭本地监听服务器');
      try {
        await _oauthServer?.close(force: true);
      } catch (_) {}
      _oauthServer = null;
    }
  }

  /// Linux Do 授权登录 - 使用授权码（适用于 WebView 方式）
  ///
  /// 当通过 WebView 获取到授权码后，调用此方法完成登录
  Future<Map<String, dynamic>> loginWithLinuxDoCode(String code) async {
    try {
      print('🔑 [AuthService] 使用授权码登录 Linux Do...');
      DeveloperModeService().addLog('🔑 [AuthService] 使用授权码登录...');

      final result = await ApiClient().postJson(
        '/auth/linuxdo/login',
        data: {'code': code},
        auth: false,
      );

      if (result.ok) {
        final data = result.data as Map<String, dynamic>;
        print('🔍 [AuthService] 后端返回数据: ${jsonEncode(data['data'])}');
        print('🖼️ [AuthService] 头像URL: ${data['data']?['avatarUrl']}');
        DeveloperModeService().addLog('🖼️ [Auth] Linux Do 头像 URL: ${data['data']?['avatarUrl']}');

        _currentUser = User.fromJson(data['data']);
        _authToken = data['data']['token'];
        _isLoggedIn = true;

        await _saveUserToStorage(_currentUser!);
        if (_authToken != null) {
          await _saveTokenToStorage(_authToken!);
        }

        notifyListeners();
        print('🎉 [AuthService] Linux Do 授权码登录成功: ${_currentUser?.username}');
        DeveloperModeService().addLog('🎉 [AuthService] Linux Do 授权码登录成功');
        return {'success': true, 'message': '登录成功'};
      } else {
        final data = result.data as Map<String, dynamic>?;
        print('❌ [AuthService] 后端通过授权码登录失败: ${data?['message']}');
        DeveloperModeService().addLog('❌ [AuthService] 授权码登录失败: ${data?['message']}');
        return {'success': false, 'message': data?['message'] ?? '验证失败'};
      }
    } catch (e) {
      print('💥 [AuthService] 授权码登录异常: $e');
      DeveloperModeService().addLog('💥 [AuthService] 授权码登录异常: $e');
      return {'success': false, 'message': '登录异常: $e'};
    }
  }


  /// 发送重置密码验证码
  Future<Map<String, dynamic>> sendResetCode({
    required String email,
  }) async {
    try {
      final result = await ApiClient().postJson(
        '/auth/reset-password/send-code',
        data: {'email': email},
        auth: false,
      );

      if (result.ok) {
        DeveloperModeService().addLog('✅ [AuthService] 重置验证码发送成功');
        return {
          'success': true,
          'message': result.message,
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 验证码发送失败');
        return {
          'success': false,
          'message': result.message ?? '发送验证码失败',
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 网络错误: $e');
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// 重置密码
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    try {
      final result = await ApiClient().postJson(
        '/auth/reset-password',
        data: {
          'email': email,
          'code': code,
          'newPassword': newPassword,
        },
        auth: false,
      );

      if (result.ok) {
        DeveloperModeService().addLog('✅ [AuthService] 密码重置成功');
        return {
          'success': true,
          'message': result.message,
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 密码重置失败');
        return {
          'success': false,
          'message': result.message ?? '重置密码失败',
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 网络错误: $e');
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// 登出
  Future<void> logout() async {
    final username = _currentUser?.username;
    _currentUser = null;
    _isLoggedIn = false;
    _authToken = null;

    // 清除本地存储
    await _clearUserFromStorage();
    await _clearTokenFromStorage();

    // 清除收藏列表（需要在这里导入 FavoriteService，但为避免循环依赖，改为在 FavoriteService 中监听登出）

    DeveloperModeService().addLog('👋 [AuthService] 用户退出登录: $username');

    notifyListeners();
  }

  Future<bool> validateToken() async {
    if (_authToken == null || _authToken!.isEmpty) {
      return false;
    }
    try {
      final result = await ApiClient().getJson('/auth/validate-token');
      if (result.ok) {
        final body = result.bodyData as Map<String, dynamic>;
        _currentUser = User.fromJson(body);
        _isLoggedIn = true;
        notifyListeners();
        return true;
      }
      await handleUnauthorized();
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> handleUnauthorized() async {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;
    try {
      await logout();
      print('当前登录态已失效，请重新登录');
      AuthOverlayService().show();
    } finally {
      _isHandlingUnauthorized = false;
    }
  }

  /// 更新用户名
  Future<Map<String, dynamic>> updateUsername(String newUsername) async {
    if (_authToken == null || _authToken!.isEmpty) {
      return {
        'success': false,
        'message': '未登录',
      };
    }

    try {
      final result = await ApiClient().postJson(
        '/auth/update-username',
        data: {
          'newUsername': newUsername,
        },
      );

      if (result.ok) {
        // 更新本地用户信息
        if (_currentUser != null) {
          _currentUser = User(
            id: _currentUser!.id,
            email: _currentUser!.email,
            username: newUsername,
            isVerified: _currentUser!.isVerified,
            lastLogin: _currentUser!.lastLogin,
            avatarUrl: _currentUser!.avatarUrl,
            isSponsor: _currentUser!.isSponsor,
            sponsorSince: _currentUser!.sponsorSince,
          );
          await _saveUserToStorage(_currentUser!);
          notifyListeners();
        }

        return {
          'success': true,
          'message': result.message ?? '用户名更新成功',
        };
      } else {
        return {
          'success': false,
          'message': result.message ?? '更新用户名失败',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }

  /// 更新用户IP归属地
  Future<Map<String, dynamic>> updateLocation() async {
    // 检查用户是否已登录
    if (!_isLoggedIn || _currentUser == null) {
      DeveloperModeService().addLog('⚠️ [AuthService] 用户未登录，无法更新IP归属地');
      return {
        'success': false,
        'message': '用户未登录',
      };
    }

    try {
      // 获取IP归属地信息
      DeveloperModeService().addLog('🌍 [AuthService] 开始获取IP归属地...');
      final locationInfo = await LocationService().fetchLocation();

      if (locationInfo == null) {
        DeveloperModeService().addLog('❌ [AuthService] 获取IP归属地失败');
        return {
          'success': false,
          'message': '获取IP归属地失败',
        };
      }

      // 准备发送到后端的数据
      final requestBody = {
        'userId': _currentUser!.id,
        'ip': locationInfo.ip,
        'location': locationInfo.shortDescription,
      };

      final result = await ApiClient().postJson(
        '/auth/update-location',
        data: requestBody,
      );

      if (result.ok) {
        DeveloperModeService().addLog('✅ [AuthService] IP归属地更新成功: ${locationInfo.shortDescription}');
        return {
          'success': true,
          'message': result.message,
          'data': {
            'ip': locationInfo.ip,
            'location': locationInfo.shortDescription,
          },
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] IP归属地更新失败');
        return {
          'success': false,
          'message': result.message ?? '更新IP归属地失败',
        };
      }
    } catch (e) {
      DeveloperModeService().addLog('❌ [AuthService] 更新IP归属地异常: $e');
      return {
        'success': false,
        'message': '网络错误: ${e.toString()}',
      };
    }
  }
}
