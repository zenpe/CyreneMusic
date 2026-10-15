// Official just_audio native playlist trial. Node 22+, attached debug VM, ADB.
// Uses a local WAV/HTTP fixture, not third-party script APIs or plugin patches.
const fs = require('node:fs');
const http = require('node:http');
const cp = require('node:child_process');
const path = require('node:path');
const vmUrl = process.argv[2];
const tag = process.argv[3] || 'official-playlist-fixture';
if (!/^wss?:\/\//.test(vmUrl || '') || !/^[\w-]+$/.test(tag)) throw Error('VM URL and safe tag required');
const adb = process.env.ADB || 'adb';
const device = process.env.ANDROID_SERIAL ? ['-s', process.env.ANDROID_SERIAL] : [];
const nativePreload = process.env.PLAYLIST_PRELOAD_OFF !== '1';
const requests = [], records = [], jobs = new Map();
let seq = 0, isolateId, libs, port, playerId, previousBackend;
const wav = seconds => {
  const count = seconds * 22050, b = Buffer.alloc(44 + count * 2);
  b.write('RIFF'); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22);
  b.writeUInt32LE(22050, 24); b.writeUInt32LE(44100, 28); b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(count * 2, 40);
  for (let i = 0; i < count; i++) b.writeInt16LE(Math.round(Math.sin(i * 440 * Math.PI * 2 / 22050) * 500), 44 + i * 2);
  return b;
};
const long = wav(120), short = wav(4);
const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const item = { path: url.pathname, at: Date.now(), range: req.headers.range || null };
  requests.push(item);
  if (url.pathname.endsWith('/activate')) { res.end('ok'); return; }
  if (url.pathname.endsWith('/bad.wav')) { res.writeHead(403); res.end('denied'); return; }
  const bytes = url.pathname.endsWith('/short.wav') ? short : long;
  const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
  const start = range ? Number(range[1]) : 0;
  const end = range?.[2] ? Math.min(Number(range[2]), bytes.length - 1) : bytes.length - 1;
  if (start >= bytes.length) { res.writeHead(416, { 'Content-Range': `bytes */${bytes.length}` }); res.end(); return; }
  const headers = { 'Content-Type': 'audio/wav', 'Content-Length': end - start + 1, 'Accept-Ranges': 'bytes' };
  if (range) headers['Content-Range'] = `bytes ${start}-${end}/${bytes.length}`;
  const send = () => { if (!res.destroyed) { res.writeHead(range ? 206 : 200, headers); res.end(bytes.subarray(start, end + 1)); } };
  if (url.pathname.endsWith('/next.wav')) setTimeout(send, 1500); else send();
});
const ws = new WebSocket(vmUrl);
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const id = ++seq, timer = setTimeout(() => { jobs.delete(id); reject(Error(method + ' timeout')); }, 20000);
    jobs.set(id, { resolve, reject, timer }); ws.send(JSON.stringify({ jsonrpc: '2.0', id, method, params }));
  });
}
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data), j = jobs.get(msg.id); if (!j) return;
  clearTimeout(j.timer); jobs.delete(msg.id); msg.error ? j.reject(Error(msg.error.message)) : j.resolve(msg.result);
};
async function ev(expression, scope, suffix = 'audio_engine.dart') {
  const lib = libs.find(l => l.uri.endsWith('/' + suffix));
  const r = await rpc('evaluate', { isolateId, targetId: lib.id, expression: expression.replace(/\n/g, ' '), ...(scope ? { scope } : {}) });
  if (r.type.includes('Error')) throw Error(r.message); return r;
}
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const record = r => { records.push(r); console.log(JSON.stringify(r)); };
ws.onopen = async () => {
  try {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); port = server.address().port;
    cp.execFileSync(adb, [...device, 'reverse', `tcp:${port}`, `tcp:${port}`]);
    isolateId = (await rpc('getVM')).isolates.find(i => i.name === 'main').id;
    libs = (await rpc('getIsolate', { isolateId })).libraries;
    await ev('PlaybackService().stop()', null, 'playback_service.dart');
    previousBackend = await ev('EqualizerService()._equalizerBackend', null, 'equalizer_service.dart');
    const out = (await ev('List<String>.empty(growable:true)')).id;
    const done = (await ev('List<bool>.filled(1,false)')).id;
    const player = await ev(`ja.AudioPlayer(androidPlaylistPreloadDuration:Duration(seconds:${nativePreload ? 3 : 0}),useLazyPreparation:false,useProxyForRequestHeaders:false,handleAudioSessionActivation:false,handleInterruptions:false,audioLoadConfiguration:JustAudioEngine._audioLoadConfiguration)`);
    playerId = player.id;
    await ev(`(() async {
      final errors=<ja.PlayerException>[];
      final sub=player.errorStream.listen(errors.add);
      Future<void> marker(String name) async {final c=HttpClient();try{final r=await c.getUrl(Uri.parse('http://127.0.0.1:${port}/'+name+'/activate'));await (await r.close()).drain<void>();}finally{c.close(force:true);}}
      Future<void> settle(int index) async {final c=Stopwatch()..start();while(player.currentIndex!=index||player.processingState!=ja.ProcessingState.ready){if(errors.isNotEmpty)throw errors.last;if(c.elapsed>const Duration(seconds:5))throw TimeoutException('ready');await Future<void>.delayed(const Duration(milliseconds:10));}}
      try {
        await player.setVolume(0);
        for(final prepared in [false,true]) {
          for(var trial=0;trial<3;trial++) {
            final name=(prepared?'prepared':'cold')+trial.toString();errors.clear();
            await player.setAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/'+name+'/current.wav'))).timeout(const Duration(seconds:5));
            unawaited(player.play());
            if(prepared)await player.addAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/'+name+'/next.wav')));
            await Future<void>.delayed(const Duration(seconds:3));
            await marker(name);final c=Stopwatch()..start();
            if(prepared){await player.seek(Duration.zero,index:1).timeout(const Duration(seconds:5));}
            else{await player.setAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/'+name+'/next.wav'))).timeout(const Duration(seconds:5));}
            await settle(prepared?1:0);
            out.add(name+':ready_ms='+c.elapsedMilliseconds.toString());
            final p=player.position;await Future<void>.delayed(const Duration(milliseconds:350));
            out.add(name+':advanced='+(player.position>p).toString());
          }
        }
        errors.clear();
        await player.setAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/fault/current.wav')));
        unawaited(player.play());await player.addAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/fault/bad.wav')));
        final before=player.position;await Future<void>.delayed(const Duration(seconds:3));
        out.add('bad_preload:current_ok='+(player.currentIndex==0&&player.playing&&player.processingState==ja.ProcessingState.ready&&player.position>before&&errors.isEmpty).toString());
        try{await player.seek(Duration.zero,index:1).timeout(const Duration(seconds:3));}catch(e){out.add('bad_activation:'+e.runtimeType.toString());}
        out.add('bad_activation:errors='+errors.length.toString());
        await player.setAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/recovery/current.wav'))).timeout(const Duration(seconds:5));
        unawaited(player.play());await settle(0);out.add('recovery:ready=true');
        errors.clear();
        await player.setAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/natural/short.wav')));
        unawaited(player.play());await player.addAudioSource(ja.AudioSource.uri(Uri.parse('http://127.0.0.1:${port}/natural/next.wav')));
        await Future<void>.delayed(const Duration(seconds:7));
        out.add('natural:next_ok='+(player.currentIndex==1&&player.playing&&player.processingState==ja.ProcessingState.ready&&player.position>Duration.zero).toString());
        await player.stop();
        if(${nativePreload}) {
          final engine=JustAudioEngine(allowPlaylistPreload:true);
          try {
            await engine.setVolume(0);
            await engine.play('http://127.0.0.1:${port}/engine/current.wav',generation:501);
            PreparedPlaybackSlot slot(String key,String file,int generation)=>PreparedPlaybackSlot(key:key,source:DirectHttpPlayableSource('http://127.0.0.1:${port}/engine/'+file),expiresAt:DateTime.now().add(const Duration(minutes:1)),queueRevision:1,generation:generation,preparedFromGeneration:501,queueEntryId:generation,trackKey:key,nonce:generation);
            final current=slot('current','current.wav',501);
            final errors=<EngineError>[];final sub=engine.errorStream.listen(errors.add);
            try {
              await engine.bindCurrentPreparedSlot(current);
              await engine.preparePlaybackWindow(PreparedPlaybackWindow(current:current,next:slot('next','bad.wav',502)));
              final before=engine.position;await Future<void>.delayed(const Duration(seconds:3));
              out.add('engine_bad_preload:current_ok='+(engine.isPlaying&&engine.position>before&&errors.isEmpty).toString());
              final c=Stopwatch()..start();
              final activated=await engine.activatePreparedSlot('next',generation:502,queueRevision:1,loadTimeout:const Duration(seconds:2));
              out.add('engine_bad_activation:rejected='+(!activated).toString());
              out.add('engine_bad_activation:elapsed_ms='+c.elapsedMilliseconds.toString());
              await engine.play('http://127.0.0.1:${port}/engine/recovery.wav',generation:503);
              final p=engine.position;await Future<void>.delayed(const Duration(milliseconds:350));
              out.add('engine_recovery:playing='+(engine.isPlaying&&engine.position>p&&engine.canResumeSource(503)).toString());
              errors.clear();
              await engine.play('http://127.0.0.1:${port}/natural-fault/short.wav',generation:601);
              PreparedPlaybackSlot naturalSlot(String key,String file,int generation)=>PreparedPlaybackSlot(key:key,source:DirectHttpPlayableSource('http://127.0.0.1:${port}/natural-fault/'+file),expiresAt:DateTime.now().add(const Duration(minutes:1)),queueRevision:2,generation:generation,preparedFromGeneration:601,queueEntryId:generation,trackKey:key,nonce:generation);
              final naturalCurrent=naturalSlot('natural-current','short.wav',601);
              final commits=<EngineSourceCommit>[];final commitSub=engine.sourceCommitStream.listen(commits.add);
              try {
                await engine.bindCurrentPreparedSlot(naturalCurrent);
                await engine.preparePlaybackWindow(PreparedPlaybackWindow(current:naturalCurrent,next:naturalSlot('natural-bad','bad.wav',602)));
                final wait=Stopwatch()..start();
                while(errors.isEmpty&&wait.elapsed<const Duration(seconds:9)){await Future<void>.delayed(const Duration(milliseconds:50));}
                out.add('engine_natural_failure:next_epoch='+(errors.isNotEmpty&&errors.last.epoch==602).toString());
                out.add('engine_natural_failure:mode='+(commits.any((c)=>c.generation==602)?'after_ready':'before_ready'));
                final committedBeforeFailure=commits.length;
                await Future<void>.delayed(const Duration(milliseconds:350));
                out.add('engine_natural_failure:no_late_commit='+(commits.length==committedBeforeFailure).toString());
                await engine.play('http://127.0.0.1:${port}/engine/recovery.wav',generation:603);
                final after=engine.position;await Future<void>.delayed(const Duration(milliseconds:350));
                out.add('engine_natural_recovery:playing='+(engine.isPlaying&&engine.position>after).toString());
              }finally{await commitSub.cancel();}
            }finally{await sub.cancel();}
          }finally{await engine.dispose();}
        }
      }catch(e){out.add('failure:'+e.runtimeType.toString());}
      finally{await sub.cancel();await player.dispose();done[0]=true;}
    })()`, { player: playerId, out, done });
    await delay(45000);
    let complete = false;
    for (let i = 0; i < 12; i++) {
      if ((await ev('done[0].toString()', { done })).valueAsString === 'true') { complete = true; break; }
      await delay(5000);
    }
    const lineValue = await ev('out.join("\\n")', { out });
    const lines = (await rpc('getObject', { isolateId, objectId: lineValue.id, offset: 0, count: 20000 })).valueAsString;
    for (const line of lines.split('\n')) record({ result: line });
    for (const name of ['prepared0', 'prepared1', 'prepared2', 'cold0', 'cold1', 'cold2']) {
      const marker = requests.find(r => r.path === '/' + name + '/activate');
      const calls = requests.filter(r => r.path === '/' + name + '/next.wav');
      record({ name, requested_before_activation: !!marker && calls.some(r => r.at < marker.at), requests: calls.length });
    }
    const requiredResults = ['cold0:ready_ms=', 'cold1:ready_ms=', 'cold2:ready_ms=',
      'prepared0:ready_ms=', 'prepared1:ready_ms=', 'prepared2:ready_ms=',
      'bad_preload:current_ok=true', 'recovery:ready=true', 'natural:next_ok=true'];
    if (nativePreload) requiredResults.push('engine_bad_preload:current_ok=true',
      'engine_bad_activation:rejected=true', 'engine_recovery:playing=true',
      'engine_natural_failure:next_epoch=true', 'engine_natural_failure:no_late_commit=true',
      'engine_natural_recovery:playing=true');
    if (nativePreload && ['prepared0','prepared1','prepared2'].some(name => {
      const activation = requests.find(r => r.path === '/' + name + '/activate');
      return !activation || !requests.some(r => r.path === '/' + name + '/next.wav' && r.at < activation.at);
    })) process.exitCode = 1;
    if (!complete || requiredResults.some(result => !lines.includes(result)) ||
        lines.split('\n').some(line => line.startsWith('failure:')) || lines.includes('=false')) process.exitCode = 1;
    const cacheOut=(await ev('List<String>.empty(growable:true)')).id;
    const cacheDone=(await ev('List<bool>.filled(1,false)')).id;
    await ev(`(() async {
      final cache=CacheService(),enabled=CacheService().cacheEnabled;
      final track=Track(id:'__cyrene_cache_fixture_${tag}',name:'Cache fixture',artists:'',album:'',picUrl:'',source:MusicSource.netease);
      final detail=SongDetail(id:track.id,name:track.name,pic:'',arName:'',alName:'',level:'standard',size:'',url:'http://127.0.0.1:${port}/cache/short.wav',lyric:'',tlyric:'',source:track.source);
      try {
        await cache.setCacheEnabled(true);
        final absent=!cache.isCached(track,quality:'standard');
        final written=await PlaybackService()._cacheSongInBackground(track,detail,'standard');
        final file=cache.getCachedAudioFilePath(track,quality:'standard');
        out.add('android_cache:miss_written='+(absent&&written&&file!=null&&await File(file).exists()).toString());
      }catch(e){out.add('android_cache:failure='+e.runtimeType.toString());}
      finally{await cache.deleteCache(track,quality:'standard');await cache.setCacheEnabled(enabled);done[0]=true;}
    })()`,{out:cacheOut,done:cacheDone},'playback_service.dart');
    for(let i=0;i<15;i++){
      if((await ev('done[0].toString()',{done:cacheDone})).valueAsString==='true')break;
      await delay(1000);
    }
    const cacheResult=await ev('out.join(";")',{out:cacheOut});
    record({result:cacheResult.valueAsString});
    if(cacheResult.valueAsString!=='android_cache:miss_written=true')process.exitCode=1;
  } catch (error) { record({ failure: error.message }); process.exitCode = 1; }
  finally {
    try { if (playerId) await ev('player.dispose()', { player: playerId }); } catch {}
    try {
      if (previousBackend?.id) await ev('EqualizerService().setBackend(saved)', { saved: previousBackend.id }, 'equalizer_service.dart');
      else await ev('EqualizerService().setBackend(null)', null, 'equalizer_service.dart');
    } catch (error) { record({ restore_failure: error.message }); process.exitCode = 1; }
    if (port) cp.spawnSync(adb, [...device, 'reverse', '--remove', `tcp:${port}`]);
    server.closeAllConnections(); server.close(); ws.close();
    fs.writeFileSync(path.join(__dirname, '..', 'build', tag + '.json'), JSON.stringify({ records, requests }, null, 2));
  }
};
