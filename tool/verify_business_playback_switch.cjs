// Runs actual PlaybackService navigation without VM polling during switches.
// Node 22+, debug VM, ADB/ANDROID_SERIAL. Restores queue, mode, volume and cache.
const fs=require('node:fs'),cp=require('node:child_process'),path=require('node:path');
const url=process.argv[2],tag=process.argv[3]||'business-switch-baseline';
if(!/^wss?:\/\//.test(url||'')||!/^[\w-]+$/.test(tag))throw Error('VM websocket and safe tag required');
const adb=process.env.ADB||'adb',device=process.env.ANDROID_SERIAL?['-s',process.env.ANDROID_SERIAL]:[];
const ws=new WebSocket(url),jobs=new Map(),records=[],native=[];
let seq=0,isolateId,libs,logger,sink,logs,queue,index,source,bypass,mode,volume,cacheEnabled,frameSamples,frameCallback,cpuStart,playerRoute,navigator;
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
function rpc(method,params={}){return new Promise((resolve,reject)=>{const id=++seq,timer=setTimeout(()=>{jobs.delete(id);reject(Error(method+' timeout'));},15000);jobs.set(id,{resolve,reject,timer});ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));});}
ws.onmessage=({data})=>{const m=JSON.parse(data),j=jobs.get(m.id);if(!j)return;jobs.delete(m.id);clearTimeout(j.timer);m.error?j.reject(m.error):j.resolve(m.result);};
async function ev(expression,suffix='playback_service.dart',scope){const lib=libs.find(l=>l.uri.endsWith('/'+suffix));const r=await rpc('evaluate',{isolateId,targetId:lib.id,expression:expression.replace(/\n/g,' '),...(scope?{scope}:{})});if(r.type.includes('Error'))throw Error(r.message);return r;}
async function full(expression,scope){let r=await ev(expression,'playback_service.dart',scope);if(r.valueAsStringIsTruncated)r=await rpc('getObject',{isolateId,objectId:r.id});return r.valueAsString;}
function record(r){records.push(r);console.log(JSON.stringify(r));}
ws.onopen=async()=>{
  try{
    logger=cp.spawn(adb,[...device,'logcat','-T','1','-v','epoch','CyreneStream:D','*:S']);logger.stdout.on('data',s=>native.push(s.toString()));
    isolateId=(await rpc('getVM')).isolates.find(i=>i.name==='main').id;libs=(await rpc('getIsolate',{isolateId})).libraries;
    queue=(await ev('List<Track>.of(PlaybackService().queue)')).id;
    index=(await ev('PlaybackService()._currentIndex.toString()')).valueAsString;
    source=(await ev('PlaybackService().source.name')).valueAsString;
    volume=(await ev('PlaybackService().volume.toString()')).valueAsString;
    cacheEnabled=(await ev('CacheService().cacheEnabled.toString()')).valueAsString;
    if(!process.env.SWITCH_KEEP_CACHE)await ev('CacheService().setCacheEnabled(false)');
    bypass=(await ev('Set<String>.of(PlaybackService()._cacheBypassKeys)')).id;
    mode=(await ev('PlaybackModeService().currentMode.name')).valueAsString;
    sink=await ev('StructuredLogService.sink');logs=(await ev('List<String>.empty(growable:true)')).id;
    await ev('StructuredLogService.sink=(line)=>logs.add(line)','playback_service.dart',{logs});
    await ev('PlaybackModeService().setMode(PlaybackMode.loopAll)');
    const encoder=(await ev('jsonEncode','structured_log_service.dart')).id;
    if(process.env.SWITCH_PROFILE){
      frameSamples=(await ev('List<List<int>>.empty(growable:true)')).id;
      frameCallback=(await ev('(List timings){for(final t in timings){frames.add(<int>[DateTime.now().millisecondsSinceEpoch,t.buildDuration.inMicroseconds,t.rasterDuration.inMicroseconds,t.totalSpan.inMicroseconds]);}}','main.dart',{frames:frameSamples})).id;
      await ev('WidgetsBinding.instance.addTimingsCallback(callback)','main.dart',{callback:frameCallback});
      cpuStart=(await rpc('getVMTimelineMicros')).timestamp;
    }
    if(process.env.SWITCH_PLAYER_PAGE){
      navigator=(await ev('MyApp.navigatorKey.currentState','main.dart')).id;
      playerRoute=(await ev(`PageRouteBuilder(pageBuilder:(context,animation,secondaryAnimation)=>const PlayerPage(),opaque:${process.env.SWITCH_OPAQUE?'true':'false'},barrierColor:Colors.transparent)`,'mini_player.dart')).id;
      await ev('navigator.push(route)','mini_player.dart',{navigator,route:playerRoute});
      await delay(1000);
    }
    const groups=process.env.SWITCH_MIXED
      ? {mixed:[['004Vk6ep1Lg64Y','Forever Love','qq'],['22494904','Alive','netease'],['001nD3cW12eYk8','献给永远的','qq'],['442867526','Die For You','netease']]}
      : {qq:[['004Vk6ep1Lg64Y','Forever Love'],['001nD3cW12eYk8','献给永远的'],['000b5WcG2YFNbF','遗书']],netease:[['22494904','Alive'],['442867526','Die For You']]};
    for(const [platform,tracks] of Object.entries(groups)){
      const samples=(await ev('List<String>.empty(growable:true)')).id,done=(await ev('List<bool>.filled(1,false)')).id;
      const list=tracks.map(([id,name,source])=>`Track(id:${JSON.stringify(id)},name:${JSON.stringify(name)},artists:'',album:'',picUrl:'',source:MusicSource.${source||platform})`).join(',');
      await ev(`(() async {
        final p=PlaybackService(), tracks=<Track>[${list}];
        Future<void> settle(String expected) async {final c=Stopwatch()..start();while(p._pendingTrack!=null || p.currentTrack?.id.toString()!=expected || p.state!=PBState.playing){if(c.elapsed>const Duration(seconds:15))throw StateError('target not ready');await Future<void>.delayed(const Duration(milliseconds:40));}}
        void save(String kind,int elapsed){final t=p._engine.lastStartupTiming;samples.add(jsonEncode({'platform':'${platform}','kind':kind,'elapsed_ms':elapsed,'epoch':p._activePlaybackToken,'track':p.currentTrack?.id,'state':p.state.name,'pending':p._pendingTrack?.id,'error':p.errorMessage,'set_source_ms':t?.setSourceMs,'play_to_ready_ms':t?.playToReadyMs,'prepared':t?.preparedActivation,'epoch_ms':DateTime.now().millisecondsSinceEpoch}));}
        try{
          await p.stop();p._trackResolver.clear();await p._engine.setVolume(0);
          for(final t in tracks){p._cacheBypassKeys.add(p._cachePlaybackKey(t,AudioQualityService().currentQuality.value));}
          final clock=Stopwatch()..start();
          await p.playNow(tracks,0,QueueSource.none);await settle(tracks[0].id.toString());save('first',clock.elapsedMilliseconds);
          await Future<void>.delayed(const Duration(seconds:1));clock.reset();
          await p.next();await settle(tracks[1].id.toString());save('short_next',clock.elapsedMilliseconds);
          await Future<void>.delayed(const Duration(seconds:8));clock.reset();
          await p.next();await settle(tracks[2%tracks.length].id.toString());save('prefetched_next',clock.elapsedMilliseconds);
          final before=p.position;await Future<void>.delayed(const Duration(milliseconds:500));
          samples.add(jsonEncode({'platform':'${platform}','kind':'position','advanced':p.position>before}));
          await Future<void>.delayed(const Duration(seconds:7));
          final duration=p.duration;if(duration<const Duration(seconds:2))throw StateError('unknown duration');
          clock.reset();await p.seek(duration-const Duration(milliseconds:500));
          await settle(tracks[3%tracks.length].id.toString());save('auto_next',clock.elapsedMilliseconds);
          final rapid=Completer<void>();
          unawaited(p.jumpTo(0).catchError((Object _){}));
          Timer(const Duration(milliseconds:60),()=>unawaited(p.jumpTo(1).catchError((Object _){})));
          Timer(const Duration(milliseconds:120),()async{try{await p.jumpTo(tracks.length-1);}finally{rapid.complete();}});
          clock.reset();await rapid.future.timeout(const Duration(seconds:18));await settle(tracks.last.id.toString());save('rapid',clock.elapsedMilliseconds);
          await p.pause();await Future<void>.delayed(const Duration(milliseconds:150));save('pause',0);
          await p.resume();await settle(tracks.last.id.toString());save('resume',0);
          if('${platform}'=='mixed'){
            await p.seek(p.duration-const Duration(milliseconds:300));
            clock.reset();await p.jumpTo(0);await settle(tracks.first.id.toString());
            await Future<void>.delayed(const Duration(seconds:1));
            if(p.currentTrack?.id!=tracks.first.id || p._pendingTrack!=null)throw StateError('completion overrode manual target');
            save('manual_near_completion',clock.elapsedMilliseconds);
          }
        }catch(error){samples.add(jsonEncode({'platform':'${platform}','kind':'failure','type':error.runtimeType.toString(),'detail':error is StateError?error.message:null,'track':p.currentTrack?.id,'duration_ms':p.duration.inMilliseconds,'state':p.state.name,'pending':p._pendingTrack?.id,'error':p.errorMessage}));}
        finally{await p.stop();done[0]=true;}
      })()`,'playback_service.dart',{samples,done,jsonEncode:encoder});
      // Leave the isolate alone during ordinary switch/automatic navigation.
      await delay(45000);
      let finished=false;for(let i=0;i<15;i++){if((await ev('done[0].toString()','playback_service.dart',{done})).valueAsString==='true'){finished=true;break;}await delay(5000);}
      const text=await full('samples.join("\\n")',{samples});for(const line of text.split('\n').filter(Boolean))record(JSON.parse(line));
      if(!finished)throw Error(platform+' scenario did not finish');
    }
  }catch(error){record({kind:'diagnostic_error',message:error.message||error.data?.details});process.exitCode=1;}
  finally{
    try{
      await ev('PlaybackService().stop()');
      if(playerRoute)await ev('((){if(route.isActive)navigator.removeRoute(route);})()','mini_player.dart',{navigator,route:playerRoute});
      if(queue)await ev(`PlaybackService().setQueueSilent(saved,${index},QueueSource.${source})`,'playback_service.dart',{saved:queue});
      if(bypass)await ev('PlaybackService()._cacheBypassKeys..clear()..addAll(saved)','playback_service.dart',{saved:bypass});
      if(mode)await ev(`PlaybackModeService().setMode(PlaybackMode.${mode})`);
      if(volume)await ev(`PlaybackService()._engine.setVolume(${volume})`);
      if(cacheEnabled)await ev(`CacheService().setCacheEnabled(${cacheEnabled})`);
      if(logs){const text=await full('logs.join("\\n")',{logs});fs.writeFileSync(path.join(outputDirectory(),tag+'-events.jsonl'),text+'\n');}
      if(frameCallback){
        await ev('WidgetsBinding.instance.removeTimingsCallback(callback)','main.dart',{callback:frameCallback});
        const encoder=(await ev('jsonEncode','structured_log_service.dart')).id;
        const frames=await full('encode(frames)',{encode:encoder,frames:frameSamples});
        fs.writeFileSync(path.join(outputDirectory(),tag+'-frames.json'),frames);
      }
      if(cpuStart){
        try{
          const end=(await rpc('getVMTimelineMicros')).timestamp;
          const profile=await rpc('getCpuSamples',{isolateId,timeOriginMicros:cpuStart,timeExtentMicros:end-cpuStart});
          fs.writeFileSync(path.join(outputDirectory(),tag+'-cpu.json'),JSON.stringify(profile));
        }catch(error){record({kind:'profile_unavailable',message:error.message});}
      }
      if(sink?.kind!=='Null'&&sink?.id)await ev('StructuredLogService.sink=saved','playback_service.dart',{saved:sink.id});else await ev('StructuredLogService.sink=null');
      record({kind:'restored',passed:!records.some(r=>r.kind==='failure'||r.kind==='diagnostic_error'||r.kind==='position'&&!r.advanced)});
    }catch(error){record({kind:'restore_error',message:error.message});process.exitCode=1;}
    logger?.kill();ws.close();
    fs.writeFileSync(path.join(outputDirectory(),tag+'-results.jsonl'),records.map(r=>JSON.stringify(r)).join('\n')+'\n');
    fs.writeFileSync(path.join(outputDirectory(),tag+'-native.log'),native.join(''));
    if(records.some(r=>r.kind==='failure'||r.kind==='position'&&!r.advanced))process.exitCode=1;
  }
};
function outputDirectory(){const directory=path.resolve(__dirname,'..','build');fs.mkdirSync(directory,{recursive:true});return directory;}
