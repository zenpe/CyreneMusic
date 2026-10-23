import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'persistent_storage_service.dart';

class RememberedLoginCredentials {
  final String? account;
  final String? password;

  const RememberedLoginCredentials({
    this.account,
    this.password,
  });

  bool get hasCredentials =>
      (account != null && account!.isNotEmpty) ||
      (password != null && password!.isNotEmpty);
}

class AuthCredentialsService extends ChangeNotifier {
  static final AuthCredentialsService _instance =
      AuthCredentialsService._internal();
  factory AuthCredentialsService() => _instance;
  AuthCredentialsService._internal();

  static const String _rememberLoginEnabledKey = 'remember_login_enabled';
  static const String _rememberedLoginAccountKey = 'remembered_login_account';
  static const String _rememberedLoginPasswordKey = 'remembered_login_password';

  final FlutterSecureStorage _secureStorage = _createSecureStorage();

  bool get isRememberLoginEnabled {
    return PersistentStorageService().getBool(_rememberLoginEnabledKey) ?? true;
  }

  Future<void> setRememberLoginEnabled(bool enabled) async {
    await PersistentStorageService().setBool(_rememberLoginEnabledKey, enabled);
    if (!enabled) {
      await clearCredentials();
    }
    notifyListeners();
  }

  Future<RememberedLoginCredentials> loadCredentials() async {
    if (!isRememberLoginEnabled) {
      return const RememberedLoginCredentials();
    }

    final account =
        PersistentStorageService().getString(_rememberedLoginAccountKey);
    String? password;

    try {
      password = await _secureStorage.read(key: _rememberedLoginPasswordKey);
    } catch (_) {
      password = null;
    }

    return RememberedLoginCredentials(
      account: account,
      password: password,
    );
  }

  Future<void> saveCredentials({
    required String account,
    required String password,
  }) async {
    if (!isRememberLoginEnabled) return;

    final trimmedAccount = account.trim();
    if (trimmedAccount.isNotEmpty) {
      await PersistentStorageService().setString(
        _rememberedLoginAccountKey,
        trimmedAccount,
      );
    } else {
      await PersistentStorageService().remove(_rememberedLoginAccountKey);
    }

    try {
      if (password.isNotEmpty) {
        await _secureStorage.write(
          key: _rememberedLoginPasswordKey,
          value: password,
        );
      } else {
        await _secureStorage.delete(key: _rememberedLoginPasswordKey);
      }
    } catch (_) {}

    notifyListeners();
  }

  Future<void> clearCredentials() async {
    await PersistentStorageService().remove(_rememberedLoginAccountKey);
    try {
      await _secureStorage.delete(key: _rememberedLoginPasswordKey);
    } catch (_) {}
    notifyListeners();
  }

  static FlutterSecureStorage _createSecureStorage() {
    if (kIsWeb) {
      return const FlutterSecureStorage(
        webOptions: WebOptions(
          dbName: 'CyreneMusic',
          publicKey: 'CyreneMusic',
        ),
      );
    }

    if (Platform.isAndroid) {
      return const FlutterSecureStorage(
        aOptions: AndroidOptions(
        ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
    }

    if (Platform.isLinux) {
      return const FlutterSecureStorage(
        lOptions: LinuxOptions(),
      );
    }

    return const FlutterSecureStorage(
      webOptions: WebOptions(
        dbName: 'CyreneMusic',
        publicKey: 'CyreneMusic',
      ),
    );
  }
}
