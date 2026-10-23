const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const js = fs.readFileSync('lib/services/lx_sandbox_js.dart', 'utf8').match(/r'''([\s\S]*)''';/)[1];
const events = [];
const context = vm.createContext({console: {log() {}, warn() {}, error() {}},
  setTimeout, __lx_native_send__: (name, data) => events.push({name, data})});
vm.runInContext(js, context);
const run = code => vm.runInContext(code, context);
const flush = () => new Promise(setImmediate);
(async () => {
  for (const body of [{code: 200, url: 'audio'}, [1, 2], false, 0, '', null, 'plain text']) {
    run(`lx.request('https://example.invalid/test', {}, (err, resp, body) => {
      globalThis.result = {err: !!err, same: resp.body === body, body};
    });`);
    const request = events.filter(e => e.name === 'lxRequest').at(-1).data;
    run(`__lx_handleHttpResponse__(${JSON.stringify({requestId: request.requestId,
      success: true, response: {statusCode: 200, body: 'incorrect fallback'}, body})});`);
    assert.deepEqual(JSON.parse(run('JSON.stringify(result)')), {err: false, same: true, body});
  }
  // The same JSON object must work for both direct body.code consumers and
  // scripts which conditionally parse text. This is the Anne failure boundary.
  for (const consumer of ['body.code === 200 ? body.url : null',
    `(typeof body === 'string' ? JSON.parse(body) : body).url`]) {
    run(`lx.on(lx.EVENT_NAMES.request, () => new Promise((resolve, reject) => {
      lx.request('https://example.invalid/music', {}, (err, resp, body) => {
        if (err) reject(err); else resolve(${consumer});
      });
    })); __lx_sendRequest__({requestKey:'${consumer.length}', source:'wy', action:'musicUrl', info:{}});`);
    const request = events.filter(e => e.name === 'lxRequest').at(-1).data;
    run(`__lx_handleHttpResponse__(${JSON.stringify({requestId: request.requestId,
      success: true, response: {statusCode: 200, body: {code: 200, url: 'audio'}}})});`);
    await flush();
    assert.equal(events.filter(e => e.name === 'lxOnResponse').at(-1).data.url, 'audio');
  }
  run(`lx.request('https://example.invalid/error', {}, (err, resp, body) => {
    globalThis.errorResult = [err.message, resp, body];
  });`);
  const request = events.filter(e => e.name === 'lxRequest').at(-1).data;
  run(`__lx_handleHttpResponse__(${JSON.stringify({requestId: request.requestId,
    success: false, error: 'transport failed'})});`);
  assert.deepEqual(JSON.parse(run('JSON.stringify(errorResult)')), ['transport failed', null, null]);
  console.log('HTTP contract checks passed');
})().catch(error => {console.error(error); process.exitCode = 1;});
