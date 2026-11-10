// Production sandbox contract: async state belongs to the context, never to
// guessed Promise owners. Whole-context cancellation is tested in native tests.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('lib/services/lx_sandbox_js.dart', 'utf8');
const js = source.match(/r'''([\s\S]*)''';/)[1];
const events = [];
const context = vm.createContext({console:{log(){},warn(){},error(){}},
  __lx_native_send__: (name,data) => events.push({name,data})});
const run = code => vm.runInContext(code,context);
const originalThen = run('Promise.prototype.then');
vm.runInContext(js, context);
assert.equal(run('Promise.prototype.then'), originalThen);
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  run(`let cached = false;
    lx.on(lx.EVENT_NAMES.request, async () => {
      await Promise.resolve();
      if (cached) return 'https://example.com/cached';
      const response = await lx.request('https://example.com/token', {});
      cached = true;
      setTimeout(() => cached = false, 100);
      return response.body;
    });
    __lx_sendRequest__({requestKey:'A',source:'tx',action:'musicUrl',info:{}});`);
  await flush();
  const http = events.find(e => e.name === 'lxRequest').data;
  assert.equal('ownerKey' in http, false);
  run(`__lx_handleHttpResponse__(${JSON.stringify({requestId:http.requestId,success:true,body:'https://example.com/a'})});`);
  await flush();
  assert(events.some(e => e.name==='lxOnResponse' && e.data.url==='https://example.com/a'));
  run(`__lx_sendRequest__({requestKey:'B',source:'tx',action:'musicUrl',info:{}});`);
  await flush();
  assert(events.some(e => e.name==='lxOnResponse' && e.data.url==='https://example.com/cached'));
  const timer = events.find(e=>e.name==='lxSetTimeout').data.timerId;
  run(`__lx_fireTimer__(${timer});`);
  assert.equal(run('cached'),false);
  run(`let ticks = 0; const interval = setInterval(() => ticks++, 10);`);
  const interval = run('interval');
  run(`__lx_fireTimer__(${interval}); __lx_fireTimer__(${interval}); clearInterval(${interval}); __lx_fireTimer__(${interval});`);
  assert.equal(run('ticks'),2);
  console.log('Context lifecycle checks passed.');
})().catch(error => {console.error(error);process.exitCode=1;});
