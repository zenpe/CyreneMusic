import 'dart:async';

import 'package:cyrene_music/services/api/api_result.dart';
import 'package:cyrene_music/services/lx_source_catalog_service.dart';
import 'package:cyrene_music/models/lx_source_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

ApiResult<dynamic> _list(List<dynamic> sources) =>
    ApiResult(statusCode: 200, data: {'status': 200, 'sources': sources});

Map<String, String> _source(String id) => {
  'path': '$id.js',
  'name': id.split('/').last,
  'directory': id.contains('/') ? id.substring(0, id.lastIndexOf('/')) : '',
};

void main() {
  test(
    'failure and malformed data preserve last successful list; genuine empty list clears it',
    () async {
      var response = _list([_source('a')]);
      final service = LxSourceCatalogService.withDependencies(
        fetch: (_) async => response,
        baseUrl: () => 'https://api.example',
      );
      await service.refresh();
      response = ApiResult(
        statusCode: 503,
        data: {'message': 'R2 unavailable'},
      );
      await expectLater(service.refresh(), throwsException);
      expect(service.candidates.single.path, 'a.js');
      response = _list([
        {'id': 'bad'},
      ]);
      await expectLater(service.refresh(), throwsFormatException);
      expect(service.candidates.single.path, 'a.js');
      response = _list([]);
      await service.refresh();
      expect(service.candidates, isEmpty);
    },
  );

  test('duplicate entries never replace the successful list', () async {
    var response = _list([_source('a')]);
    final service = LxSourceCatalogService.withDependencies(
      fetch: (_) async => response,
      baseUrl: () => 'https://api.example',
    );
    await service.refresh();
    response = _list([_source('b'), _source('b')]);
    await expectLater(service.refresh(), throwsFormatException);
    expect(service.candidates.single.path, 'a.js');
  });

  test(
    'a late response from the previous backend cannot replace the current backend list',
    () async {
      var baseUrl = 'https://old.example';
      final oldResponse = Completer<ApiResult<dynamic>>();
      final service = LxSourceCatalogService.withDependencies(
        baseUrl: () => baseUrl,
        fetch: (base) => base == 'https://old.example'
            ? oldResponse.future
            : Future.value(_list([_source('new')])),
      );
      final oldRequest = service.refresh();
      baseUrl = 'https://new.example';
      expect(service.candidates, isEmpty);
      await service.refresh();
      oldResponse.complete(_list([_source('old')]));
      await oldRequest;
      expect(service.candidates.single.path, 'new.js');
    },
  );

  test(
    'nested directory filters include descendants but not prefix siblings',
    () {
      final sources = [
        'root',
        '公益/HYW',
        '公益/网易/备用/HYW',
        '公益2/HYW',
      ].map((path) => LxSourceCandidate.fromJson(_source(path))).toList();
      expect(LxSourceCandidate.directories(sources), [
        '公益',
        '公益/网易',
        '公益/网易/备用',
        '公益2',
      ]);
      expect(
        sources.where((s) => s.matches(selectedDirectory: '公益')),
        hasLength(2),
      );
      expect(
        sources.where((s) => s.matches(selectedDirectory: '')),
        hasLength(1),
      );
      expect(
        sources.where(
          (s) => s.matches(query: ' hYw ', selectedDirectory: '公益/网易'),
        ),
        hasLength(1),
      );
      expect(sources.where((s) => s.matches(query: '备用')), hasLength(1));
      expect(sources.map((s) => s.path).toSet(), hasLength(4));
    },
  );

  test('unsafe paths and inconsistent directory metadata are rejected', () {
    for (final path in ['../a', '/a', 'a//b', 'a/./b', r'a\b', 'C:/a']) {
      expect(
        () => LxSourceCandidate.fromJson(_source(path)),
        throwsFormatException,
      );
    }
    expect(
      () =>
          LxSourceCandidate.fromJson({..._source('a/b'), 'directory': 'other'}),
      throwsFormatException,
    );
  });
}
