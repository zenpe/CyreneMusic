// Release-mode emulator smoke checks. Preserves application data and rotation.
const fs = require('node:fs'), cp = require('node:child_process');
const adb = process.env.ADB || 'adb', results = [];
const run = (...args) => cp.execFileSync(adb, ['-s','emulator-5554',...args], {encoding:'utf8',timeout:30000});
const pause = ms => new Promise(resolve => setTimeout(resolve,ms));
function record(value){results.push(value);console.log(JSON.stringify(value));}
function tree(){run('shell','uiautomator','dump','/sdcard/qa-release.xml');return run('shell','cat','/sdcard/qa-release.xml');}
function tap(label){
  const nodes=[...tree().matchAll(/<node\b[^>]*>/g)].map(m=>Object.fromEntries([...m[0].matchAll(/([\w-]+)="([^"]*)"/g)].map(x=>[x[1],x[2]])));
  const node=nodes.filter(n=>n.text===label||n['content-desc']===label).at(-1);
  if(!node)throw Error('Missing navigation: '+label);
  const b=node.bounds.match(/\d+/g).map(Number);run('shell','input','tap',String(Math.round((b[0]+b[2])/2)),String(Math.round((b[1]+b[3])/2)));
}
function memory(label){
  const raw=run('shell','dumpsys','meminfo','com.cyrene.music');
  fs.writeFileSync('build/qa-release-memory-'+label+'.txt',raw);
  record({kind:'memory',label,pss_kib:Number(/TOTAL PSS:\s+(\d+)/.exec(raw)?.[1]),rss_kib:Number(/TOTAL RSS:\s+(\d+)/.exec(raw)?.[1])});
}
(async()=>{
  const rotation=run('shell','settings','get','system','user_rotation').trim(),auto=run('shell','settings','get','system','accelerometer_rotation').trim();
  try{
    run('shell','settings','put','system','accelerometer_rotation','0');run('shell','settings','put','system','user_rotation','0');
    for(let i=0;i<3;i++){
      run('shell','am','force-stop','com.cyrene.music');
      const start=Date.now(),raw=run('shell','am','start','-W','-n','com.cyrene.music/.MainActivity');
      let visible=false;while(Date.now()-start<25000){if(tree().includes('首页')){visible=true;break;}await pause(500);}
      record({kind:'cold_start',iteration:i+1,activity_ms:Number(/TotalTime:\s*(\d+)/.exec(raw)?.[1]),home_observed_within_ms:Date.now()-start,home_visible:visible});await pause(1500);
    }
    memory('initial');run('shell','dumpsys','gfxinfo','com.cyrene.music','reset');
    for(let round=0;round<3;round++){
      for(const label of ['首页','发现','我的','设置']){tap(label);await pause(600);record({kind:'navigation',round:round+1,page:label,alive:!!run('shell','pidof','com.cyrene.music').trim()});}
      run('shell','settings','put','system','user_rotation','1');await pause(900);
      record({kind:'rotation',round:round+1,ui_visible:tree().includes('设置')});
      run('shell','settings','put','system','user_rotation','0');await pause(700);
    }
    memory('after_navigation');run('shell','input','keyevent','3');await pause(5000);
    run('shell','am','start','-n','com.cyrene.music/.MainActivity');await pause(1500);tap('首页');await pause(4000);memory('idle');
    const cpu=run('shell','dumpsys','cpuinfo');fs.writeFileSync('build/qa-release-cpu.txt',cpu);
    record({kind:'cpu_sample',app:cpu.split('\n').find(l=>l.includes('com.cyrene.music'))?.trim()||'below_report_threshold'});
    fs.writeFileSync('build/qa-release-gfxinfo.txt',run('shell','dumpsys','gfxinfo','com.cyrene.music','framestats'));
    fs.writeFileSync('build/qa-release-exit-info.txt',run('shell','dumpsys','activity','exit-info','com.cyrene.music'));
    const anr=run('shell','dumpsys','activity','lastanr');fs.writeFileSync('build/qa-release-lastanr.txt',anr);record({kind:'anr',no_record:anr.includes('no ANR has occurred')});
  }catch(e){record({kind:'test_error',message:e.message});process.exitCode=1;}
  finally{run('shell','settings','put','system','user_rotation',rotation);run('shell','settings','put','system','accelerometer_rotation',auto);fs.writeFileSync('build/qa-release-smoke.json',JSON.stringify(results,null,2));}
})();
