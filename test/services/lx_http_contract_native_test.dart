import 'dart:convert';
import 'dart:io';

import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/services/lx_music_info.dart';
import 'package:cyrene_music/services/lx_quickjs_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real QuickJS uses LX metadata, Buffer callbacks, gzip and multipart',
    () async {
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final uploads = <List<int>>[];
      server.listen((request) async {
        if (request.uri.path == '/upload') {
          uploads.add(
            await request.fold<List<int>>([], (a, b) => a..addAll(b)),
          );
          expect(request.headers.contentType?.mimeType, 'multipart/form-data');
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"ok":true}');
        } else if (request.uri.path == '/gzip') {
          request.response.headers.set('content-encoding', 'gzip');
          request.response.add(gzip.encode(utf8.encode('{"ok":true}')));
        } else {
          request.response.add([0, 255, 1, 128]);
        }
        await request.response.close();
      });
      final runtime = LxQuickJsRuntime();
      addTearDown(runtime.dispose);
      final base = 'http://127.0.0.1:${server.port}';
      await runtime.loadScript('''
lx.on(lx.EVENT_NAMES.request, async ({info}) => {
 const m=info.musicInfo;
 if(m.songmid!=='MID1'||m.songId!==12345||m.strMediaMid!=='MEDIA1'||m.interval!=='03:32') throw Error('metadata');
 const {resp}=await lx.request('$base/binary', {});
 if(resp.bytes!==4||resp.raw.toString('hex')!=='00ff0180'||resp.raw.readUInt16BE(0)!==255) throw Error('raw bytes');
 if(resp.raw.slice(1,3).toString('hex')!=='ff01') throw Error('buffer slice');
 const zipped=await lx.request('$base/gzip',{});
 if(zipped.body.ok!==true||zipped.resp.raw.readUInt16BE(0)!==0x1f8b||zipped.resp.bytes!==zipped.resp.raw.length) throw Error('gzip');
 const posted=await lx.request('$base/upload',{method:'POST',formData:{name:'中文',file:{buffer:lx.utils.buffer.from('00ff0180','hex'),filename:'sample.bin',content_type:'application/octet-stream'}}});
 if(posted.body.ok!==true) throw Error('multipart');
 return 'https://example.test/ok.mp3';
});
lx.send(lx.EVENT_NAMES.inited,{sources:{tx:{qualitys:['128k']}}});
''');
      final url = await runtime.getMusicUrl(
        source: 'tx',
        songId: 'MID1',
        quality: '128k',
        musicInfo: buildLxMusicInfo(
          source: 'tx',
          songId: 'MID1',
          durationMs: 212000,
          lxMetadata: const LxMusicMetadata(
            songId: '12345',
            strMediaMid: 'MEDIA1',
          ),
        ),
      );
      expect(url, 'https://example.test/ok.mp3');
      expect(uploads, hasLength(1));
      expect(latin1.decode(uploads.single), contains('filename="sample.bin"'));
      expect(uploads.single, containsAllInOrder([0, 255, 1, 128]));
    },
    skip: Platform.environment['CYRENE_LX_NATIVE_TEST'] != '1',
  );
}
