import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';

/// 用户数据模型（管理员视图）
class AdminUserData {
  final int id;
  final String email;
  final String username;
  final String? avatarUrl;
  final String createdAt;
  final String updatedAt;
  final bool isVerified;
  final String? verifiedAt;
  final String? lastLogin;
  final String? lastIp;
  final String? lastIpLocation;
  final String? lastIpUpdatedAt;

  AdminUserData({
    required this.id,
    required this.email,
    required this.username,
    this.avatarUrl,
    required this.createdAt,
    required this.updatedAt,
    required this.isVerified,
    this.verifiedAt,
    this.lastLogin,
    this.lastIp,
    this.lastIpLocation,
    this.lastIpUpdatedAt,
  });

  factory AdminUserData.fromJson(Map<String, dynamic> json) {
    return AdminUserData(
      id: json['id'],
      email: json['email'],
      username: json['username'],
      avatarUrl: json['avatar_url'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      isVerified: json['is_verified'] == 1,
      verifiedAt: json['verified_at'],
      lastLogin: json['last_login'],
      lastIp: json['last_ip'],
      lastIpLocation: json['last_ip_location'],
      lastIpUpdatedAt: json['last_ip_updated_at'],
    );
  }
}

/// 统计数据模型
class UserStats {
  final int totalUsers;
  final int verifiedUsers;
  final int unverifiedUsers;
  final int todayUsers;
  final int todayActiveUsers;
  final int last7DaysUsers;
  final int last30DaysUsers;
  final List<LocationStat> topLocations;
  final List<TrendData> registrationTrend;
  final List<TrendData> activeTrend;

  UserStats({
    required this.totalUsers,
    required this.verifiedUsers,
    required this.unverifiedUsers,
    required this.todayUsers,
    required this.todayActiveUsers,
    required this.last7DaysUsers,
    required this.last30DaysUsers,
    required this.topLocations,
    required this.registrationTrend,
    required this.activeTrend,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    final overview = json['overview'] as Map<String, dynamic>;
    return UserStats(
      totalUsers: overview['totalUsers'],
      verifiedUsers: overview['verifiedUsers'],
      unverifiedUsers: overview['unverifiedUsers'],
      todayUsers: overview['todayUsers'],
      todayActiveUsers: overview['todayActiveUsers'],
      last7DaysUsers: overview['last7DaysUsers'],
      last30DaysUsers: overview['last30DaysUsers'],
      topLocations: (json['topLocations'] as List)
          .map((item) => LocationStat.fromJson(item))
          .toList(),
      registrationTrend: (json['registrationTrend'] as List)
          .map((item) => TrendData.fromJson(item))
          .toList(),
      activeTrend: (json['activeTrend'] as List)
          .map((item) => TrendData.fromJson(item))
          .toList(),
    );
  }
}

/// 地区统计
class LocationStat {
  final String location;
  final int count;

  LocationStat({required this.location, required this.count});

  factory LocationStat.fromJson(Map<String, dynamic> json) {
    return LocationStat(
      location: json['location'],
      count: json['count'],
    );
  }
}

/// 趋势数据
class TrendData {
  final String date;
  final int count;

  TrendData({required this.date, required this.count});

  factory TrendData.fromJson(Map<String, dynamic> json) {
    return TrendData(
      date: json['date'],
      count: json['count'],
    );
  }
}

/// 管理员服务
class AdminService extends ChangeNotifier {
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;
  AdminService._internal() {
    _loadToken();
  }

  String? _adminToken;
  bool _isAuthenticated = false;
  List<AdminUserData> _users = [];
  UserStats? _stats;
  bool _isLoading = false;
  String? _errorMessage;

  String? get adminToken => _adminToken;
  bool get isAuthenticated => _isAuthenticated;
  List<AdminUserData> get users => _users;
  UserStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Admin auth headers (used for authenticated admin calls)
  Map<String, String> get _authHeaders =>
      {'Authorization': 'Bearer $_adminToken'};

  /// 从本地存储加载令牌
  Future<void> _loadToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _adminToken = prefs.getString('admin_token');
      if (_adminToken != null && _adminToken!.isNotEmpty) {
        _isAuthenticated = true;
        print('👑 [AdminService] 从本地加载管理员令牌');
        notifyListeners();
      }
    } catch (e) {
      print('❌ [AdminService] 加载令牌失败: $e');
    }
  }

  /// 保存令牌到本地
  Future<void> _saveToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('admin_token', token);
      print('💾 [AdminService] 管理员令牌已保存');
    } catch (e) {
      print('❌ [AdminService] 保存令牌失败: $e');
    }
  }

  /// 清除令牌
  Future<void> _clearToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('admin_token');
      print('🗑️ [AdminService] 管理员令牌已清除');
    } catch (e) {
      print('❌ [AdminService] 清除令牌失败: $e');
    }
  }

  /// 管理员登录
  Future<Map<String, dynamic>> login(String password) async {
    print('👑 [AdminService] 开始管理员登录...');
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await ApiClient().postJson(
        '/admin/login',
        data: {'password': password},
        auth: false,
      );

      print('📥 [AdminService] 状态码: ${result.statusCode}');

      final data = result.data as Map<String, dynamic>?;

      if (result.ok) {
        _adminToken = data?['data']?['token'];
        _isAuthenticated = true;
        await _saveToken(_adminToken!);

        print('✅ [AdminService] 管理员登录成功');

        _isLoading = false;
        notifyListeners();

        return {'success': true, 'message': data?['message']};
      } else {
        _errorMessage = data?['message'];
        _isLoading = false;
        notifyListeners();

        return {'success': false, 'message': data?['message']};
      }
    } catch (e) {
      print('❌ [AdminService] 登录异常: $e');
      _errorMessage = '网络错误: ${e.toString()}';
      _isLoading = false;
      notifyListeners();

      return {'success': false, 'message': _errorMessage};
    }
  }

  /// 管理员登出
  Future<void> logout() async {
    print('👑 [AdminService] 管理员登出...');

    if (_adminToken != null) {
      try {
        await ApiClient().postJson(
          '/admin/logout',
          auth: false,
          headers: _authHeaders,
        );
      } catch (e) {
        print('⚠️ [AdminService] 登出请求失败: $e');
      }
    }

    _adminToken = null;
    _isAuthenticated = false;
    _users = [];
    _stats = null;
    await _clearToken();

    print('✅ [AdminService] 管理员已登出');
    notifyListeners();
  }

  /// 获取所有用户列表
  Future<bool> fetchUsers() async {
    if (!_isAuthenticated || _adminToken == null) {
      print('⚠️ [AdminService] 未登录，无法获取用户列表');
      return false;
    }

    print('👑 [AdminService] 获取用户列表...');
    _isLoading = true;
    _errorMessage = null; // 清除之前的错误信息
    notifyListeners();

    try {
      final result = await ApiClient().getJson(
        '/admin/users',
        auth: false,
        headers: _authHeaders,
      );

      print('📥 [AdminService] 状态码: ${result.statusCode}');

      if (result.statusCode == 401) {
        // 令牌无效，但不立即登出，给用户一个重试机会
        _errorMessage = '令牌验证失败，请重新登录或重试';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final data = result.data as Map<String, dynamic>?;

      if (result.ok) {
        final usersList = data?['data']?['users'] as List;
        _users = usersList.map((json) => AdminUserData.fromJson(json)).toList();

        print('✅ [AdminService] 获取用户列表成功: ${_users.length} 个用户');

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data?['message'];
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('❌ [AdminService] 获取用户列表异常: $e');
      _errorMessage = '网络错误: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 获取统计数据
  Future<bool> fetchStats() async {
    if (!_isAuthenticated || _adminToken == null) {
      print('⚠️ [AdminService] 未登录，无法获取统计数据');
      return false;
    }

    print('👑 [AdminService] 获取统计数据...');
    _isLoading = true;
    _errorMessage = null; // 清除之前的错误信息
    notifyListeners();

    try {
      final result = await ApiClient().getJson(
        '/admin/stats',
        auth: false,
        headers: _authHeaders,
      );

      print('📥 [AdminService] 状态码: ${result.statusCode}');

      if (result.statusCode == 401) {
        // 令牌无效，但不立即登出，给用户一个重试机会
        _errorMessage = '令牌验证失败，请重新登录或重试';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final data = result.data as Map<String, dynamic>?;

      if (result.ok) {
        _stats = UserStats.fromJson(data!['data']);

        print('✅ [AdminService] 获取统计数据成功');

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = data?['message'];
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('❌ [AdminService] 获取统计数据异常: $e');
      _errorMessage = '网络错误: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// 删除用户
  Future<bool> deleteUser(int userId) async {
    if (!_isAuthenticated || _adminToken == null) {
      print('⚠️ [AdminService] 未登录，无法删除用户');
      return false;
    }

    print('👑 [AdminService] 删除用户 ID: $userId');

    try {
      final result = await ApiClient().deleteJson(
        '/admin/users',
        data: {'userId': userId},
        auth: false,
        headers: _authHeaders,
      );

      print('📥 [AdminService] 状态码: ${result.statusCode}');

      if (result.statusCode == 401) {
        await logout();
        return false;
      }

      final data = result.data as Map<String, dynamic>?;

      if (result.ok) {
        print('✅ [AdminService] 用户已删除');

        // 从本地列表中移除
        _users.removeWhere((user) => user.id == userId);
        notifyListeners();

        return true;
      } else {
        print('❌ [AdminService] 删除失败: ${data?['message']}');
        return false;
      }
    } catch (e) {
      print('❌ [AdminService] 删除用户异常: $e');
      return false;
    }
  }

}
