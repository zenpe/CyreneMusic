const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const js = fs.readFileSync('lib/services/lx_sandbox_js.dart', 'utf8').match(/r'''([\s\S]*)''';/)[1];
const context = vm.createContext({console: {log() {}, warn() {}, error() {}}, setTimeout, __lx_native_send__() {}});
vm.runInContext(js, context);
const run = code => vm.runInContext(code, context);
(async () => {
  for (const value of ['hello', '中文音乐🎵', '', '\ud800', 'a\udc00b']) {
    assert.equal(run(`lx.utils.crypto.md5(${JSON.stringify(value)})`), crypto.createHash('md5').update(value).digest('hex'));
  }
  const bytes = [0, 255, 128, 195, 40];
  assert.equal(run(`lx.utils.crypto.md5(new Uint8Array(${JSON.stringify(bytes)}))`), crypto.createHash('md5').update(Buffer.from(bytes)).digest('hex'));
  for (const bytes of [[0xff], [0xe0,0x80,0x80], [0xed,0xa0,0x80], [0xf4,0x90,0x80,0x80], [0xe4,0xb8], [0xe4,65], [239,187,191,65], [240,159,142,181]]) {
    assert.equal(run(`new TextDecoder().decode(new Uint8Array(${JSON.stringify(bytes)}))`), new TextDecoder().decode(Uint8Array.from(bytes)));
  }
  const original = '\ufeff// 中文音乐🎵\nconst 名称 = "音乐";';
  run(`__lx_setScriptInfo__({scriptBase64: '${Buffer.from(original).toString('base64')}'})`);
  assert.equal(run('lx.currentScriptInfo.rawScript'), original);
  assert.throws(() => run('lx.utils.crypto.aesEncrypt(new Uint8Array())'), /aesEncrypt/);
  assert.throws(() => run('lx.utils.crypto.rsaEncrypt(new Uint8Array())'), /rsaEncrypt/);
  await assert.rejects(run('lx.utils.zlib.inflate(new Uint8Array())'), /inflate/);
  await assert.rejects(run('lx.utils.zlib.deflate(new Uint8Array())'), /deflate/);
  console.log('encoding contracts passed');
})().catch(e => { console.error(e); process.exitCode = 1; });
