// Non-destructive app QA over a Flutter debug VM. Node 22+, ADB required.
// Tests only a newly created QA playlist; always restores theme, rotation and hooks.
const fs = require('node:fs'), cp = require('node:child_process'), path = require('node:path');
const [url, phase = 'ui'] = process.argv.slice(2);
if (!/^wss?:\/\//.test(url || '') || !['ui', 'playlist', 'probe', 'data','touch','robustness','layout'].includes(phase)) throw Error('VM URL and QA phase required');
const adb = process.env.ADB || 'adb', directory = path.resolve(__dirname, '../build');
const ws = new WebSocket(url), jobs = new Map(), records = [];
let sequence = 0, isolateId, libraries, oldError, errors, frameCallback, frames, savedSink, playbackLogs;
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
const device = (...args) => cp.execFileSync(adb, ['-s', 'emulator-5554', ...args], {encoding:'utf8',timeout:30000});
function record(value) { records.push(value); console.log(JSON.stringify(value)); }
function rpc(method, params = {}) { return new Promise((resolve,reject) => {
  const id=++sequence,timer=setTimeout(()=>{jobs.delete(id);reject(Error(method+' timed out'));},20000);
  jobs.set(id,{resolve,reject,timer});ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));
}); }
ws.onmessage=({data})=>{const m=JSON.parse(data),j=jobs.get(m.id);if(!j)return;clearTimeout(j.timer);jobs.delete(m.id);m.error?j.reject(Error(m.error.message)):j.resolve(m.result);};
async function ev(expression,suffix='main.dart',scope) {
  const library=libraries.find(l=>l.uri.endsWith('/'+suffix));if(!library)throw Error('Library unavailable: '+suffix);
  let result=await rpc('evaluate',{isolateId,targetId:library.id,expression:expression.replace(/\n/g,' '),...(scope?{scope}:{})});
  if(result.type.includes('Error'))throw Error(result.message);
  if(result.valueAsStringIsTruncated)result=await rpc('getObject',{isolateId,objectId:result.id});
  return result;
}
async function value(expression,suffix,scope){return (await ev(expression,suffix,scope)).valueAsString;}
async function mutate(expression,suffix='main.dart',scope){
  const action=(await ev(`(){${expression};}`,suffix,scope)).id;
  // VM evaluation can interrupt an in-progress build. Run UI actions on the
  // next event-loop turn and request a frame, as real input dispatch would.
  return ev('Future<void>(() {action();WidgetsBinding.instance.scheduleFrame();})','main.dart',{action});
}
async function state(name) {
  return ev(`((){State? found;void visit(Element e){if(e is StatefulElement&&e.state.runtimeType.toString()=='${name}')found=e.state;e.visitChildren(visit);}final root=WidgetsBinding.instance.rootElement;if(root!=null)visit(root);return found;})()`);
}
async function task(expression,suffix,timeout=45000) {
  const results=(await ev('List<String>.empty(growable:true)')).id,done=(await ev('List<bool>.filled(1,false)')).id;
  await ev(`Future<void>(() async {try{${expression}}catch(e){out.add('exception:'+e.runtimeType.toString());}finally{done[0]=true;}})`,suffix,{out:results,done});
  const started=Date.now();while(await value('done[0].toString()',undefined,{done})!=='true') {
    if(Date.now()-started>timeout)throw Error('QA task deadline exceeded');await pause(500);
  }
  const result=await value('out.join(";")',undefined,{out:results});record({phase,result});
  if(result.includes('=false')||result.includes('exception:'))process.exitCode=1;
  return result;
}
function memory(label) {
  const output=device('shell','dumpsys','meminfo','com.cyrene.music');
  const pss=/TOTAL PSS:\s+(\d+)/.exec(output),rss=/TOTAL RSS:\s+(\d+)/.exec(output);
  record({kind:'memory',label,pss_kib:pss?Number(pss[1]):null,rss_kib:rss?Number(rss[1]):null});
}
function screenshot(label){const remote='/sdcard/cyrene-qa.png';device('shell','screencap','-p',remote);device('pull',remote,path.join(directory,'qa-'+label+'.png'));}
function tapLabel(label){
  device('shell','uiautomator','dump','/sdcard/cyrene-qa-window.xml');
  const xml=device('shell','cat','/sdcard/cyrene-qa-window.xml');
  const nodes=[...xml.matchAll(/<node\b[^>]*>/g)].map(m=>Object.fromEntries([...m[0].matchAll(/([\w-]+)="([^"]*)"/g)].map(x=>[x[1],x[2]])));
  const node=nodes.filter(n=>n.text===label||n['content-desc']===label).at(-1);
  if(!node)throw Error('UI label unavailable: '+label);
  const b=node.bounds.match(/\d+/g).map(Number);device('shell','input','tap',String(Math.round((b[0]+b[2])/2)),String(Math.round((b[1]+b[3])/2)));
}
ws.onopen=async()=>{
  let framework,mode,page,rotation,autoRotation,searchHistory,searchResult,keyword,airplane,savedQueue,savedQueueIndex,savedQueueSource,savedVolume,savedBypass,fontScale;
  try {
    isolateId=(await rpc('getVM')).isolates.find(i=>i.name==='main').id;
    libraries=(await rpc('getIsolate',{isolateId})).libraries;
    record({kind:'session',logged_in:await value('AuthService().isLoggedIn.toString()','playback_service.dart'),source_configured:await value('AudioSourceService().isConfigured.toString()','playback_service.dart')});
    if(phase==='probe'){
      record({kind:'states',value:await value(`((){final types=<String>{};void visit(Element e){if(e is StatefulElement)types.add(e.state.runtimeType.toString());e.visitChildren(visit);}visit(WidgetsBinding.instance.rootElement!);return types.where((s)=>s.contains('Page')||s.contains('Layout')||s.contains('Search')).join(',');})()`)});
      record({kind:'playback',state:await value('PlaybackService().state.name','playback_service.dart'),pending:await value('PlaybackService().isTrackSwitchPending.toString()','playback_service.dart'),error:await value('PlaybackService().errorMessage??"none"','playback_service.dart'),problem:await value('PlaybackService().currentProblem?.kind.name??"none"','playback_service.dart')});
      return;
    }
    if(phase==='robustness'){
      savedSink=await ev('StructuredLogService.sink','playback_service.dart');
      playbackLogs=(await ev('List<String>.empty(growable:true)')).id;
      await ev('StructuredLogService.sink=(line)=>logs.add(line)','playback_service.dart',{logs:playbackLogs});
      savedQueue=(await ev('List<Track>.of(PlaybackService().queue)','playback_service.dart')).id;
      savedQueueIndex=await value('PlaybackService()._currentIndex.toString()','playback_service.dart');
      savedQueueSource=await value('PlaybackService().source.name','playback_service.dart');
      savedVolume=await value('PlaybackService().volume.toString()','playback_service.dart');
      savedBypass=(await ev('Set<String>.of(PlaybackService()._cacheBypassKeys)','playback_service.dart')).id;
      const tracks=(await ev(`List<Track>.of([Track(id:'004Vk6ep1Lg64Y',name:'Forever Love',artists:'',album:'',picUrl:'',source:MusicSource.qq),Track(id:'22494904',name:'Alive',artists:'',album:'',picUrl:'',source:MusicSource.netease)])`,'playback_service.dart')).id;
      await ev('PlaybackService()._engine.setVolume(0)','playback_service.dart');
      await task(`await PlaybackService().playNow([Track(id:'004Vk6ep1Lg64Y',name:'Forever Love',artists:'',album:'',picUrl:'',source:MusicSource.qq),Track(id:'22494904',name:'Alive',artists:'',album:'',picUrl:'',source:MusicSource.netease)],0,QueueSource.none);out.add('baseline_playing='+(PlaybackService().state==PBState.playing).toString());`,'playback_service.dart');
      if(await value('PlaybackService().state.name','playback_service.dart')!=='playing'){
        record({kind:'baseline_failure',cause:await value('PlaybackService()._lastFailureEvidence?.cause.name??"none"','playback_service.dart'),scope:await value('PlaybackService()._lastFailureEvidence?.scope.name??"none"','playback_service.dart')});
        await task(`await PlaybackService().playNow([Track(id:'22494904',name:'Alive',artists:'',album:'',picUrl:'',source:MusicSource.netease)],0,QueueSource.none);out.add('fallback_playing='+(PlaybackService().state==PBState.playing).toString());`,'playback_service.dart');
        if(await value('PlaybackService().state.name','playback_service.dart')!=='playing'){record({kind:'background_skipped',reason:'no_playable_baseline',cause:await value('PlaybackService()._lastFailureEvidence?.cause.name??"none"','playback_service.dart')});return;}
      }
      const before=Number(await value('PlaybackService().position.inMilliseconds.toString()','playback_service.dart'));
      device('shell','input','keyevent','3');device('shell','input','keyevent','223');await pause(10000);
      const after=Number(await value('PlaybackService().position.inMilliseconds.toString()','playback_service.dart'));
      record({kind:'screen_off_background',position_advanced_ms:after-before,state:await value('PlaybackService().state.name','playback_service.dart')});
      device('shell','cmd','media_session','dispatch','pause');await pause(700);
      record({kind:'system_pause',state:await value('PlaybackService().state.name','playback_service.dart')});
      device('shell','cmd','media_session','dispatch','play');await pause(700);
      device('shell','cmd','media_session','dispatch','next');await pause(10000);
      record({kind:'system_next',track:await value('PlaybackService().currentTrack?.id.toString()??"none"','playback_service.dart'),state:await value('PlaybackService().state.name','playback_service.dart'),app_opened:/mResumedActivity.*com\.cyrene\.music/.test(device('shell','dumpsys','activity','activities'))});
      device('shell','input','keyevent','224');device('shell','wm','dismiss-keyguard');device('shell','am','start','-n','com.cyrene.music/.MainActivity');
      airplane=device('shell','settings','get','global','airplane_mode_on').trim();
      device('shell','cmd','connectivity','airplane-mode','enable');await pause(1500);
      const offlineStart=Date.now();
      await task(`final p=PlaybackService();p._trackResolver.clear();final track=Track(id:'000b5WcG2YFNbF',name:'遗书',artists:'',album:'',picUrl:'',source:MusicSource.qq);p._cacheBypassKeys.add(p._cachePlaybackKey(track,AudioQualityService().currentQuality.value));await p.playNow([track],0,QueueSource.none).timeout(const Duration(seconds:16));out.add('offline_pending_released='+(!p.isTrackSwitchPending).toString());out.add('offline_state='+p.state.name);`,'playback_service.dart',20000);
      record({kind:'offline_duration',elapsed_ms:Date.now()-offlineStart});
      device('shell','cmd','connectivity','airplane-mode',airplane==='1'?'enable':'disable');await pause(2000);
      await task(`await PlaybackService().playNow([Track(id:'22494904',name:'Alive',artists:'',album:'',picUrl:'',source:MusicSource.netease)],0,QueueSource.none);out.add('online_recovered='+(PlaybackService().state==PBState.playing&&!PlaybackService().isTrackSwitchPending).toString());`,'playback_service.dart');
      memory('robustness_end');return;
    }
    if(phase==='touch'){
      autoRotation=device('shell','settings','get','system','accelerometer_rotation').trim();rotation=device('shell','settings','get','system','user_rotation').trim();
      device('shell','settings','put','system','accelerometer_rotation','0');device('shell','settings','put','system','user_rotation','0');await pause(2500);
      tapLabel('首页');await pause(2000);tapLabel('搜索');await pause(1500);
      const search=await state('_SearchWidgetState');if(search.kind==='Null')throw Error('Search did not open after actual tap');
      searchHistory=(await ev('List<String>.of(SearchService().searchHistory)','search_service.dart')).id;
      searchResult=await ev('SearchService().searchResult','search_service.dart');keyword=await value('SearchService().currentKeyword','search_service.dart');
      device('shell','input','text','Jay');await pause(1300);
      record({kind:'search_input',typed:await value('state._searchController.text','search_widget.dart',{state:search.id}),no_auto:(await value('SearchService().currentKeyword','search_service.dart'))===keyword});
      device('shell','input','keyevent','66');await pause(500);
      const clock=Date.now();while(await value('SearchService().searchResult.allCompleted.toString()','search_service.dart')!=='true'&&Date.now()-clock<25000)await pause(500);
      record({kind:'search_result',completed:await value('SearchService().searchResult.allCompleted.toString()','search_service.dart'),keyword:await value('SearchService().currentKeyword','search_service.dart'),netease_count:await value('SearchService().searchResult.neteaseResults.length.toString()','search_service.dart'),qq_count:await value('SearchService().searchResult.qqResults.length.toString()','search_service.dart'),netease_failed:await value('(SearchService().searchResult.neteaseError!=null).toString()','search_service.dart'),qq_failed:await value('(SearchService().searchResult.qqError!=null).toString()','search_service.dart')});
      if(/mInputShown=true|inputShown=true/.test(device('shell','dumpsys','input_method')))device('shell','input','keyevent','4');
      await pause(300);screenshot('touch-search');
      await mutate('state._handleTabChanged(1)','search_widget.dart',{state:search.id});await pause(500);
      record({kind:'search_tab',selected:await value('state._selectedTab.key','search_widget.dart',{state:search.id})});
      await mutate('state._clearSearchInputAndResult()','search_widget.dart',{state:search.id});await pause(500);
      record({kind:'search_clear',empty:await value('state._searchController.text.isEmpty.toString()','search_widget.dart',{state:search.id})});
      device('shell','input','keyevent','4');await pause(700);
      tapLabel('发现');await pause(1500);device('shell','input','tap','280','650');await pause(1000);
      const detail=await state('_DiscoverPlaylistDetailContentState');
      if(detail.kind!=='Null'){
        const wait=Date.now();while(await value('state._detail==null?"waiting":"ready"','discover_playlist_detail_page.dart',{state:detail.id})==='waiting'&&Date.now()-wait<20000)await pause(500);
        record({kind:'discover_detail',counts:await value('state._detail==null?"missing":state._detail!.tracks.length.toString()+"/"+state._detail!.trackCount.toString()','discover_playlist_detail_page.dart',{state:detail.id})});screenshot('touch-discover-detail');device('shell','input','keyevent','4');await pause(700);
      }else record({kind:'discover_detail',opened:false});
      tapLabel('我的');await pause(1200);screenshot('touch-my');
      try{tapLabel('设置');}catch(_){tapLabel('更多');await pause(700);tapLabel('设置');}
      await pause(1200);screenshot('touch-settings');
      record({kind:'actual_touch_navigation',passed:true});memory('touch_end');
      return;
    }
    if(phase==='data'){
      await task(`final service=MusicService();final preview=service.toplists.first;final full=await service.fetchToplistDetail(preview);out.add('home_preview='+preview.tracks.length.toString());out.add('home_full='+full.tracks.length.toString());out.add('home_complete='+(full.tracks.length==full.trackCount).toString());`,'music_service.dart');
      await task(`final service=NeteaseDiscoverService();await service.fetchDiscoverPlaylists();out.add('discover_cards='+service.playlists.length.toString());final first=service.playlists.first;final detail=await service.fetchPlaylistDetail(first.id);out.add('discover_full='+(detail?.tracks.length.toString()??'null'));out.add('discover_complete='+(detail!=null&&detail.tracks.length==detail.trackCount).toString());`,'netease_discover_service.dart');
      await task(`final service=SearchService();final keyword=service._currentKeyword,previous=service._searchResult;try{await service.search('Jay',saveHistory:false);final r=service.searchResult;out.add('search_completed='+r.allCompleted.toString());out.add('netease_results='+r.neteaseResults.length.toString());out.add('qq_results='+r.qqResults.length.toString());out.add('netease_error='+(r.neteaseError!=null).toString());out.add('qq_error='+(r.qqError!=null).toString());}finally{service._currentKeyword=keyword;service._searchResult=previous;service.notifyListeners();}`,'search_service.dart');
      return;
    }
    if(phase==='playlist'){
      await task(`
        final service=PlaylistService();final before=service.currentPlaylistId;
        final created=await service.createPlaylist('__QA_functional_'+DateTime.now().millisecondsSinceEpoch.toString());
        out.add('created='+(created!=null).toString());if(created==null)return;
        try{
          final id=created.id;
          final renamed=await service.updatePlaylist(id,'__QA_renamed_'+id.toString());
          out.add('renamed='+(renamed&&service.playlists.any((p)=>p.id==id&&p.name=='__QA_renamed_'+id.toString())).toString());
          final track=Track(id:'22494904',name:'Alive',artists:'QA fixture',album:'',picUrl:'',source:MusicSource.netease);
          out.add('added='+(await service.addTrackToPlaylist(id,track)).toString());
          await service.loadPlaylistTracks(id);out.add('one_track='+(service.currentTracks.length==1).toString());
          out.add('duplicate_response='+((await service.addTrackToPlaylist(id,track))?'accepted':'rejected'));
          await service.loadPlaylistTracks(id);out.add('deduplicated='+(service.currentTracks.length==1).toString());
          if(service.currentTracks.isNotEmpty)out.add('removed='+(await service.removePlaylistTrack(id,service.currentTracks.single)).toString());
          await service.loadPlaylistTracks(id);out.add('empty='+(service.currentTracks.isEmpty).toString());
        }finally{
          final deleted=await service.deletePlaylist(created.id);out.add('qa_playlist_deleted='+deleted.toString());
          if(before!=null)await service.loadPlaylistTracks(before);
        }
      `,'playlist_service.dart',90000);
      return;
    }
    framework=await value('ThemeManager().mobileThemeFramework.name','theme_manager.dart');
    mode=await value('ThemeManager().themeMode.name','theme_manager.dart');
    page=await value('PageVisibilityNotifier().currentPageIndex.toString()','main_layout.dart');
    autoRotation=device('shell','settings','get','system','accelerometer_rotation').trim();
    rotation=device('shell','settings','get','system','user_rotation').trim();
    errors=(await ev('List<String>.empty(growable:true)')).id;
    oldError=await ev('FlutterError.onError');
    if(phase==='layout'){
      await ev(`FlutterError.onError=(details){errors.add(details.toString());}`,undefined,{errors});
      fontScale=device('shell','settings','get','system','font_scale').trim();
      device('shell','settings','put','system','accelerometer_rotation','0');
      for(const theme of ['material','cupertino']){
        device('shell','settings','put','system','font_scale','1');device('shell','settings','put','system','user_rotation','0');await pause(3000);
        await mutate(`ThemeManager().setMobileThemeFramework(MobileThemeFramework.${theme})`,'theme_manager.dart');await pause(1000);
        tapLabel('发现');await pause(2000);
        for(const scale of [1,1.5]){
          device('shell','settings','put','system','font_scale',String(scale));
          for(const orientation of [0,1]){
            device('shell','settings','put','system','user_rotation',String(orientation));await pause(3000);
            const miniMounted=(await state('_MiniPlayerState')).kind!=='Null';
            record({kind:'layout',theme,scale,orientation,error_count:Number(await value('errors.length.toString()',undefined,{errors})),discover_mounted:(await state('_DiscoverPageState')).kind!=='Null',mini_player_mounted:miniMounted});
            if(!miniMounted)process.exitCode=1;
            screenshot(`ui-fixes-${theme}-${scale}-${orientation}`);
          }
        }
        device('shell','settings','put','system','font_scale','1');device('shell','settings','put','system','user_rotation','0');await pause(3000);
        tapLabel('首页');await pause(3000);screenshot(`ui-fixes-${theme}-home`);
      }
      const count=Number(await value('errors.length.toString()',undefined,{errors}));if(count)process.exitCode=1;
      record({kind:'layout_complete',errors:count});return;
    }
    await ev(`FlutterError.onError=(details){errors.add(details.exception.runtimeType.toString()+':'+details.exceptionAsString().split('\\n').first.replaceAll(RegExp(r'https?://[^ ]+'),'<url>'));try{if(previous!=null)previous(details);}catch(_){}}`,undefined,{errors,previous:oldError.id});
    frames=(await ev('List<List<int>>.empty(growable:true)')).id;
    frameCallback=(await ev('(List timings){for(final t in timings)frames.add(<int>[t.buildDuration.inMicroseconds,t.rasterDuration.inMicroseconds,t.totalSpan.inMicroseconds]);}',undefined,{frames})).id;
    await ev('WidgetsBinding.instance.addTimingsCallback(callback)',undefined,{callback:frameCallback});
    memory('ui_start');
    device('shell','settings','put','system','accelerometer_rotation','0');
    for(const theme of (process.env.QA_THEME?[process.env.QA_THEME]:['material','cupertino'])){
      await mutate(`ThemeManager().setMobileThemeFramework(MobileThemeFramework.${theme})`,'theme_manager.dart');
      for(const orientation of [0,1]){
        device('shell','settings','put','system','user_rotation',String(orientation));await pause(1500);
        for(const [tab,index] of [['home',0],['discover',1],['my',4],['settings',5]]){
          await mutate(`PageVisibilityNotifier().setCurrentPage(${index})`,'main_layout.dart');await pause(1200);
          const size=await value('WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.toString()');
          const errorCount=Number(await value('errors.length.toString()',undefined,{errors}));
          record({kind:'page',theme,orientation,tab,size,error_count:errorCount,alive:device('shell','pidof','com.cyrene.music').trim()!==''});
          screenshot(`${theme}-${orientation}-${tab}`);
          if(tab==='home'){
            device('shell','input','swipe','540','1550','540','550','450');await pause(300);
            device('shell','input','swipe','540','550','540','1550','450');
          }
        }
      }
    }
    device('shell','settings','put','system','user_rotation','0');
    await mutate('ThemeManager().setMobileThemeFramework(MobileThemeFramework.cupertino)','theme_manager.dart');
    await mutate('PageVisibilityNotifier().setCurrentPage(0)','main_layout.dart');await pause(1000);
    searchHistory=(await ev('List<String>.of(SearchService().searchHistory)','search_service.dart')).id;
    searchResult=await ev('SearchService().searchResult','search_service.dart');
    keyword=await value('SearchService().currentKeyword','search_service.dart');
    await mutate('HomeSearchService().requestSearch()','home_page.dart');await pause(1200);
    const search=await state('_SearchWidgetState');if(search.kind==='Null')throw Error('Search overlay did not mount');
    const before=await value('SearchService().currentKeyword','search_service.dart');
    device('shell','input','text','Jay');await pause(1200);
    const typed=await value('state._searchController.text','search_widget.dart',{state:search.id});
    const unchanged=await value('SearchService().currentKeyword','search_service.dart');
    record({kind:'search_input',text_entered:typed==='Jay',no_automatic_search:unchanged===before});
    if(typed!=='Jay'||unchanged!==before)process.exitCode=1;
    device('shell','input','keyevent','66');await pause(500);
    const began=Date.now();while(await value('SearchService().searchResult.allCompleted.toString()','search_service.dart')!=='true'&&Date.now()-began<25000)await pause(500);
    record({kind:'search_result',completed:await value('SearchService().searchResult.allCompleted.toString()','search_service.dart'),keyword:await value('SearchService().currentKeyword','search_service.dart'),counts:await value('SearchService().searchResult.neteaseResults.length.toString()+","+SearchService().searchResult.qqResults.length.toString()','search_service.dart')});
    device('shell','input','keyevent','4');
    await mutate('state._handleTabChanged(1)','search_widget.dart',{state:search.id});await pause(500);
    record({kind:'search_tab',selected:await value('state._selectedTab.key','search_widget.dart',{state:search.id})});
    screenshot('search-results');
    await mutate('state._clearSearchInputAndResult()','search_widget.dart',{state:search.id});await pause(300);
    record({kind:'search_clear',empty:await value('state._searchController.text.isEmpty.toString()','search_widget.dart',{state:search.id})});
    await mutate('HomeOverlayController().handleBack()','home_page.dart');
    for(let i=0;i<16;i++){await mutate(`PageVisibilityNotifier().setCurrentPage(${[0,1,4,5][i%4]})`,'main_layout.dart');await pause(180);}
    await mutate('ThemeManager().setThemeMode(ThemeMode.dark)','theme_manager.dart');await pause(700);screenshot('cupertino-dark-settings');
    memory('ui_end');
    const allocation=await rpc('getAllocationProfile',{isolateId,gc:true});
    record({kind:'dart_heap_after_gc',usage:allocation.memoryUsage});await pause(500);memory('ui_after_gc');
    const errorLines=await value('errors.join("\\n")',undefined,{errors});
    fs.writeFileSync(path.join(directory,'qa-ui-errors.log'),errorLines);
    record({kind:'flutter_errors',count:errorLines?errorLines.split('\n').length:0});
    const frameLines=await value('frames.map((f)=>f.join(",")).join("\\n")',undefined,{frames});
    fs.writeFileSync(path.join(directory,'qa-ui-frames.csv'),frameLines);
  }catch(error){record({kind:'test_error',message:error.message});process.exitCode=1;}
  finally{
    try{
      if(playbackLogs){fs.writeFileSync(path.join(directory,'qa-robustness-playback-events.jsonl'),await value('logs.join("\\n")','playback_service.dart',{logs:playbackLogs}));await ev('StructuredLogService.sink=saved','playback_service.dart',{saved:savedSink.id});}
      if(airplane!==undefined)device('shell','cmd','connectivity','airplane-mode',airplane==='1'?'enable':'disable');
      if(savedQueue){await ev('PlaybackService().stop()','playback_service.dart');await ev(`PlaybackService().setQueueSilent(saved,${savedQueueIndex},QueueSource.${savedQueueSource})`,'playback_service.dart',{saved:savedQueue});}
      if(savedVolume)await ev(`PlaybackService()._engine.setVolume(${savedVolume})`,'playback_service.dart');
      if(savedBypass)await ev('PlaybackService()._cacheBypassKeys..clear()..addAll(saved)','playback_service.dart',{saved:savedBypass});
      if(errors){const text=await value('errors.join("\\n")',undefined,{errors});fs.writeFileSync(path.join(directory,phase==='layout'?'ui-fixes-errors.log':'qa-ui-errors.log'),text);record({kind:'captured_errors',count:text?text.split('\n').length:0});}
      if(frames){const text=await value('frames.map((f)=>f.join(",")).join("\\n")',undefined,{frames});fs.writeFileSync(path.join(directory,'qa-ui-frames.csv'),text);}
      if(frameCallback)await ev('WidgetsBinding.instance.removeTimingsCallback(callback)',undefined,{callback:frameCallback});
      if(oldError?.id)await ev('FlutterError.onError=saved',undefined,{saved:oldError.id});
      if(searchHistory){
        await ev(`(() async {SearchService()._searchHistory=List<String>.of(saved);final prefs=await SharedPreferences.getInstance();await prefs.setStringList('search_history',saved);})()`,'search_service.dart',{saved:searchHistory});
        if(searchResult?.id)await ev('SearchService()._searchResult=saved','search_service.dart',{saved:searchResult.id});
        if(keyword!==undefined)await ev(`SearchService()._currentKeyword=${JSON.stringify(keyword)}`,'search_service.dart');
      }
      if(framework)await mutate(`ThemeManager().setMobileThemeFramework(MobileThemeFramework.${framework})`,'theme_manager.dart');
      if(mode)await mutate(`ThemeManager().setThemeMode(ThemeMode.${mode})`,'theme_manager.dart');
      if(page)await mutate(`PageVisibilityNotifier().setCurrentPage(${page})`,'main_layout.dart');
      if(rotation)device('shell','settings','put','system','user_rotation',rotation);
      if(fontScale!==undefined)device('shell','settings','put','system','font_scale',fontScale==='null'?'1':fontScale);
      if(autoRotation)device('shell','settings','put','system','accelerometer_rotation',autoRotation);
      record({kind:'restored',phase});
    }catch(error){record({kind:'restore_error',message:error.message});process.exitCode=1;}
    fs.writeFileSync(path.join(directory,'qa-functional-'+phase+'.json'),JSON.stringify(records,null,2));ws.close();
  }
};
