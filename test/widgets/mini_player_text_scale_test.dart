import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:cyrene_music/services/playback_mode_service.dart';
import 'package:cyrene_music/utils/theme_manager.dart';
import 'package:cyrene_music/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mini player grows with text and survives orientation changes', (
    tester,
  ) async {
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('cyrene-mini-layout-'),
    );
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => temp!.path,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        null,
      );
      await temp!.delete(recursive: true);
    });
    final track = Track(
      id: 'qa',
      name: '很长的歌曲名称用于验证切屏与大字体布局',
      artists: '很长的歌手名称',
      album: '',
      picUrl: '',
      source: MusicSource.netease,
    );
    SharedPreferences.setMockInitialValues({
      'playback_session_snapshot_v1': jsonEncode({
        'version': 1,
        'queue': [track.toJson()],
        'currentIndex': 0,
        'source': QueueSource.none.name,
        'positionMs': 0,
        'state': 'idle',
        'playbackMode': 'loopAll',
      }),
    });
    await tester.runAsync(() => ThemeManager().ensureSettingsLoaded());
    ThemeManager().setThemeFramework(ThemeFramework.material);
    final playback = PlaybackService();
    expect(
      await tester.runAsync(
        () => playback.restoreSessionOnStartup(autoPlay: false),
      ),
      isTrue,
    );
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      playback.dispose();
    });

    final heights = <double>[];
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      for (final size in [
        const Size(360, 800),
        const Size(800, 360),
        const Size(320, 640),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(
                body: SizedBox.expand(),
                bottomNavigationBar: MiniPlayer(transparent: true),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(MiniPlayer), findsOneWidget);
        expect(find.textContaining('很长的歌曲名称'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: '$size scale $scale');
        if (size.width == 360) {
          heights.add(tester.getSize(find.byType(MiniPlayer)).height);
        }
      }
    }
    expect(heights.first, greaterThanOrEqualTo(66));
    expect(find.text('SQ'), findsNothing);
    expect(heights.last, greaterThan(heights.first));

    // Repeated mode clicks should update the button immediately without a
    // feedback overlay covering the controls between clicks.
    await tester.binding.setSurfaceSize(const Size(800, 360));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(),
          bottomNavigationBar: MiniPlayer(transparent: true),
        ),
      ),
    );
    final modes = PlaybackModeService();
    await modes.setMode(PlaybackMode.loopAll);
    await tester.pump();
    const cycle = [
      PlaybackMode.shuffle,
      PlaybackMode.repeatOne,
      PlaybackMode.sequential,
      PlaybackMode.loopAll,
    ];
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byTooltip(modes.getModeName()));
      await tester.pump(const Duration(milliseconds: 16));
      expect(modes.currentMode, cycle[i % cycle.length]);
      expect(find.byTooltip(modes.getModeName()), findsOneWidget);
      expect(find.byIcon(modes.getModeIcon()), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const ValueKey('app-feedback-surface')), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    // Let the session's asynchronous backup write finish before removing its
    // isolated directory during teardown.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });
}
