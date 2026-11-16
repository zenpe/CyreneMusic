const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const script = fs.readFileSync(path.join(__dirname, '../audio_sources/qingliu.js'), 'utf8');

function setup(respond) {
  let resolve;
  const calls = [];
  const context = vm.createContext({
    setTimeout, clearTimeout,
    __QINGLIU_CONFIG__: { allowSameSongFallback: false, extraProviders: [], disabledProviders: ['qq-dedicated'] },
    lx: {
      EVENT_NAMES: { request: 'request', inited: 'inited' },
      on: (_, handler) => { resolve = handler; },
      send: () => {},
      request: (url, opts, callback) => {
        calls.push({ url, opts });
        let cancelled = false;
        queueMicrotask(() => {
          if (cancelled) return;
          try { callback(null, respond(url, opts), undefined); }
          catch (error) { callback(error); }
        });
        return () => { cancelled = true; };
      },
    },
  });
  vm.runInContext(script, context);
  return {
    calls,
    resolve: () => resolve({ action: 'musicUrl', source: 'tx', info: {
      musicInfo: { songmid: 'test-mid', name: 'test', interval: 212 }, type: '128k',
    } }),
  };
}

const media = (total = 4000000) => ({ statusCode: 206, headers: {
  'content-type': 'audio/mpeg', 'content-length': '4096', 'content-range': `bytes 0-4095/${total}`,
}, body: [255, 251, 144, 0, 0, 0, 0, 0, 0, 0, 0, 0] });
const api = (url) => ({ statusCode: 200, body: { url } });

test('uses bounded GET and never adds QQ headers to GitCode audio', async () => {
  const run = setup((url) => url.includes('wwwweb') ? api('https://cdn-img.gitcode.com/audio') : media());
  assert.equal(await run.resolve(), 'https://cdn-img.gitcode.com/audio');
  const request = run.calls.find(c => c.url.includes('gitcode'));
  assert.equal(request.opts.method, 'GET');
  assert.equal(request.opts.headers.Range, 'bytes=0-4095');
  assert.equal(request.opts.headers.Referer, undefined);
  assert.equal(request.opts.maxResponseBytes, 65536);
  assert.equal(request.opts.encoding, null);
  assert.ok(!run.calls.some(c => c.opts.method === 'HEAD'));
});

test('HEAD-like metadata cannot hide a failing GET', async () => {
  const run = setup(url => url.includes('wwwweb') ? api('https://cdn-img.gitcode.com/bad') :
    { statusCode: 403, headers: { 'content-type': 'audio/mpeg' }, body: [] });
  await assert.rejects(run.resolve());
});

test('even a fresh cached URL is checked and replaced after GET failure', async () => {
  let apis = 0, bad = false;
  const run = setup(url => {
    if (url.includes('wwwweb')) return api(`https://cdn-img.gitcode.com/${++apis}`);
    if (bad && url.endsWith('/1')) return { statusCode: 403 };
    return media();
  });
  assert.equal(await run.resolve(), 'https://cdn-img.gitcode.com/1');
  bad = true;
  assert.equal(await run.resolve(), 'https://cdn-img.gitcode.com/2');
  assert.equal(apis, 2);
  assert.equal(run.calls.filter(c => c.url.endsWith('/1')).length, 2);
});

test('official audio headers follow the resolved host', async () => {
  const run = setup(url => url.includes('wwwweb') ? api('https://dl.stream.qqmusic.qq.com/audio') : media());
  await run.resolve();
  const headers = run.calls.at(-1).opts.headers;
  assert.equal(headers.Referer, 'https://y.qq.com/');
});

for (const [name, response] of [
  ['HTML despite audio MIME', { ...media(), body: Array.from(Buffer.from('<html>not audio</html>')) }],
  ['short resource', media(100000)],
  ['invalid partial range', { ...media(), headers: { 'content-range': 'bytes 10-4095/4000000' } }],
]) {
  test(`rejects ${name}`, async () => {
    const run = setup(url => url.includes('wwwweb') ? api('https://cdn-img.gitcode.com/audio') : response);
    await assert.rejects(run.resolve());
  });
}
