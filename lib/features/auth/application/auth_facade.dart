import 'package:flutter/foundation.dart';

import '../../../services/auth_service.dart';

/// 认证门面。
///
/// 为页面层提供统一认证状态读写入口，减少对 AuthService 的散落依赖。
class AuthFacade {
  static final AuthFacade _instance = AuthFacade._internal();

  factory AuthFacade() => _instance;

  AuthFacade.withService(AuthService service) : _authService = service;

  AuthFacade._internal({AuthService? authService})
      : _authService = authService ?? AuthService();

  final AuthService _authService;

  bool get isLoggedIn => _authService.isLoggedIn;

  User? get currentUser => _authService.currentUser;

  String? get token => _authService.token;

  void addAuthStateListener(VoidCallback listener) {
    _authService.addListener(listener);
  }

  void removeAuthStateListener(VoidCallback listener) {
    _authService.removeListener(listener);
  }

  void refresh() => _authService.refresh();

  Future<void> logout() => _authService.logout();

  Future<Map<String, dynamic>> updateUsername(String newUsername) {
    return _authService.updateUsername(newUsername);
  }

  Future<Map<String, dynamic>> login({
    required String account,
    required String password,
  }) {
    return _authService.login(account: account, password: password);
  }

  Future<Map<String, dynamic>> updateLocation() {
    return _authService.updateLocation();
  }

  Future<void> loginWithToken({
    required String token,
    Map<String, dynamic>? userJson,
  }) {
    return _authService.loginWithToken(token: token, userJson: userJson);
  }

  Future<Map<String, dynamic>> checkRegistrationStatus() {
    return _authService.checkRegistrationStatus();
  }

  Future<Map<String, dynamic>> sendRegisterCode({
    required String email,
    required String username,
  }) {
    return _authService.sendRegisterCode(email: email, username: username);
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String username,
    required String password,
    required String code,
  }) {
    return _authService.register(
      email: email,
      username: username,
      password: password,
      code: code,
    );
  }

  Future<Map<String, dynamic>> sendResetCode({
    required String email,
  }) {
    return _authService.sendResetCode(email: email);
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) {
    return _authService.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
  }

  Future<bool> validateToken() {
    return _authService.validateToken();
  }
}
