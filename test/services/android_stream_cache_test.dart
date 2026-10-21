import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cyrene_music/services/android_stream_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidStreamCache.channel, (call) async {
          calls.add(call);
          if (call.method == 'streamCache.stats') {
            return {'totalFiles': 2, 'totalSize': 2048, 'qq': 1, 'netease': 1};
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidStreamCache.channel, null);
  });
  test(
    'fragment stats remain independent of complete audio file metadata',
    () async {
      final stats = await AndroidStreamCache.stats();
      expect(stats['totalFiles'], 2);
      expect(stats['totalSize'], 2048);
      expect(stats.containsKey('filePath'), isFalse);
    },
  );
  test(
    'complete lookup passes identity and only accepts a committed native record',
    () async {
      expect(
        await AndroidStreamCache.lookup({'source': 'qq', 'songId': 'one'}),
        isNull,
      );
      expect(calls.single.method, 'streamCache.lookup');
      expect(calls.single.arguments, {
        'identity': {'source': 'qq', 'songId': 'one'},
      });
    },
  );
  test(
    'per-track deletion passes optional quality without broadening scope',
    () async {
      await AndroidStreamCache.delete('qq', 'same-id', '128k');
      expect(calls.single.method, 'streamCache.delete');
      expect(calls.single.arguments, {
        'source': 'qq',
        'songId': 'same-id',
        'quality': '128k',
      });
    },
  );
  test(
    'native maintenance errors propagate instead of reporting success',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidStreamCache.channel, (_) async {
            throw PlatformException(code: 'stream_cache');
          });
      await expectLater(
        AndroidStreamCache.clear(),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
