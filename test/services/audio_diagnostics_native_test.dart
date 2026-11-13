import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/services/developer_mode_service.dart';
import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:cyrene_music/services/resolution_request.dart';
import 'package:cyrene_music/services/structured_log_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = Platform.environment['CYRENE_LX_NATIVE_TEST'] == '1';

  test(
    'worker business errors reach panel with transaction and original cause',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      SharedPreferences.setMockInitialValues({'developer_mode': true});
      final developer = DeveloperModeService();
      await developer.initialize();
      addTearDown(developer.disableDeveloperMode);
      StructuredLogService.sink = (_) {};
      addTearDown(() => StructuredLogService.sink = null);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final stopped = request.uri.path == '/stopped';
        final auth = request.uri.path == '/auth';
        if (auth) request.response.statusCode = 403;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            auth
                ? {'code': 403, 'msg': '触发人机验证'}
                : stopped
                ? {'code': 'APP_UPGRADE_REQUIRED', 'message': '当前版本已停止服务，请升级'}
                : {
                    'code': 2,
                    'msg': 'Object trans failure: 140017. token=private',
                  },
          ),
        );
        await request.response.close();
      });
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      await runtime.loadScript('''
/*! @name 诊断测试音源 */
lx.on(lx.EVENT_NAMES.request, async ({info}) => {
  await lx.request('http://127.0.0.1:${server.port}/' + info.musicInfo.songmid, {});
  throw new Error('get music url failed');
});
lx.send(lx.EVENT_NAMES.inited, {sources:{tx:{qualitys:['128k']}}});
''');
      for (final id in ['v7', 'stopped', 'auth']) {
        developer.clearLogs();
        final owner = ResolutionRequest.inContext(
          purpose: 'playback',
          transaction: 42,
          action: () => ResolutionRequest(track: 'qq_$id'),
        );
        final url = await owner.run(
          () => runtime.getMusicUrl(source: 'tx', songId: id, quality: '128k'),
        );
        expect(url, isNull);
        expect(runtime.lastFailure?.message, contains('get music url failed'));
        final logs = developer.logs.join('\n');
        expect(logs, contains('tx=42 request=${owner.id}'));
        expect(logs, contains('track=qq_$id'));
        expect(logs, contains(id == 'auth' ? 'HTTP=403' : 'HTTP=200'));
        expect(logs, contains('音源=诊断测试音源'));
        expect(
          logs,
          contains(
            id == 'auth'
                ? '业务码=403'
                : id == 'v7'
                ? '业务码=2'
                : 'APP_UPGRADE_REQUIRED',
          ),
        );
        expect(
          logs,
          contains(
            id == 'auth'
                ? '触发人机验证'
                : id == 'v7'
                ? '140017'
                : '当前版本已停止服务',
          ),
        );
        expect(logs, isNot(contains('private')));
        expect(logs, isNot(contains('at <eval>')));
      }
    },
    skip: !native,
  );
}
