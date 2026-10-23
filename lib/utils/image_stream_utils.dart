import 'dart:async';

import 'package:flutter/painting.dart';

/// Loads one frame. The caller owns the returned ImageInfo and must dispose it.
Future<ImageInfo> loadFirstImage(
  ImageProvider provider, {
  required Duration timeout,
}) async {
  final stream = provider.resolve(const ImageConfiguration());
  final completer = Completer<ImageInfo>();
  var accepting = true;
  var delivered = false;
  ImageInfo? received;
  final listener = ImageStreamListener(
    (info, _) {
      if (!accepting || completer.isCompleted) {
        info.dispose();
        return;
      }
      received = info;
      completer.complete(info);
    },
    onError: (Object error, StackTrace? stack) {
      if (accepting && !completer.isCompleted) {
        completer.completeError(error, stack);
      }
    },
  );
  try {
    stream.addListener(listener);
    final info = await completer.future.timeout(timeout);
    delivered = true;
    return info;
  } finally {
    accepting = false;
    stream.removeListener(listener);
    if (!delivered) received?.dispose();
  }
}
