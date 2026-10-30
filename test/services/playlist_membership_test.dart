import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/auth_service.dart';
import 'package:cyrene_music/services/playlist_service.dart';
import 'package:cyrene_music/services/url_service.dart';
import 'package:cyrene_music/widgets/playlist_membership_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _track = Track(
  id: 'song',
  name: 'Song',
  artists: 'Artist',
  album: 'Album',
  picUrl: '',
  source: MusicSource.qq,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unknown reads coalesce; complete positive and negative results are cached',
    () async {
      await _withServer((f) async {
        f.matches = [_match(10), _match(20)];
        f.gate = Completer<void>();
        final first = f.service.isTrackInAnyPlaylist(_track);
        final second = f.service.isTrackInAnyPlaylist(_track);
        await f.arrived.future;
        expect(f.reads, 1);
        f.gate!.complete();
        expect((await first).matches, hasLength(2));
        expect((await second).matches, hasLength(2));
        await f.service.isTrackInAnyPlaylist(_track);
        expect(f.reads, 1);
        final other = Track(
          id: 'other',
          name: 'Other',
          artists: 'Artist',
          album: 'Album',
          picUrl: '',
          source: MusicSource.qq,
        );
        f.matches = [];
        expect(
          (await f.service.isTrackInAnyPlaylist(other)).inPlaylist,
          isFalse,
        );
        expect((await f.service.isTrackInAnyPlaylist(other)).known, isTrue);
        expect(f.reads, 2);
      });
    },
  );

  test(
    'successful add patches a late read without losing other playlist matches',
    () async {
      await _withServer((f) async {
        f.matches = [_match(20)];
        f.gate = Completer<void>();
        final read = f.service.isTrackInAnyPlaylist(_track);
        await f.arrived.future;
        expect(await f.service.addTrackToPlaylist(10, _track), isTrue);
        expect(f.service.cachedTrackMembership(_track).inPlaylist, isTrue);
        f.gate!.complete();
        expect((await read).playlistIds, unorderedEquals([10, 20]));
        expect(f.reads, 1);
      });
    },
  );

  test(
    'remove retains heart for another playlist and late read cannot resurrect it',
    () async {
      await _withServer((f) async {
        f.matches = [_match(10), _match(20)];
        final initial = await f.service.isTrackInAnyPlaylist(_track);
        expect(
          await f.service.removeTrackMatch(initial.matches.first, _track),
          isTrue,
        );
        expect(f.service.cachedTrackMembership(_track).playlistIds, [20]);
        expect(f.reads, 1);
        expect(
          await f.service.removeTrackMatch(initial.matches.last, _track),
          isTrue,
        );
        expect(f.service.cachedTrackMembership(_track).known, isTrue);
        expect(f.service.cachedTrackMembership(_track).inPlaylist, isFalse);

        f.service.clear();
        await f.service.loadPlaylists();
        f.matches = [_match(10)];
        f.gate = Completer<void>();
        f.arrived = Completer<void>();
        final read = f.service.isTrackInAnyPlaylist(_track);
        await f.arrived.future;
        expect(
          await f.service.removeTrackMatch(
            PlaylistTrackMatch.fromJson(_match(10)),
            _track,
          ),
          isTrue,
        );
        f.gate!.complete();
        expect((await read).inPlaylist, isFalse);
      });
    },
  );

  test(
    'failed mutations preserve cached status and failed reads remain unknown',
    () async {
      await _withServer((f) async {
        f.matches = [];
        await f.service.isTrackInAnyPlaylist(_track);
        f.failMutation = true;
        expect(await f.service.addTrackToPlaylist(10, _track), isFalse);
        expect(f.service.cachedTrackMembership(_track).inPlaylist, isFalse);
        f.service.clear();
        f.failRead = true;
        expect((await f.service.isTrackInAnyPlaylist(_track)).known, isFalse);
        f.failRead = false;
        expect((await f.service.isTrackInAnyPlaylist(_track)).known, isTrue);
        expect(f.reads, 3);
      });
    },
  );

  test(
    'loaded local tracks give immediate positives; subscribed tracks do not',
    () async {
      await _withServer((f) async {
        await f.service.loadPlaylistTracks(10);
        expect(f.service.cachedTrackMembership(_track).inPlaylist, isTrue);
        expect(f.service.cachedTrackMembership(_track).complete, isFalse);
        expect(f.reads, 0);
        f.service.clear();
        f.synced = true;
        await f.service.loadPlaylists();
        await f.service.loadPlaylistTracks(10);
        expect(f.service.cachedTrackMembership(_track).known, isFalse);
      });
    },
  );

  test(
    'rename and playlist deletion update complete membership immediately',
    () async {
      await _withServer((f) async {
        f.matches = [_match(10), _match(20)];
        await f.service.isTrackInAnyPlaylist(_track);
        expect(await f.service.updatePlaylist(10, 'Renamed'), isTrue);
        expect(
          f.service.cachedTrackMembership(_track).playlistNames,
          contains('Renamed'),
        );
        expect(await f.service.deletePlaylist(10), isTrue);
        expect(f.service.cachedTrackMembership(_track).playlistIds, [20]);
        expect(f.reads, 1);
      });
    },
  );

  test(
    'backend ABA and account changes discard cache and late checks',
    () async {
      await _withServer((f) async {
        f.matches = [_match(10)];
        f.gate = Completer<void>();
        final read = f.service.isTrackInAnyPlaylist(_track);
        await f.arrived.future;
        final url = UrlService().baseUrl;
        UrlService().useCustomSource('http://127.0.0.1:1');
        UrlService().useCustomSource(url);
        expect(AuthService().isLoggedIn, false);
        await AuthService().loginWithToken(
          token: 'returned-backend',
          userJson: _user(1),
        );
        f.gate!.complete();
        expect((await read).known, isFalse);
        expect(f.service.cachedTrackMembership(_track).known, isFalse);
        f.gate = null;
        await f.service.isTrackInAnyPlaylist(_track);
        await AuthService().loginWithToken(token: 'second', userJson: _user(2));
        expect(f.service.cachedTrackMembership(_track).known, isFalse);
      });
    },
  );

  test('same song ID on different platforms has separate membership', () async {
    await _withServer((f) async {
      f.matches = [_match(10)];
      await f.service.isTrackInAnyPlaylist(_track);
      f.matches = [];
      final other = Track(
        id: 'song',
        name: 'Song',
        artists: 'Artist',
        album: 'Album',
        picUrl: '',
        source: MusicSource.netease,
      );
      expect((await f.service.isTrackInAnyPlaylist(other)).inPlaylist, isFalse);
      expect(f.service.cachedTrackMembership(_track).inPlaylist, isTrue);
      expect(f.reads, 2);
    });
  });

  test(
    'clear invalidates late checks even without an account change',
    () async {
      await _withServer((f) async {
        f.matches = [_match(10)];
        f.gate = Completer<void>();
        final read = f.service.isTrackInAnyPlaylist(_track);
        await f.arrived.future;
        f.service.clear();
        f.gate!.complete();
        expect((await read).known, isFalse);
        expect(f.service.cachedTrackMembership(_track).known, isFalse);
      });
    },
  );

  testWidgets('switching track and disposing ignore old player checks', (
    tester,
  ) async {
    await tester.runAsync(
      () => _withServer((f) async {
        f.matches = [_match(10)];
        f.gate = Completer<void>();
        final gate = f.gate!;
        await tester.pumpWidget(MaterialApp(home: _Heart(track: _track)));
        await f.arrived.future;
        expect(find.text('loading'), findsOneWidget);
        final firstRead = f.service.isTrackInAnyPlaylist(_track);
        f.gate = null;
        f.matches = [];
        final other = Track(
          id: 'other',
          name: 'Other',
          artists: 'Artist',
          album: 'Album',
          picUrl: '',
          source: MusicSource.qq,
        );
        await tester.pumpWidget(MaterialApp(home: _Heart(track: other)));
        await f.service.isTrackInAnyPlaylist(other);
        await tester.pump();
        expect(find.text('empty'), findsOneWidget);
        gate.complete();
        await firstRead;
        await tester.pump();
        expect(find.text('empty'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        expect(await f.service.addTrackToPlaylist(10, _track), isTrue);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }),
    );
  });

  testWidgets('heart updates before a slow playlist refresh finishes', (
    tester,
  ) async {
    await tester.runAsync(
      () => _withServer((f) async {
        f.tracksPresent = false;
        await f.service.loadPlaylistTracks(10);
        await f.service.isTrackInAnyPlaylist(_track);
        await tester.pumpWidget(MaterialApp(home: _Heart(track: _track)));
        expect(find.text('empty'), findsOneWidget);
        f.tracksPresent = true;
        f.trackGate = Completer<void>();
        final add = f.service.addTrackToPlaylist(10, _track);
        await f.trackArrived.future;
        await tester.pump();
        expect(find.text('heart'), findsOneWidget);
        expect(f.reads, 1);
        f.trackGate!.complete();
        expect(await add, isTrue);
        await tester.pumpWidget(const SizedBox());
      }),
    );
  });

  testWidgets(
    'shared player state updates after add and treats failure as unknown',
    (tester) async {
      await tester.runAsync(
        () => _withServer((f) async {
          f.matches = [];
          await f.service.isTrackInAnyPlaylist(_track);
          await tester.pumpWidget(MaterialApp(home: _Heart(track: _track)));
          expect(find.text('empty'), findsOneWidget);
          expect(await f.service.addTrackToPlaylist(10, _track), isTrue);
          await tester.pump();
          expect(find.text('heart'), findsOneWidget);
          expect(f.reads, 1);
          await tester.pumpWidget(const SizedBox());
          f.service.clear();
          f.failRead = true;
          await tester.pumpWidget(MaterialApp(home: _Heart(track: _track)));
          await f.arrived.future;
          // Joining the same pending check also waits for its state subscription.
          await f.service.isTrackInAnyPlaylist(_track);
          await tester.pump();
          expect(find.text('unknown'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        }),
      );
    },
  );
}

class _Heart extends StatefulWidget {
  final Track track;
  const _Heart({required this.track});
  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with PlaylistMembershipState<_Heart> {
  @override
  Track get membershipTrack => widget.track;
  @override
  Widget build(BuildContext context) => Text(
    membershipLoading
        ? 'loading'
        : !membershipResult.known
        ? 'unknown'
        : membershipResult.inPlaylist
        ? 'heart'
        : 'empty',
  );
}

class _RealHttp extends HttpOverrides {}

Map<String, dynamic> _user(int id) => {
  'id': id,
  'email': '$id@example.com',
  'username': 'user$id',
  'isVerified': true,
};
Map<String, dynamic> _match(int id) => {
  'playlistId': id,
  'playlistName': 'List$id',
  'itemId': id * 10,
};
Map<String, dynamic> _playlist(int id, {String? name, bool synced = false}) => {
  'id': id,
  'name': name ?? 'List$id',
  'type': synced ? 'synced' : 'local',
  'isDefault': id == 10,
  'trackCount': 1,
  'contentRevision': 0,
  'orderRevision': 0,
  'createdAt': '2026-10-16 00:00:00',
  'updatedAt': '2026-10-16 00:00:00',
};

class _Fixture {
  final service = PlaylistService();
  List<Map<String, dynamic>> matches = [];
  Completer<void>? gate;
  Completer<void> arrived = Completer<void>();
  int reads = 0;
  bool failRead = false;
  bool failMutation = false;
  bool synced = false;
  bool tracksPresent = true;
  Completer<void>? trackGate;
  final trackArrived = Completer<void>();

  Future<void> handle(HttpRequest request) async {
    final path = request.uri.path;
    var body = <String, dynamic>{'status': 200};
    if (path == '/playlists/check-track') {
      reads++;
      final snapshot = matches.map(Map<String, dynamic>.from).toList();
      if (!arrived.isCompleted) arrived.complete();
      await gate?.future;
      if (failRead) request.response.statusCode = 503;
      body['matches'] = snapshot;
    } else if (path == '/playlists') {
      body['playlists'] = [_playlist(10, synced: synced), _playlist(20)];
    } else if (request.method == 'GET' && path.endsWith('/tracks')) {
      if (trackGate != null) {
        if (!trackArrived.isCompleted) trackArrived.complete();
        await trackGate!.future;
      }
      body['tracks'] = [
        if (tracksPresent)
          {
            'itemId': 100,
            'trackId': 'song',
            'name': 'Song',
            'artists': 'Artist',
            'album': 'Album',
            'picUrl': '',
            'source': 'qq',
            'addedAt': '2026-10-16 00:00:00',
          },
      ];
    } else {
      final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      if (failMutation) request.response.statusCode = 500;
      body['playlist'] = _playlist(10, name: data['name'] as String?);
      body['itemId'] = 100;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }
}

Future<void> _withServer(Future<void> Function(_Fixture) action) async {
  SharedPreferences.setMockInitialValues({});
  await HttpOverrides.runZoned(() async {
    final auth = AuthService();
    await auth.ensureInitialized();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final f = _Fixture();
    final subscription = server.listen(f.handle);
    try {
      UrlService().useCustomSource('http://127.0.0.1:${server.port}');
      await auth.loginWithToken(token: 'membership', userJson: _user(1));
      f.service.clear();
      await f.service.loadPlaylists();
      await action(f).timeout(const Duration(seconds: 15));
    } finally {
      if (f.gate != null && !f.gate!.isCompleted) f.gate!.complete();
      if (f.trackGate != null && !f.trackGate!.isCompleted) {
        f.trackGate!.complete();
      }
      await auth.logout();
      await subscription.cancel();
      await server.close(force: true);
    }
  }, createHttpClient: _RealHttp().createHttpClient);
}
