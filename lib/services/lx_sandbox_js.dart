const String lxSandboxJs = r'''
(function() {
  'use strict';

  var _global = (typeof globalThis !== 'undefined')
    ? globalThis
    : (typeof window !== 'undefined' ? window : {});
  var window = _global;

  if (typeof _global.atob === 'undefined') {
    _global.atob = function(input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var str = String(input).replace(/=+$/, '');
      var output = '';
      if (str.length % 4 === 1) {
        throw new Error('Invalid base64 string');
      }
      for (var bc = 0, bs = 0, buffer, idx = 0;
        (buffer = str.charAt(idx++));
        ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer,
          bc++ % 4) ? output += String.fromCharCode(255 & (bs >> ((-2 * bc) & 6))) : 0) {
        buffer = chars.indexOf(buffer);
      }
      return output;
    };
  }

  if (typeof _global.btoa === 'undefined') {
    _global.btoa = function(input) {
      var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
      var str = String(input);
      var output = '';
      for (var block, charCode, idx = 0, map = chars;
        str.charAt(idx | 0) || (map = '=', idx % 1);
        output += map.charAt(63 & block >> 8 - idx % 1 * 8)) {
        charCode = str.charCodeAt(idx += 3 / 4);
        if (charCode > 0xFF) {
          throw new Error('Invalid character');
        }
        block = block << 8 | charCode;
      }
      return output;
    };
  }

  if (typeof _global.TextEncoder === 'undefined') {
    _global.TextEncoder = function() {};
    _global.TextEncoder.prototype.encode = function(str) {
      var utf8 = unescape(encodeURIComponent(str));
      var result = new Uint8Array(utf8.length);
      for (var i = 0; i < utf8.length; i++) {
        result[i] = utf8.charCodeAt(i);
      }
      return result;
    };
  }

  if (typeof _global.TextDecoder === 'undefined') {
    _global.TextDecoder = function() {};
    _global.TextDecoder.prototype.decode = function(buf) {
      var bytes = buf;
      if (bytes instanceof ArrayBuffer) {
        bytes = new Uint8Array(bytes);
      }
      var str = '';
      for (var i = 0; i < bytes.length; i++) {
        str += String.fromCharCode(bytes[i]);
      }
      return decodeURIComponent(escape(str));
    };
  }

  if (typeof _global.crypto === 'undefined') {
    _global.crypto = {};
  }
  if (typeof _global.crypto.getRandomValues !== 'function') {
    _global.crypto.getRandomValues = function(arr) {
      for (var i = 0; i < arr.length; i++) {
        arr[i] = Math.floor(Math.random() * 256);
      }
      return arr;
    };
  }

  if (typeof console !== 'undefined') {
    if (typeof console.group !== 'function') {
      console.group = console.log;
    }
    if (typeof console.groupEnd !== 'function') {
      console.groupEnd = function() {};
    }
    if (typeof console.info !== 'function') {
      console.info = console.log;
    }
    if (typeof console.debug !== 'function') {
      console.debug = console.log;
    }
    var LX_DEBUG = false;
    var _lxOrigLog = console.log;
    if (typeof _lxOrigLog === 'function') {
      console.log = function() {
        if (!LX_DEBUG && arguments.length > 0 &&
            typeof arguments[0] === 'string' &&
            arguments[0].indexOf('[LxMusic]') === 0) {
          return;
        }
        return _lxOrigLog.apply(console, arguments);
      };
    }
    var _lxOrigWarn = console.warn;
    if (typeof _lxOrigWarn === 'function') {
      console.warn = function() {
        if (!LX_DEBUG && arguments.length > 0 &&
            typeof arguments[0] === 'string' &&
            arguments[0].indexOf('[LxMusic]') === 0) {
          return;
        }
        return _lxOrigWarn.apply(console, arguments);
      };
    }
  }
  
  // ==================== 状态 ====================
  let isInited = false;
  let requestHandler = null;
  let currentScriptInfo = null;
  const pendingHttpRequests = new Map();
  let httpRequestCounter = 0;
  
  // ==================== 工具函数 ====================
  
  // 发送消息到 Flutter
  function sendToFlutter(handlerName, data) {
    if (typeof _global.__lx_native_send__ === 'function') {
      _global.__lx_native_send__(handlerName, data);
      return;
    }
    if (window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler(handlerName, data);
    }
  }
  
  // ==================== lx API 实现 ====================
  
  const EVENT_NAMES = {
    request: 'request',
    inited: 'inited',
    updateAlert: 'updateAlert',
  };
  
  // HTTP 请求实现 - 支持回调和 Promise 两种形式
  function request(url, options, callback) {
    const requestId = 'http_' + (++httpRequestCounter) + '_' + Date.now();

    console.log('[LxMusic] request called, url: ' + url);
    console.log('[LxMusic] request options type: ' + typeof options + ', callback type: ' + typeof callback);

    // 如果 options 是函数，说明是 request(url, callback) 形式
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }

    // 如果没有回调，返回 Promise
    if (typeof callback !== 'function') {
      return new Promise(function(resolve, reject) {
        pendingHttpRequests.set(requestId, function(err, resp, body) {
          if (err) {
            reject(err);
          } else {
            resolve({ resp: resp, body: body });
          }
        });

        sendToFlutter('lxRequest', {
          requestId: requestId,
          url: url,
          options: options || {},
        });
      });
    }

    pendingHttpRequests.set(requestId, callback);

    sendToFlutter('lxRequest', {
      requestId: requestId,
      url: url,
      options: options || {},
    });

    // 返回取消函数
    return function() {
      pendingHttpRequests.delete(requestId);
    };
  }
  
  // 发送事件
  function send(eventName, data) {
    return new Promise((resolve, reject) => {
      if (eventName === EVENT_NAMES.inited) {
        if (isInited) {
          reject(new Error('Already inited'));
          return;
        }
        isInited = true;
        sendToFlutter('lxOnInited', data);
        resolve();
      } else if (eventName === EVENT_NAMES.updateAlert) {
        // 更新提醒，暂时忽略
        resolve();
      } else {
        reject(new Error('Unknown event: ' + eventName));
      }
    });
  }
  
  // 注册事件处理器
  function on(eventName, handler) {
    console.log('[LxMusic] lx.on called, eventName: ' + eventName + ', handler type: ' + typeof handler);
    if (eventName === EVENT_NAMES.request) {
      requestHandler = handler;
      // 返回取消订阅函数
      return function() {
        requestHandler = null;
      };
    }
    console.warn('[LxMusic] Unknown event: ' + eventName);
    return function() {};
  }
  
  // ==================== MD5 实现 ====================
  // 完整的 MD5 实现，用于音源脚本签名验证
  const md5 = (function() {
    function md5cycle(x, k) {
      let a = x[0], b = x[1], c = x[2], d = x[3];
      a = ff(a, b, c, d, k[0], 7, -680876936);
      d = ff(d, a, b, c, k[1], 12, -389564586);
      c = ff(c, d, a, b, k[2], 17, 606105819);
      b = ff(b, c, d, a, k[3], 22, -1044525330);
      a = ff(a, b, c, d, k[4], 7, -176418897);
      d = ff(d, a, b, c, k[5], 12, 1200080426);
      c = ff(c, d, a, b, k[6], 17, -1473231341);
      b = ff(b, c, d, a, k[7], 22, -45705983);
      a = ff(a, b, c, d, k[8], 7, 1770035416);
      d = ff(d, a, b, c, k[9], 12, -1958414417);
      c = ff(c, d, a, b, k[10], 17, -42063);
      b = ff(b, c, d, a, k[11], 22, -1990404162);
      a = ff(a, b, c, d, k[12], 7, 1804603682);
      d = ff(d, a, b, c, k[13], 12, -40341101);
      c = ff(c, d, a, b, k[14], 17, -1502002290);
      b = ff(b, c, d, a, k[15], 22, 1236535329);
      a = gg(a, b, c, d, k[1], 5, -165796510);
      d = gg(d, a, b, c, k[6], 9, -1069501632);
      c = gg(c, d, a, b, k[11], 14, 643717713);
      b = gg(b, c, d, a, k[0], 20, -373897302);
      a = gg(a, b, c, d, k[5], 5, -701558691);
      d = gg(d, a, b, c, k[10], 9, 38016083);
      c = gg(c, d, a, b, k[15], 14, -660478335);
      b = gg(b, c, d, a, k[4], 20, -405537848);
      a = gg(a, b, c, d, k[9], 5, 568446438);
      d = gg(d, a, b, c, k[14], 9, -1019803690);
      c = gg(c, d, a, b, k[3], 14, -187363961);
      b = gg(b, c, d, a, k[8], 20, 1163531501);
      a = gg(a, b, c, d, k[13], 5, -1444681467);
      d = gg(d, a, b, c, k[2], 9, -51403784);
      c = gg(c, d, a, b, k[7], 14, 1735328473);
      b = gg(b, c, d, a, k[12], 20, -1926607734);
      a = hh(a, b, c, d, k[5], 4, -378558);
      d = hh(d, a, b, c, k[8], 11, -2022574463);
      c = hh(c, d, a, b, k[11], 16, 1839030562);
      b = hh(b, c, d, a, k[14], 23, -35309556);
      a = hh(a, b, c, d, k[1], 4, -1530992060);
      d = hh(d, a, b, c, k[4], 11, 1272893353);
      c = hh(c, d, a, b, k[7], 16, -155497632);
      b = hh(b, c, d, a, k[10], 23, -1094730640);
      a = hh(a, b, c, d, k[13], 4, 681279174);
      d = hh(d, a, b, c, k[0], 11, -358537222);
      c = hh(c, d, a, b, k[3], 16, -722521979);
      b = hh(b, c, d, a, k[6], 23, 76029189);
      a = hh(a, b, c, d, k[9], 4, -640364487);
      d = hh(d, a, b, c, k[12], 11, -421815835);
      c = hh(c, d, a, b, k[15], 16, 530742520);
      b = hh(b, c, d, a, k[2], 23, -995338651);
      a = ii(a, b, c, d, k[0], 6, -198630844);
      d = ii(d, a, b, c, k[7], 10, 1126891415);
      c = ii(c, d, a, b, k[14], 15, -1416354905);
      b = ii(b, c, d, a, k[5], 21, -57434055);
      a = ii(a, b, c, d, k[12], 6, 1700485571);
      d = ii(d, a, b, c, k[3], 10, -1894986606);
      c = ii(c, d, a, b, k[10], 15, -1051523);
      b = ii(b, c, d, a, k[1], 21, -2054922799);
      a = ii(a, b, c, d, k[8], 6, 1873313359);
      d = ii(d, a, b, c, k[15], 10, -30611744);
      c = ii(c, d, a, b, k[6], 15, -1560198380);
      b = ii(b, c, d, a, k[13], 21, 1309151649);
      a = ii(a, b, c, d, k[4], 6, -145523070);
      d = ii(d, a, b, c, k[11], 10, -1120210379);
      c = ii(c, d, a, b, k[2], 15, 718787259);
      b = ii(b, c, d, a, k[9], 21, -343485551);
      x[0] = add32(a, x[0]);
      x[1] = add32(b, x[1]);
      x[2] = add32(c, x[2]);
      x[3] = add32(d, x[3]);
    }
    function cmn(q, a, b, x, s, t) {
      a = add32(add32(a, q), add32(x, t));
      return add32((a << s) | (a >>> (32 - s)), b);
    }
    function ff(a, b, c, d, x, s, t) {
      return cmn((b & c) | ((~b) & d), a, b, x, s, t);
    }
    function gg(a, b, c, d, x, s, t) {
      return cmn((b & d) | (c & (~d)), a, b, x, s, t);
    }
    function hh(a, b, c, d, x, s, t) {
      return cmn(b ^ c ^ d, a, b, x, s, t);
    }
    function ii(a, b, c, d, x, s, t) {
      return cmn(c ^ (b | (~d)), a, b, x, s, t);
    }
    function md51(s) {
      const n = s.length;
      let state = [1732584193, -271733879, -1732584194, 271733878], i;
      for (i = 64; i <= s.length; i += 64) {
        md5cycle(state, md5blk(s.substring(i - 64, i)));
      }
      s = s.substring(i - 64);
      const tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      for (i = 0; i < s.length; i++)
        tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
      tail[i >> 2] |= 0x80 << ((i % 4) << 3);
      if (i > 55) {
        md5cycle(state, tail);
        for (i = 0; i < 16; i++) tail[i] = 0;
      }
      tail[14] = n * 8;
      md5cycle(state, tail);
      return state;
    }
    function md5blk(s) {
      const md5blks = [];
      for (let i = 0; i < 64; i += 4) {
        md5blks[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24);
      }
      return md5blks;
    }
    const hex_chr = '0123456789abcdef'.split('');
    function rhex(n) {
      let s = '', j = 0;
      for (; j < 4; j++)
        s += hex_chr[(n >> (j * 8 + 4)) & 0x0F] + hex_chr[(n >> (j * 8)) & 0x0F];
      return s;
    }
    function hex(x) {
      for (let i = 0; i < x.length; i++) x[i] = rhex(x[i]);
      return x.join('');
    }
    function add32(a, b) {
      return (a + b) & 0xFFFFFFFF;
    }
    return function(s) {
      return hex(md51(s));
    };
  })();
  
  // 工具函数
  const utils = {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) {
        console.warn('[LxMusic] crypto.aesEncrypt not implemented');
        return buffer;
      },
      rsaEncrypt: function(buffer, key) {
        console.warn('[LxMusic] crypto.rsaEncrypt not implemented');
        return buffer;
      },
      randomBytes: function(size) {
        const bytes = new Uint8Array(size);
        crypto.getRandomValues(bytes);
        return bytes;
      },
      md5: function(str) {
        // 使用完整的 MD5 实现
        if (typeof str !== 'string') {
          str = new TextDecoder().decode(str);
        }
        return md5(str);
      },
    },
    buffer: {
      from: function(data, encoding) {
        if (typeof data === 'string') {
          if (encoding === 'base64') {
            return Uint8Array.from(atob(data), c => c.charCodeAt(0));
          }
          return new TextEncoder().encode(data);
        }
        return new Uint8Array(data);
      },
      bufToString: function(buf, format) {
        if (format === 'hex') {
          return Array.from(new Uint8Array(buf))
            .map(b => b.toString(16).padStart(2, '0'))
            .join('');
        }
        if (format === 'base64') {
          return btoa(String.fromCharCode(...new Uint8Array(buf)));
        }
        return new TextDecoder().decode(buf);
      },
    },
    zlib: {
      inflate: function(buf) {
        console.warn('[LxMusic] zlib.inflate not implemented');
        return Promise.resolve(buf);
      },
      deflate: function(data) {
        console.warn('[LxMusic] zlib.deflate not implemented');
        return Promise.resolve(data);
      },
    },
  };
  
  // ==================== 暴露全局 lx 对象 ====================
  
  window.lx = {
    EVENT_NAMES: EVENT_NAMES,
    request: request,
    send: send,
    on: on,
    utils: utils,
    version: '2.0.0',
    env: 'desktop',  // 使用 desktop 环境标识以匹配洛雪桌面端
    currentScriptInfo: {
      name: '',
      version: '',
      author: '',
      description: '',
      homepage: '',
      rawScript: '',
    },
  };
  
  // ==================== Flutter 调用的接口 ====================
  
  // 重置状态
  window.__lx_reset__ = function() {
    isInited = false;
    requestHandler = null;
    pendingHttpRequests.clear();
    console.log('[LxMusic] Sandbox reset');
  };
  
  // 设置脚本信息
  window.__lx_setScriptInfo__ = function(info) {
    currentScriptInfo = info;
    // 解码 Base64 编码的脚本内容
    let rawScript = '';
    if (info.scriptBase64) {
      try {
        rawScript = atob(info.scriptBase64);
        console.log('[LxMusic] rawScript 已设置，长度: ' + rawScript.length);
      } catch (e) {
        console.warn('[LxMusic] Base64 解码失败: ' + e.message);
      }
    }
    window.lx.currentScriptInfo = {
      name: info.name || '',
      version: info.version || '',
      author: info.author || '',
      description: info.description || '',
      homepage: info.homepage || '',
      rawScript: rawScript,
    };
    console.log('[LxMusic] Script info set:', info.name);
  };
  
  // 发送请求到脚本
  window.__lx_sendRequest__ = function(data) {
    console.log('[LxMusic] __lx_sendRequest__ called, data:', JSON.stringify(data));
    console.log('[LxMusic] requestHandler type:', typeof requestHandler);

    if (!requestHandler) {
      sendToFlutter('lxOnResponse', {
        requestKey: data.requestKey,
        success: false,
        error: 'Request handler not registered',
      });
      return;
    }

    try {
      let result;

      if (typeof requestHandler === 'function') {
        // 函数形式: lx.on('request', (req) => { ... })
        console.log('[LxMusic] Calling function handler');
        const context = {};
        try {
          result = requestHandler.call(context, {
            source: data.source,
            action: data.action,
            info: data.info,
          });
          console.log('[LxMusic] Function handler returned, result type: ' + typeof result);
        } catch (innerErr) {
          console.log('[LxMusic] Function handler threw error: ' + (innerErr.message || String(innerErr)));
          throw innerErr;
        }
      } else if (typeof requestHandler === 'object' && requestHandler !== null) {
        // 对象形式: lx.on('request', { musicUrl: (info, source) => { ... } })
        const method = requestHandler[data.action];
        console.log('[LxMusic] Handler type: object, action: ' + data.action + ', method type: ' + typeof method);
        console.log('[LxMusic] Available actions: ' + Object.keys(requestHandler).join(', '));
        console.log('[LxMusic] Info: ' + JSON.stringify(data.info));
        if (typeof method === 'function') {
          console.log('[LxMusic] Calling method for action: ' + data.action);
          result = method.call(requestHandler, data.info, data.source);
          console.log('[LxMusic] Method returned, result type: ' + typeof result);
        } else {
          throw new Error('Handler does not support action: ' + data.action + ', type: ' + typeof method);
        }
      } else {
        throw new Error('Invalid request handler type: ' + typeof requestHandler);
      }

      if (result && typeof result.then === 'function') {
        result.then(function(url) {
          sendToFlutter('lxOnResponse', {
            requestKey: data.requestKey,
            success: true,
            url: url,
          });
        }).catch(function(err) {
          const errMsg = err && err.stack ? String(err.stack) : (err.message || String(err));
          sendToFlutter('lxOnResponse', {
            requestKey: data.requestKey,
            success: false,
            error: errMsg,
          });
        });
      } else {
        sendToFlutter('lxOnResponse', {
          requestKey: data.requestKey,
          success: true,
          url: result,
        });
      }
    } catch (err) {
      const errMsg = err && err.stack ? String(err.stack) : (err.message || String(err));
      sendToFlutter('lxOnResponse', {
        requestKey: data.requestKey,
        success: false,
        error: errMsg,
      });
    }
  };
  
  // 处理 HTTP 响应
  window.__lx_handleHttpResponse__ = function(data) {
    console.log('[LxMusic] __lx_handleHttpResponse__ called, requestId: ' + data.requestId);

    const callback = pendingHttpRequests.get(data.requestId);
    if (callback) {
      console.log('[LxMusic] Found callback for requestId: ' + data.requestId);
      pendingHttpRequests.delete(data.requestId);
      if (data.success) {
        // 获取 body，优先使用 data.body，如果没有则使用 data.response.body
        var body = data.body || (data.response && data.response.body);
        // 如果 body 是对象，转换为 JSON 字符串（脚本期望字符串）
        if (body && typeof body === 'object') {
          body = JSON.stringify(body);
        }
        console.log('[LxMusic] Calling callback with success, body: ' + (body ? body.substring(0, 100) : 'null'));
        callback(null, data.response, body);
      } else {
        console.log('[LxMusic] Calling callback with error: ' + data.error);
        callback(new Error(data.error), null, null);
      }
    } else {
      console.log('[LxMusic] No callback found for requestId: ' + data.requestId);
    }
  };
  
  // 处理错误
  window.__lx_onError__ = function(message) {
    console.error('[LxMusic] Script error:', message);
    sendToFlutter('lxOnError', message);
  };
  
  // 全局错误捕获
  if (window.addEventListener) {
    window.addEventListener('error', function(event) {
      window.__lx_onError__(event.message);
    });
    
    window.addEventListener('unhandledrejection', function(event) {
      const message = event.reason?.message || String(event.reason);
      window.__lx_onError__(message);
    });
  }
  
  console.log('[LxMusic] Sandbox initialized');
  
  // ==================== 调试函数 ====================
  // 检查脚本加载后的关键全局变量
  window.__lx_debugGlobals__ = function() {
    console.log('========== [LxMusic Global Variables Debug] ==========');
    
    // 检查可能的签名相关变量
    const varNames = ['API_URL', 'API_KEY', 'SECRET_KEY', 'SCRIPT_MD5', 'version', 
                      'DEV_ENABLE', 'UPDATE_ENABLE', 'MUSIC_SOURCE'];
    
    varNames.forEach(function(name) {
      if (typeof window[name] !== 'undefined') {
        const val = window[name];
        const display = typeof val === 'object' ? JSON.stringify(val) : String(val);
        console.log('[LxMusic] window.' + name + ' = ' + display.substring(0, 200));
      }
    });
    
    // 检查 globalThis
    varNames.forEach(function(name) {
      if (typeof globalThis !== 'undefined' && typeof globalThis[name] !== 'undefined' && globalThis[name] !== window[name]) {
        const val = globalThis[name];
        const display = typeof val === 'object' ? JSON.stringify(val) : String(val);
        console.log('[LxMusic] globalThis.' + name + ' = ' + display.substring(0, 200));
      }
    });
    
    // 检查 MUSIC_SOURCE 导出模块
    if (window.MUSIC_SOURCE) {
      console.log('[LxMusic] MUSIC_SOURCE module found:');
      const ms = window.MUSIC_SOURCE;
      if (ms.API_URL) console.log('[LxMusic]   API_URL = ' + ms.API_URL);
      if (ms.API_KEY) console.log('[LxMusic]   API_KEY = ' + ms.API_KEY);
      if (ms.SECRET_KEY) console.log('[LxMusic]   SECRET_KEY = ' + (ms.SECRET_KEY ? ms.SECRET_KEY.substring(0, 10) + '...' : 'undefined'));
      if (ms.SCRIPT_MD5) console.log('[LxMusic]   SCRIPT_MD5 = ' + ms.SCRIPT_MD5);
      if (ms.generateSign) console.log('[LxMusic]   generateSign = function');
      if (ms.sha256) console.log('[LxMusic]   sha256 = function');
    }
    
    console.log('========================================================');
  };
  
  // 在脚本执行 500ms 后自动检查全局变量
  setTimeout(function() {
    if (isInited) {
      window.__lx_debugGlobals__();
    }
  }, 500);
})();
''';
