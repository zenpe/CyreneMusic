import 'dart:async';

import 'package:cyrene_music/services/api/api_result.dart';
import 'package:cyrene_music/services/lx_source_catalog_service.dart';
import 'package:flutter_test/flutter_test.dart';

ApiResult<dynamic> _list(List<dynamic> sources) =>
    ApiResult(statusCode: 200, data: {'status': 200, 'sources': sources});

Map<String, String> _source(String id) => {
  'id': '$id.js',
  'name': id,
  'url': 'https://api.example/lx/scripts/$id.js',
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
      expect(service.candidates.single.id, 'a.js');
      response = _list([
        {'id': 'bad'},
      ]);
      await expectLater(service.refresh(), throwsFormatException);
      expect(service.candidates.single.id, 'a.js');
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
    expect(service.candidates.single.id, 'a.js');
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
      expect(service.candidates.single.id, 'new.js');
    },
  );
}
