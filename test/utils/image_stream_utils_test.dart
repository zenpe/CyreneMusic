import 'dart:async';
import 'dart:ui' as ui;

import 'package:cyrene_music/services/playback/cover_manager.dart';
import 'package:cyrene_music/utils/image_stream_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class _Stream extends ImageStream {
  ImageStreamListener? listener;
  ImageStreamListener? removedListener;
  ImageInfo? synchronousImage;

  @override
  void addListener(ImageStreamListener listener) {
    this.listener = listener;
    if (synchronousImage case final info?) listener.onImage(info, true);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    removedListener = listener;
    this.listener = null;
  }
}

class _Completer extends ImageStreamCompleter {
  void emit(ImageInfo info) => setImage(info);
}

class _Provider extends ImageProvider<_Provider> {
  final ImageStream stream;
  _Provider(this.stream);

  @override
  ImageStream createStream(ImageConfiguration configuration) => stream;

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Provider key,
    ImageErrorListener handleError,
  ) {}

  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ImageInfo image() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final picture = recorder.endRecording();
    final result = ImageInfo(image: picture.toImageSync(2, 2));
    picture.dispose();
    return result;
  }

  test(
    'synchronous cache hit transfers ownership and removes listener',
    () async {
      final info = image();
      final stream = _Stream()..synchronousImage = info;
      final result = await loadFirstImage(
        _Provider(stream),
        timeout: const Duration(seconds: 1),
      );
      expect(result, same(info));
      expect(stream.listener, isNull);
      expect(info.image.debugDisposed, false);
      result.dispose();
      expect(info.image.debugDisposed, true);
    },
  );

  test(
    'releasing the delivered frame preserves a shared cached image',
    () async {
      final cached = image();
      final completer = _Completer();
      final keepAlive = completer.keepAlive();
      completer.emit(cached);
      final stream = ImageStream()..setCompleter(completer);
      final result = await loadFirstImage(
        _Provider(stream),
        timeout: const Duration(seconds: 1),
      );
      result.dispose();
      expect(result.image.debugDisposed, true);
      expect(cached.image.debugDisposed, false);
      keepAlive.dispose();
      expect(cached.image.debugDisposed, true);
    },
  );

  test(
    'duplicate frames are released without disposing the first frame',
    () async {
      final stream = _Stream();
      final pending = loadFirstImage(
        _Provider(stream),
        timeout: const Duration(seconds: 1),
      );
      final first = image();
      final duplicate = image();
      stream.listener!.onImage(first, false);
      stream.listener!.onImage(duplicate, false);
      final result = await pending;
      expect(duplicate.image.debugDisposed, true);
      expect(first.image.debugDisposed, false);
      expect(stream.listener, isNull);
      result.dispose();
    },
  );

  test('timeout removes listener and releases a late callback frame', () async {
    final stream = _Stream();
    await expectLater(
      loadFirstImage(
        _Provider(stream),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(stream.listener, isNull);
    final lateFrame = image();
    stream.removedListener!.onImage(lateFrame, false);
    stream.removedListener!.onError!(
      StateError('late error'),
      StackTrace.current,
    );
    expect(lateFrame.image.debugDisposed, true);
  });

  test(
    'load failure removes listener and preserves the original error',
    () async {
      final stream = _Stream();
      final pending = loadFirstImage(
        _Provider(stream),
        timeout: const Duration(seconds: 1),
      );
      final error = StateError('load failed');
      final check = expectLater(pending, throwsA(same(error)));
      stream.listener!.onError!(error, StackTrace.current);
      await check;
      expect(stream.listener, isNull);
    },
  );

  test('disposed cover manager ignores pending and new updates', () async {
    final manager = CoverManager();
    var notifications = 0;
    manager.addListener(() => notifications++);
    final pending = manager.updateCover('missing-cover-lifecycle-test.png');
    final pendingColor = manager.extractThemeColor(
      'missing-color-lifecycle-test.png',
    );
    manager.dispose();
    await Future.wait([pending, pendingColor]);
    manager.setCover(MemoryImage(Uint8List(0)));
    manager.setCoverImmediate(MemoryImage(Uint8List(0)));
    manager.resetThemeColor();
    await manager.updateCover('https://example.invalid/cover.png');
    await manager.extractThemeColor('https://example.invalid/cover.png');
    await manager.precacheThemeColor('https://example.invalid/cover.png');
    expect(manager.currentCover, isNull);
    expect(notifications, 0);
  });
}
