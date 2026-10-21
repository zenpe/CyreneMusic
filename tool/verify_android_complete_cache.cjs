// Run against a debug VM websocket. Only the unique QA identity is deleted.
const http = require('node:http');
const cp = require('node:child_process');

const endpoint = process.argv[2];
if (!/^wss?:\/\//.test(endpoint || '')) throw Error('VM websocket required');
const adb = process.env.ADB || 'F:/DevTools/Android/Sdk/platform-tools/adb.exe';
const device = process.env.ANDROID_SERIAL || 'emulator-5554';
const runAdb = args => cp.execFileSync(adb, ['-s', device, ...args], {encoding:'utf8'});
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const requests = [];
const jobs = new Map();
let sequence = 0;
let isolateId, libraries, player, port, identity, cacheRoot, settings;
const songId = 'complete-cache-qa-' + Date.now();
const wav = Buffer.alloc(44 + 22050 * 2 * 8);
wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16,16); wav.writeUInt16LE(1,20); wav.writeUInt16LE(1,22);
wav.writeUInt32LE(22050,24); wav.writeUInt32LE(44100,28); wav.writeUInt16LE(2,32);
wav.writeUInt16LE(16,34); wav.write('data',36); wav.writeUInt32LE(wav.length-44,40);
for (let offset=44; offset<wav.length; offset+=2) wav.writeInt16LE(Math.sin(offset/100)*12000, offset);
const server = http.createServer((req,res) => {
  requests.push(req.url);
  if (req.url.includes('deny')) {res.writeHead(403);res.end();return;}
  const match = /^bytes=(\d+)-(\d*)$/.exec(req.headers.range || '');
  const start = match ? +match[1] : 0;
  const end = match?.[2] ? Math.min(+match[2], wav.length-1) : wav.length-1;
  if (start >= wav.length) {res.writeHead(416);res.end();return;}
  const headers = {'Content-Type':'audio/wav','Content-Length':end-start+1,
    'ETag':'"stable-qa"','Accept-Ranges':'bytes'};
  if (match) headers['Content-Range'] = `bytes ${start}-${end}/${wav.length}`;
  res.writeHead(match?206:200,headers);res.end(wav.subarray(start,end+1));
});

const ws = new WebSocket(endpoint);
function rpc(method, params={}) {
  return new Promise((resolve,reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { jobs.delete(id);reject(Error(method+' timed out')); },20000);
    jobs.set(id,{resolve,reject,timer});
    ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));
  });
}
ws.onmessage = event => {
  const reply=JSON.parse(event.data), job=jobs.get(reply.id);
  if (!job) return;
  jobs.delete(reply.id);clearTimeout(job.timer);
  reply.error?job.reject(Error(reply.error.message+' '+JSON.stringify(reply.error.data || {}))):job.resolve(reply.result);
};
async function evaluate(expression, suffix='cache_service.dart', scope={}) {
  const library=libraries.find(item=>item.uri.endsWith('/'+suffix));
  if (!library) throw Error('Library unavailable: '+suffix);
  const value=await rpc('evaluate',{isolateId,targetId:library.id,expression,scope});
  if (value.type.includes('Error')) throw Error(value.message);
  return value;
}
async function task(expression,suffix='cache_service.dart',scope={}) {
  const output=(await evaluate('List<String>.empty(growable:true)')).id;
  await evaluate(`Future<void>(() async {try {${expression};out.add('ok');} catch(e) {out.add('error:'+e.toString());}})`,suffix,{...scope,out:output});
  const until=Date.now()+20000;
  while((await evaluate('out.isEmpty.toString()',undefined,{out:output})).valueAsString==='true') {
    if(Date.now()>until)throw Error('Task timed out'); await delay(100);
  }
  const result=(await evaluate('out.last',undefined,{out:output})).valueAsString;
  if(result!=='ok')throw Error(result);
}
async function readJson(expression,suffix='cache_service.dart',scope={}) {
  return JSON.parse(await fullString(await evaluate(expression,suffix,scope)));
}
async function fullString(ref) {
  if (!ref.id) return ref.valueAsString;
  return (await rpc('getObject',{isolateId,objectId:ref.id,offset:0,count:100000})).valueAsString;
}
function check(ok,name) {if(!ok) throw Error(name); console.log('PASS '+name);}
async function lookup() {
  const output=(await evaluate('List<String>.empty(growable:true)')).id;
  await task('results.add(jsonEncode(await AndroidStreamCache.lookup(cacheId)))','cache_service.dart',{results:output,cacheId:identity});
  const raw=await fullString(await evaluate('results.single',undefined,{results:output}));
  if (!raw || raw === 'null') return null;
  return JSON.parse(raw);
}
async function closePlayer() {
  if (!player) return;
  await task('await p.dispose()','audio_engine.dart',{p:player});player=null;
}
async function play(url, cacheMeta) {
  player=(await evaluate('ja.AudioPlayer(useProxyForRequestHeaders:false,handleAudioSessionActivation:false,handleInterruptions:false)','audio_engine.dart')).id;
  const expr=cacheMeta === true
    ? `await p.setAudioSource(ja.ProgressiveAudioSource(Uri.parse(${JSON.stringify(url)}),androidStreamCache:cacheId));unawaited(p.play());`
    : `await p.setAudioSource(ja.AudioSource.file(${JSON.stringify(url)}));unawaited(p.play());`;
  await task(expr,'audio_engine.dart',{p:player,...(cacheMeta === true ? {cacheId:identity} : {})});
  await delay(1200);
  check((await evaluate('p.processingState.name','audio_engine.dart',{p:player})).valueAsString==='ready','native player ready');
}
ws.onopen=async()=>{
  try {
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
    port=server.address().port;runAdb(['reverse',`tcp:${port}`,`tcp:${port}`]);
    isolateId=(await rpc('getVM')).isolates.find(item=>item.name==='main').id;
    libraries=(await rpc('getIsolate',{isolateId})).libraries;
    settings=await readJson("jsonEncode({'enabled':CacheService().cacheEnabled,'maxBytes':CacheService().maxCacheSizeBytes,'root':CacheService().currentCacheDir})");
    cacheRoot=settings.root+'/media3';
    const track=`Track(id:${JSON.stringify(songId)},name:'QA',artists:'QA',album:'',picUrl:'',source:MusicSource.qq)`;
    identity=(await evaluate(`audioCacheIdentityFor(${track},CacheService.normalizeQualityValue('128k'))`)).id;
    await task(`await AndroidStreamCache.configure(directory:${JSON.stringify(cacheRoot)},enabled:true,maxBytes:${Math.max(settings.maxBytes,16*1024*1024)})`);
    const initial=await lookup();check(initial===null,'fresh QA identity misses');
    await play(`http://127.0.0.1:${port}/track.wav?one`, true);
    await closePlayer();
    let committed=null;
    const until=Date.now()+10000;
    while(Date.now()<until && !committed) {committed=await lookup();if(!committed) await delay(150);}
    check(!!committed,'full resource promoted after playback');
    check(committed.fileSize===wav.length,'complete file has expected size');
    const cacheResult=(await evaluate('List<String>.empty(growable:true)')).id;
    await task(`results.add(jsonEncode((await CacheService().getCachedAudioFileInfo(${track},quality:'128k'))?.filePath))`,
      'cache_service.dart',{results:cacheResult});
    const cacheHit=JSON.parse(await fullString(await evaluate('results.single',undefined,{results:cacheResult})));
    check(cacheHit===committed.path,'playback lookup selects the complete file');
    const before=requests.length;
    await play(committed.path, false);
    await closePlayer();
    check(requests.length===before,'replay needs no URL request');
    await task(`await AndroidStreamCache.delete('qq',${JSON.stringify(songId)},null)`);
    check(await lookup()===null,'delete hides completed audio');
    console.log(JSON.stringify({summary:'passed',fileSize:committed.fileSize,requests:requests.length}));
  } catch(error) {console.error(error);process.exitCode=1;}
  finally {
    try {
      await closePlayer();
      if(identity)await task(`await AndroidStreamCache.delete('qq',${JSON.stringify(songId)},null)`);
      if(settings)await task(`await AndroidStreamCache.configure(directory:${JSON.stringify(cacheRoot)},enabled:${settings.enabled},maxBytes:${settings.maxBytes})`);
    } catch(error) {console.error('cleanup: '+error);process.exitCode=1;}
    try {if(port)runAdb(['reverse','--remove',`tcp:${port}`]);}catch(_error){}
    server.closeAllConnections();server.close();ws.close();
  }
};
