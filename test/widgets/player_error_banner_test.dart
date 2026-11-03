import 'package:cyrene_music/widgets/player_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'failure is inline with details and no duplicate recovery controls',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlayerErrorBanner(message: '暂时无法播放', details: '获取播放链接超时'),
          ),
        ),
      );
      expect(find.text('暂时无法播放'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.byTooltip('获取播放链接超时'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlayerErrorBanner(message: null)),
        ),
      );
      expect(find.text('暂时无法播放'), findsNothing);
    },
  );
}
