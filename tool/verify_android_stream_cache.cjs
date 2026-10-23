// Non-destructive native-cache regression over a running Flutter debug VM.
// Node 22+, ADB. Only unique QA resources are removed; settings are restored.
const http = require('node:http'), cp = require('node:child_process');
const fs = require('node:fs'), path = require('node:path');
const endpoint = process.argv[2], adb = process.env.ADB || 'adb';
if (!/^wss?:\/\//.test(endpoint || '')) throw Error('VM websocket required');
const ws = new WebSocket(endpoint), jobs = new Map(), requests = [], records = [];
const oneShotConnections = new Map();
let sequence = 0, isolateId, libraries, player, port, original, root, crashed=false;
const id = 'native-cache-qa-' + Date.now();
const delay = ms => new Promise(r => setTimeout(r, ms));
const wav = Buffer.alloc(44 + 22050 * 2 * 180);
wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
wav.writeUInt32LE(22050, 24); wav.writeUInt32LE(44100, 28); wav.writeUInt16LE(2, 32);
wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(wav.length - 44, 40);
const server = http.createServer((req, res) => {
  requests.push({url: req.url, range: req.headers.range || null});
  const token = new URL(req.url, 'http://localhost').searchParams.get('token');
  const oneShot = token?.startsWith('single-');
  if (oneShot && oneShotConnections.has(token)) {
    res.writeHead(403); res.end('expired'); return;
  }
  const range = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
  const start = range ? +range[1] : 0;
  const end = range?.[2] ? Math.min(+range[2], wav.length - 1) : wav.length - 1;
  if (start >= wav.length) { res.writeHead(416); res.end(); return; }
  const headers = {'Content-Type':'audio/wav','Content-Length':end-start+1,'Accept-Ranges':'bytes'};
  if (range) headers['Content-Range'] = `bytes ${start}-${end}/${wav.length}`;
  res.writeHead(range ? 206 : 200, headers);
  if (!oneShot) { res.end(wav.subarray(start, end + 1)); return; }
  // One valid connection, subsequent opens rejected. Throttle so maintenance
  // happens during real upstream reads, rather than only buffered playback.
  const connection = {bytes:0, closed:false};
  oneShotConnections.set(token, connection);
  let cursor=start;
  const timer=setInterval(()=>{
    if(res.destroyed)return;
    const next=Math.min(cursor+16384,end+1);
    if(next>cursor) {res.write(wav.subarray(cursor,next));connection.bytes+=next-cursor;cursor=next;}
    if(cursor>end){clearInterval(timer);res.end();}
  },25);
  res.on('close',()=>{connection.closed=true;clearInterval(timer);});
});
function record(value) { records.push(value); console.log(JSON.stringify(value)); }
function check(condition, label) { if (!condition) throw Error(label); record({pass:label}); }
function rpc(method, params = {}) {
  return new Promise((resolve, reject) => {
    const n = ++sequence, timer = setTimeout(() => {jobs.delete(n);reject(Error(method+' timeout'));},20000);
    jobs.set(n,{resolve,reject,timer});ws.send(JSON.stringify({jsonrpc:'2.0',id:n,method,params}));
  });
}
ws.onmessage = ({data}) => {
  const message=JSON.parse(data), job=jobs.get(message.id);if(!job)return;
  jobs.delete(message.id);clearTimeout(job.timer);
  message.error?job.reject(Error(message.error.message)):job.resolve(message.result);
};
async function ev(expression, suffix='audio_engine.dart', scope) {
  const library=libraries.find(l=>l.uri.endsWith('/'+suffix));
  const result=await rpc('evaluate',{isolateId,targetId:library.id,expression:expression.replace(/\n/g,' '),...(scope?{scope}:{})});
  if(result.type.includes('Error')) throw Error(result.message);
  return result;
}
async function task(expression, suffix='audio_engine.dart', scope={}) {
  const out=(await ev('List<String>.empty(growable:true)')).id;
  await ev(`Future<void>(() async {try {${expression};out.add('ok');}catch(e){out.add('error:'+e.toString());}})`,suffix,{...scope,out});
  const started=Date.now();
  while((await ev('out.isEmpty.toString()',undefined,{out})).valueAsString==='true') {
    if(Date.now()-started>22000)throw Error('native task deadline');await delay(120);
  }
  const result=(await ev('out.last',undefined,{out})).valueAsString;
  if(result!=='ok')throw Error(result);
}
const config = (enabled, maxBytes=original.maxBytes) => task(`await AndroidStreamCache.configure(directory:${JSON.stringify(root)},enabled:${enabled},maxBytes:${maxBytes})`,'cache_service.dart');
async function stats() {
  const out=(await ev('List<String>.empty(growable:true)')).id;
  await task('outStats.add(jsonEncode(await AndroidStreamCache.stats()))','cache_service.dart',{outStats:out});
  return JSON.parse((await ev('outStats.single',undefined,{outStats:out})).valueAsString);
}
async function close() { if(player){await task('await p.dispose()',undefined,{p:player});player=null;await delay(200);} }
async function cleanupEntries() {
  await task(`for(final suffix in ['','-disabled','-quota','-fault','-delete','-disable']){await AndroidStreamCache.delete('qq','${id}'+suffix,null);}`,'cache_service.dart');
}
function cacheFiles() {
  return new Set(cp.execFileSync(adb,['-s','emulator-5554','shell','run-as','com.cyrene.music','find',root,'-name','*.exo'],{encoding:'utf8'}).trim().split(/\r?\n/).filter(Boolean));
}
async function load({scope='account-a', token='one', header='a', slot=id}={}) {
  await close();
  player=(await ev('ja.AudioPlayer(useProxyForRequestHeaders:false,handleAudioSessionActivation:false,handleInterruptions:false)')).id;
  const meta={source:'qq',songId:slot,quality:'128k',scope};
  const metadata=JSON.stringify(meta).replace(/"([^\"]+)":/g,'"$1":');
  await task(`await p.setVolume(0);await p.setAudioSource(ja.ProgressiveAudioSource(Uri.parse('http://127.0.0.1:${port}/track.wav?token=${token}'),headers:{'X-Test':'${header}'},androidStreamCache:${metadata}));unawaited(p.play());await Future<void>.delayed(Duration(milliseconds:800))`,undefined,{p:player});
}
ws.onopen=async()=>{
  try {
    await new Promise(r=>server.listen(0,'127.0.0.1',r));port=server.address().port;
    cp.execFileSync(adb,['-s','emulator-5554','reverse',`tcp:${port}`,`tcp:${port}`]);
    isolateId=(await rpc('getVM')).isolates.find(i=>i.name==='main').id;
    libraries=(await rpc('getIsolate',{isolateId})).libraries;
    await task('await PlaybackService().stop()','playback_service.dart');
    original=JSON.parse((await ev("jsonEncode({'enabled':CacheService().cacheEnabled,'maxBytes':CacheService().maxCacheSizeBytes,'root':CacheService().currentCacheDir})",'cache_service.dart')).valueAsString);
    root=original.root+'/media3';await config(true);
    const baseline=await stats();
    await load();await close();
    const populated=await stats();check(populated.totalSize>baseline.totalSize,'playback writes native fragments');
    const coldRequests=requests.length;check(coldRequests>0,'cold playback contacts upstream');
    await load();
    check(requests.length===coldRequests,'new player reuses cached bytes without HTTP');
    const before=(await ev('p.position.inMilliseconds.toString()',undefined,{p:player})).valueAsString;
    await delay(400);
    check(+(await ev('p.position.inMilliseconds.toString()',undefined,{p:player})).valueAsString>+before,'cache playback advances');
    await task('await p.seek(Duration(seconds:160));await Future<void>.delayed(Duration(milliseconds:500))',undefined,{p:player});
    check(requests.length>coldRequests && requests.slice(coldRequests).some(r=>r.range),'seek outside cached span fetches HTTP Range');
    await close();
    for(const variant of [{scope:'account-b'},{token:'two'},{header:'b'}]) {
      const n=requests.length;await load(variant);await close();
      check(requests.length>n,'resource/account/header identity isolated: '+Object.keys(variant)[0]);
    }
    await config(false);const disabled=await stats(), n=requests.length;
    await load({slot:id+'-disabled'});await close();
    check(requests.length>n,'disabled cache uses network');
    check((await stats()).totalSize===disabled.totalSize,'disabled cache writes no fragments');
    await config(true);await load();
    await task(`await AndroidStreamCache.delete('qq','${id}',null)`,'cache_service.dart');
    const t0=+(await ev('p.position.inMilliseconds.toString()',undefined,{p:player})).valueAsString;
    await delay(400);
    check(+(await ev('p.position.inMilliseconds.toString()',undefined,{p:player})).valueAsString>t0,'per-song deletion does not interrupt playback');
    await close();
    const removed=await stats();check(removed.totalSize===baseline.totalSize,'closed writers cannot resurrect deleted fragments');
    const count=requests.length;await load();await close();
    check(requests.length>count,'deleted resource returns to network');
    for(const operation of ['delete','disable']) {
      const token='single-'+operation, slot=id+'-'+operation;
      const n=requests.length;
      await load({token,slot});
      const buffered=+(await ev('p.bufferedPosition.inMilliseconds.toString()',undefined,{p:player})).valueAsString;
      const bytes=oneShotConnections.get(token).bytes;
      if(operation==='delete')await task(`await AndroidStreamCache.delete('qq','${slot}',null)`,'cache_service.dart');
      else await config(false);
      await delay(2000);
      check(requests.length===n+1,'expired signed URL is not reopened on '+operation);
      check(!oneShotConnections.get(token).closed && oneShotConnections.get(token).bytes>bytes+131072,
        'original upstream continues delivering after '+operation);
      check(+(await ev('p.bufferedPosition.inMilliseconds.toString()',undefined,{p:player})).valueAsString>buffered,
        'native loading continues beyond existing buffer after '+operation);
      check((await ev('p.processingState.name',undefined,{p:player})).valueAsString==='ready',
        'player stays ready with expired URL after '+operation);
      await close();
      await task(`await AndroidStreamCache.delete('qq','${slot}',null)`,'cache_service.dart');
      await config(true);
    }
    if(baseline.totalSize===0) {
      // Only test destructive global maintenance when no user cache existed.
      await config(true,65536);await load({slot:id+'-quota'});await close();
      check((await stats()).totalSize<=65536,'live quota evicts without reopening the cache');
      await config(true);await load();
      await task('await AndroidStreamCache.clear()','cache_service.dart');
      await close();
      check((await stats()).totalSize===0,'clear during playback leaves no committed fragments');
    }
    // Cache filesystem failure must not cause a URL re-parse or block playback.
    const dirs=cp.execFileSync(adb,['-s','emulator-5554','shell','run-as','com.cyrene.music','find',root,'-type','d'],{encoding:'utf8'}).trim().split(/\r?\n/);
    try {
      for(const directory of dirs)cp.execFileSync(adb,['-s','emulator-5554','shell','run-as','com.cyrene.music','chmod','500',directory]);
      const beforeFault=requests.length;
      await load({slot:id+'-fault'});await close();
      const attempts=requests.length-beforeFault;
      // CacheDataSource opens upstream before its write sink. A failed sink can
      // therefore require one bounded reopen, rather than an independent download.
      check(attempts>=1 && attempts<=2,'cache write failure has at most one network fallback');
      record({cacheWriteFaultRequests:attempts});
    } finally {
      for(const directory of dirs)cp.execFileSync(adb,['-s','emulator-5554','shell','run-as','com.cyrene.music','chmod','700',directory]);
    }
    record({summary:'passed',requests:requests.length,initialCachedBytes:populated.totalSize-baseline.totalSize});
    if(process.env.STREAM_CACHE_CRASH_TEST==='1') {
      await cleanupEntries();
      const before=cacheFiles(), variant={slot:id+'-crash',token:'crash'};
      await load(variant);await close();
      const owned=[...cacheFiles()].filter(file=>!before.has(file));
      check(owned.length>0,'crash fixture has committed cache files');
      await load(variant);
      await task(`await AndroidStreamCache.delete('qq','${id}-crash',null)`,'cache_service.dart');
      check(owned.every(file=>cacheFiles().has(file)),'active deletion retains its current read until close');
      // Kill without Media3 close; the next process must finish the persisted deletion.
      crashed=true;player=null;
      cp.execFileSync(adb,['-s','emulator-5554','shell','am','force-stop','com.cyrene.music']);
      cp.execFileSync(adb,['-s','emulator-5554','shell','monkey','-p','com.cyrene.music','-c','android.intent.category.LAUNCHER','1'],{stdio:'ignore'});
      const deadline=Date.now()+20000;
      while(owned.some(file=>cacheFiles().has(file)) && Date.now()<deadline)await delay(250);
      check(owned.every(file=>!cacheFiles().has(file)),'process restart finishes pending deletion without resurrection');
    }
  } catch(error) {record({error:error.message});process.exitCode=1;}
  finally {
    try {
      if(!crashed) {
        await close();
        await cleanupEntries();
        if(original)await config(original.enabled);
      }
    }catch(error){record({cleanup:error.message});process.exitCode=1;}
    if(port)cp.execFileSync(adb,['-s','emulator-5554','reverse','--remove',`tcp:${port}`]);
    fs.writeFileSync(path.join(__dirname,'../build/android-stream-cache-fixture.json'),JSON.stringify({records,requests},null,2));
    server.closeAllConnections();server.close();ws.close();
  }
};
