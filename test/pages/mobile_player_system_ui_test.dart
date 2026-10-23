import 'package:cyrene_music/pages/mobile_player_page.dart';
import 'package:cyrene_music/services/lyric_style_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('system UI changes only when style or orientation requires it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final style = LyricStyleService();
    await style.setStyle(LyricStyle.fluidCloud);
    final modes = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
          modes.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    Future<void> show(Size size) => tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const MobilePlayerPage(),
        ),
      ),
    );

    await show(const Size(400, 800));
    expect(modes, ['SystemUiMode.edgeToEdge']);
    // A dependency change and a lyric preference notification must not repeat
    // a platform request when the required mode is unchanged.
    await show(const Size(410, 800));
    await style.setAlignment(LyricAlignment.top);
    await tester.pump();
    expect(modes, ['SystemUiMode.edgeToEdge']);

    await show(const Size(800, 400));
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    expect(modes.length, 2);
    await style.setStyle(LyricStyle.defaultStyle);
    await tester.pump();
    expect(modes.last, 'SystemUiMode.edgeToEdge');
    expect(modes.length, 3);
    await style.setStyle(LyricStyle.immersive);
    await tester.pump();
    expect(modes.last, 'SystemUiMode.immersiveSticky');
    await show(const Size(400, 800));
    expect(modes.length, 4);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
    await style.setStyle(LyricStyle.fluidCloud);
    await style.setAlignment(LyricAlignment.center);
    expect(tester.takeException(), isNull);
  });
}
