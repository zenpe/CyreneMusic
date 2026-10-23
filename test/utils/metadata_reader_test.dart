import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/utils/metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> size32(int value, {bool syncSafe = false}) {
  final bits = syncSafe ? 7 : 8;
  final mask = (1 << bits) - 1;
  return [for (var i = 3; i >= 0; i--) (value >> (i * bits)) & mask];
}

List<int> frame(String id, List<int> content, int version) => [
  ...ascii.encode(id),
  ...size32(content.length, syncSafe: version == 4),
  0,
  0,
  ...content,
];
List<int> mp3(List<int> frames, int version) => [
  ...ascii.encode('ID3'),
  version,
  0,
  0,
  ...size32(frames.length, syncSafe: true),
  ...frames,
];

void main() {
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'cyrene_metadata_test_',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));
  Future<String?> lyrics(String extension, List<int> bytes) async {
    final file = await File(
      '${directory.path}/song.$extension',
    ).writeAsBytes(bytes);
    final result = await MetadataReader.extractLyrics(file.path);
    // Also verifies that all random-access handles are closed on Windows.
    await file.delete();
    return result;
  }

  for (final version in [3, 4]) {
    test(
      'ID3v2.$version skips picture frames and decodes UTF8 lyrics',
      () async {
        const text = '[00:01] 歌词';
        final frames = [
          ...frame('APIC', List<int>.filled(20000, 1), version),
          ...frame('USLT', [
            3,
            ...ascii.encode('eng'),
            0,
            ...utf8.encode(text),
          ], version),
        ];
        expect(await lyrics('mp3', mp3(frames, version)), text);
      },
    );
  }

  for (final littleEndian in [false, true]) {
    test(
      'UTF16 description terminator uses code unit alignment (LE=$littleEndian)',
      () async {
        List<int> encode(String text) => [
          for (final unit in text.codeUnits)
            ...littleEndian ? [unit & 255, unit >> 8] : [unit >> 8, unit & 255],
        ];
        final bom = littleEndian ? [255, 254] : [254, 255];
        final content = [
          1,
          ...ascii.encode('eng'),
          ...bom,
          ...encode('A'),
          0,
          0,
          ...bom,
          ...encode('歌词🎵'),
        ];
        expect(await lyrics('mp3', mp3(frame('USLT', content, 3), 3)), '歌词🎵');
      },
    );
  }

  test('FLAC seeks past image block and reads Vorbis lyrics', () async {
    final comment = utf8.encode('LYRICS=[00:01]歌词');
    final block = [
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      ...size32(comment.length).reversed,
      ...comment,
    ];
    expect(
      await lyrics('flac', [
        ...ascii.encode('fLaC'),
        6,
        0,
        0x10,
        0,
        ...List<int>.filled(4096, 1),
        0x84,
        0,
        0,
        block.length,
        ...block,
      ]),
      '[00:01]歌词',
    );
  });

  test('truncated metadata and oversized frame lengths fail safely', () async {
    expect(await lyrics('mp3', [73, 68, 51]), isNull);
    expect(
      await lyrics(
        'mp3',
        mp3([...ascii.encode('USLT'), ...size32(10000), 0, 0, 1], 3),
      ),
      isNull,
    );
    expect(
      await lyrics('flac', [...ascii.encode('fLaC'), 0x84, 0xff, 0xff, 0xff]),
      isNull,
    );
    expect(
      await lyrics('flac', [...ascii.encode('fLaC'), 0x84, 0, 0, 1, 0]),
      isNull,
    );
  });
}
