import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'developer_mode_service.dart';
import 'url_service.dart';
import 'auth_overlay_service.dart';
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
    _loadUserFromStorage();
  }

  User? _currentUser;
  bool _isLoggedIn = false;
  String? _authToken;

  User? get currentUser => _currentUser;
  bool get isLoggedIn => _isLoggedIn;
  
  String? get token => _authToken;

  /// 从本地存储加载用户信息
  Future<void> _loadUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString('current_user');
      final savedToken = prefs.getString('auth_token');
      
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
      final url = '${UrlService().baseUrl}/auth/registration-status';

      DeveloperModeService().addLog('🌐 [Network] GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'enabled': data['data']['enabled'] ?? false,
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

  /// 发送注册验证码
  Future<Map<String, dynamic>> sendRegisterCode({
    required String email,
    required String username,
  }) async {
    try {
      final url = '${UrlService().baseUrl}/auth/register/send-code';
      final requestBody = {
        'email': email,
        'username': username,
      };
      
      DeveloperModeService().addLog('🌐 [Network] POST $url');
      DeveloperModeService().addLog('📤 [Network] 请求体: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        DeveloperModeService().addLog('✅ [AuthService] 验证码发送成功');
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 验证码发送失败');
        return {
          'success': false,
          'message': data['message'] ?? '发送验证码失败',
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
      final url = '${UrlService().baseUrl}/auth/register';
      final requestBody = {
        'email': email,
        'username': username,
        'password': '***', // 密码不记录
        'code': code,
      };
      
      DeveloperModeService().addLog('🌐 [Network] POST $url');
      DeveloperModeService().addLog('📤 [Network] 请求体: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': username,
          'password': password,
          'code': code,
        }),
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        DeveloperModeService().addLog('✅ [AuthService] 用户注册成功: $username');
        return {
          'success': true,
          'message': data['message'],
          'data': data['data'],
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 注册失败');
        return {
          'success': false,
          'message': data['message'] ?? '注册失败',
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
      final response = await http.post(
        Uri.parse('${UrlService().baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'account': account,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
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
          'message': data['message'],
          'user': _currentUser,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? '登录失败',
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

    HttpServer? server;
    final completer = Completer<String?>();

    try {
      print('🚀 [AuthService] 准备启动本地服务器...');
      DeveloperModeService().addLog('🚀 [AuthService] 准备启动本地服务器...');
      
      // 绑定到 127.0.0.1 端口 40555
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 40555);
      print('🌐 [AuthService] 本地监听器运行中: http://127.0.0.1:40555');
      DeveloperModeService().addLog('🌐 [AuthService] 本地监听器运行中: http://127.0.0.1:40555');

      server.listen((HttpRequest request) async {
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
        <p class="notice">正在为您返回 Cyrene Music...</p>
        <a href="cyrenemusic://callback" class="btn" id="manualBtn">手动返回应用</a>
        <div class="countdown" id="timer">正在处理授权信息...</div>
    </div>
    <script>
        var isMobile = /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
        var seconds = 3;
        
        if (isMobile) {
            var timer = setInterval(function() {
                seconds--;
                document.getElementById('timer').innerText = seconds + " 秒后自动跳转";
                if (seconds <= 0) {
                    clearInterval(timer);
                    window.location.href = "cyrenemusic://callback";
                }
            }, 1000);
        } else {
            // 桌面端提示
            document.getElementById('timer').innerText = "授权成功，应用窗口已尝试自动激活";
            document.getElementById('manualBtn').style.display = "none"; 
        }
        
        // 尝试立即跳转（仅移动端）
        if (isMobile) {
            window.location.href = "cyrenemusic://callback";
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
          
          if (!completer.isCompleted) {
            completer.complete(code);
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

      if (await canLaunchUrl(Uri.parse(authUrl))) {
        print('🔗 [AuthService] 正在打开浏览器...');
        await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
      } else {
        throw '无法启动浏览器';
      }

      print('⏳ [AuthService] 等待授权码返回...');
      final code = await completer.future.timeout(
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
      final response = await http.post(
        Uri.parse('${UrlService().baseUrl}/auth/linuxdo/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code}),
      );

      print('📥 [AuthService] 后端响应状态: ${response.statusCode}');
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
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
        print('❌ [AuthService] 后端通过授权码登录失败: ${data['message']}');
        return {'success': false, 'message': data['message'] ?? '验证失败'};
      }
    } catch (e) {
      print('💥 [AuthService] 异常: $e');
      return {'success': false, 'message': '登录异常: $e'};
    } finally {
      print('🏁 [AuthService] 关闭本地监听服务器');
      await server?.close(force: true);
    }
  }

  /// 发送重置密码验证码
  Future<Map<String, dynamic>> sendResetCode({
    required String email,
  }) async {
    try {
      final url = '${UrlService().baseUrl}/auth/reset-password/send-code';
      final requestBody = {'email': email};
      
      DeveloperModeService().addLog('🌐 [Network] POST $url');
      DeveloperModeService().addLog('📤 [Network] 请求体: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        DeveloperModeService().addLog('✅ [AuthService] 重置验证码发送成功');
        return {
          'success': true,
          'message': data['message'],
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 验证码发送失败');
        return {
          'success': false,
          'message': data['message'] ?? '发送验证码失败',
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
      final url = '${UrlService().baseUrl}/auth/reset-password';
      final requestBody = {
        'email': email,
        'code': code,
        'newPassword': '***', // 密码不记录
      };
      
      DeveloperModeService().addLog('🌐 [Network] POST $url');
      DeveloperModeService().addLog('📤 [Network] 请求体: ${jsonEncode(requestBody)}');
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
          'newPassword': newPassword,
        }),
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');
      
      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        DeveloperModeService().addLog('✅ [AuthService] 密码重置成功');
        return {
          'success': true,
          'message': data['message'],
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] 密码重置失败');
        return {
          'success': false,
          'message': data['message'] ?? '重置密码失败',
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
      final url = '${UrlService().baseUrl}/auth/validate-token';
      final r = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $_authToken'},
      );
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        _currentUser = User.fromJson(data['data']);
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
    await logout();
    print('当前登录态已失效，请重新登录');
    AuthOverlayService().show();
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
      final response = await http.post(
        Uri.parse('${UrlService().baseUrl}/auth/update-username'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_authToken',
        },
        body: jsonEncode({
          'newUsername': newUsername,
        }),
      );

      final data = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
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
          'message': data['message'] ?? '用户名更新成功',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? '更新用户名失败',
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
      final url = '${UrlService().baseUrl}/auth/update-location';
      final requestBody = {
        'userId': _currentUser!.id,
        'ip': locationInfo.ip,
        'location': locationInfo.shortDescription,
      };

      DeveloperModeService().addLog('🌐 [Network] POST $url');
      DeveloperModeService().addLog('📤 [Network] 请求体: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      DeveloperModeService().addLog('📥 [Network] 状态码: ${response.statusCode}');
      DeveloperModeService().addLog('📄 [Network] 响应体: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        DeveloperModeService().addLog('✅ [AuthService] IP归属地更新成功: ${locationInfo.shortDescription}');
        return {
          'success': true,
          'message': data['message'],
          'data': {
            'ip': locationInfo.ip,
            'location': locationInfo.shortDescription,
          },
        };
      } else {
        DeveloperModeService().addLog('❌ [AuthService] IP归属地更新失败');
        return {
          'success': false,
          'message': data['message'] ?? '更新IP归属地失败',
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
