// Executes the production sandbox with real promises and timers, no source API.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync('lib/services/lx_sandbox_js.dart', 'utf8');
const js = source.match(/r'''([\s\S]*)''';/)[1];
const events = [];
const context = vm.createContext({ console: { log() {}, warn() {}, error() {} },
  setTimeout, __lx_native_send__: (name, data) => events.push({name, data}) });
vm.runInContext(js, context);
const run = code => vm.runInContext(code, context);
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  run(`lx.on(lx.EVENT_NAMES.request, () => new Promise((resolve, reject) => {
    lx.request('https://example.com/a', {}, (err) => {
      if (err) reject(err); else resolve('audio');
    });
  })); __lx_sendRequest__({requestKey:'A', source:'tx', action:'musicUrl', info:{}});`);
  const httpA = events.find(e => e.name === 'lxRequest').data;
  assert.equal(httpA.ownerKey, 'A');
  run(`__lx_cancelRequest__('A');`);
  await flush();
  assert(events.some(e => e.name === 'lxOnResponse' && e.data.requestKey === 'A' && !e.data.success));
  const count = events.length;
  run(`__lx_handleHttpResponse__(${JSON.stringify({requestId: httpA.requestId, success:true, body:'late'})});`);
  await flush();
  assert.equal(events.length, count);
  run(`__lx_sendRequest__({requestKey:'B', source:'tx', action:'musicUrl', info:{}});`);
  const httpB = events.filter(e => e.name === 'lxRequest').at(-1).data;
  assert.equal(httpB.ownerKey, 'B');
  run(`__lx_handleHttpResponse__(${JSON.stringify({requestId:httpB.requestId, success:true, body:'ok'})});`);
  await flush();
  assert(events.some(e => e.name === 'lxOnResponse' && e.data.requestKey === 'B' && e.data.url === 'audio'));
  run(`lx.on(lx.EVENT_NAMES.request, () => new Promise(resolve => {
    setTimeout(() => { lx.request('https://example.com/late', {}); resolve('bad'); }, 10);
  })); __lx_sendRequest__({requestKey:'C', source:'tx', action:'musicUrl', info:{}});
  __lx_cancelRequest__('C');`);
  await new Promise(resolve => setTimeout(resolve, 25));
  assert(!events.some(e => e.name === 'lxRequest' && e.data.url.endsWith('/late')));
  console.log('Sandbox lifecycle checks passed: cancellation, settlement, ownership, late callbacks, timers.');
})().catch(error => { console.error(error); process.exitCode = 1; });
