import 'package:cyrene_music/features/audio_source/audio_source_feature.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/navidrome_session_service.dart';
import 'package:cyrene_music/services/persistent_storage_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends ChangeNotifier implements AuthService {
  @override
  bool isLoggedIn = false;
  @override
  Future<void> ensureInitialized() async {}
  void change(bool value) {
    isLoggedIn = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Read extends ChangeNotifier implements AudioSourceReadController {
  @override
  bool isConfigured = true;
  @override
  bool isNavidromeActive = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Write implements AudioSourceController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Storage extends ChangeNotifier implements PersistentStorageService {
  @override
  bool termsAccepted = true;
  @override
  bool enableLocalMode = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Navidrome extends ChangeNotifier implements NavidromeSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'entry listener follows login and logout without clearing the source',
    () {
      final auth = _Auth();
      final read = _Read();
      final storage = _Storage();
      final navidrome = _Navidrome();
      final facade = AudioSourceFacade.withDependencies(
        readController: read,
        writeController: _Write(),
        storageService: storage,
        authService: auth,
        navidromeSessionService: navidrome,
      );
      var notifications = 0;
      void listener() => notifications++;
      facade.addEntryStateListener(listener);
      expect(facade.resolveEntryRoute(), AppGateRoute.regularSetup);
      auth.change(true);
      expect(notifications, 1);
      expect(facade.resolveEntryRoute(), AppGateRoute.regularMain);
      auth.change(false);
      expect(notifications, 2);
      expect(facade.resolveEntryRoute(), AppGateRoute.regularSetup);
      expect(read.isConfigured, true);
      read.isNavidromeActive = true;
      auth.change(true);
      expect(facade.resolveEntryRoute(), AppGateRoute.navidromeMain);
      facade.removeEntryStateListener(listener);
      final beforeRemoval = notifications;
      auth.change(false);
      read.notifyListeners();
      storage.notifyListeners();
      navidrome.notifyListeners();
      expect(notifications, beforeRemoval);
      auth.dispose();
      read.dispose();
      storage.dispose();
      navidrome.dispose();
    },
  );
}
