import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/playlist_service.dart';
import 'package:cyrene_music/services/url_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ignores playlist responses from a previous account session', () async {
    SharedPreferences.setMockInitialValues({});
    final requestReceived = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.uri.path == '/playlists') {
        requestReceived.complete();
        await releaseResponse.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 200,
            'playlists': [
              {
                'id': 10,
                'name': 'account-a-playlist',
                'type': 'local',
                'isDefault': false,
                'trackCount': 0,
                'createdAt': '2026-10-09 00:00:00',
                'updatedAt': '2026-10-09 00:00:00',
              },
            ],
          }),
        );
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final realHttp = _RealHttpOverrides();
    await HttpOverrides.runZoned(() async {
      try {
        final auth = AuthService();
        await auth.ensureInitialized();
        await UrlService().initialize();
        UrlService().setCustomBaseUrl(
          'http://${server.address.address}:${server.port}',
        );
        UrlService().setSourceType(BackendSourceType.custom);

        await auth.loginWithToken(token: 'token-a', userJson: _user(1, 'a'));
        final service = PlaylistService();
        final load = service.loadPlaylists();
        await requestReceived.future.timeout(const Duration(seconds: 5));

        await auth.loginWithToken(token: 'token-b', userJson: _user(2, 'b'));
        releaseResponse.complete();
        await load;

        expect(service.playlists, isEmpty);
        expect(service.isLoading, isFalse);
      } finally {
        if (!releaseResponse.isCompleted) releaseResponse.complete();
        await subscription.cancel();
        await server.close(force: true);
        await AuthService().logout();
      }
    }, createHttpClient: realHttp.createHttpClient);
  });
}

class _RealHttpOverrides extends HttpOverrides {}

Map<String, dynamic> _user(int id, String name) => {
  'id': id,
  'email': '$name@example.com',
  'username': name,
  'isVerified': true,
};
