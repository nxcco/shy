(function (listings) {
  var made = window.browser, runtime = made && made.runtime;
  if (typeof window.chrome !== 'undefined' || !runtime || typeof runtime.sendMessage !== 'function') return;
  // Chrome's match patterns: scheme, host, then path. A host with a
  // port matches that port only; one without, any.
  var glob = function (text) {
    return new RegExp('^' + text.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*') + '$');
  };
  var listed = function (pattern) {
    var parts = /^(\*|https?):\/\/([^\/]+)(\/.*)$/.exec(pattern);
    if (!parts) return false;
    var scheme = location.protocol.slice(0, -1);
    if (parts[1] === '*' ? scheme !== 'http' && scheme !== 'https' : parts[1] !== scheme) return false;
    var host = parts[2], port = '';
    var colon = host.lastIndexOf(':');
    if (colon > 0 && host.indexOf(']') < colon) { port = host.slice(colon + 1); host = host.slice(0, colon); }
    if (port && port !== '*' && port !== location.port) return false;
    var here = location.hostname;
    if (host.indexOf('*.') === 0) {
      var base = host.slice(2);
      if (base.indexOf('.') < 0) return false;
      if (here !== base && here.slice(-base.length - 1) !== '.' + base) return false;
    } else if (host !== here) return false;
    return glob(parts[3]).test(location.pathname + location.search);
  };
  // The extensions that list this page: the only ones it can reach.
  var reached = Object.keys(listings).filter(function (id) { return listings[id].some(listed); });
  if (!reached.length) return;
  var chromeRuntime = {
    sendMessage: function (id, message, options, callback) {
      if (typeof options === 'function') { callback = options; options = undefined; }
      var sent = reached.indexOf(id) < 0
        ? Promise.reject(new Error('Could not establish connection. Receiving end does not exist.'))
        : options === undefined ? runtime.sendMessage(id, message) : runtime.sendMessage(id, message, options);
      if (typeof callback !== 'function') return sent;
      Promise.resolve(sent).then(function (reply) { callback(reply); }, function (error) {
        chromeRuntime.lastError = { message: String(error && error.message || error) };
        try { callback(); } finally { delete chromeRuntime.lastError; }
      });
    }
  };
  if (typeof runtime.connect === 'function') {
    chromeRuntime.connect = function () { return runtime.connect.apply(runtime, arguments); };
  }
  try {
    Object.defineProperty(window, 'chrome', {
      value: { runtime: chromeRuntime }, configurable: true, writable: true, enumerable: false
    });
  } catch (e) {}
})(__SHY_LIST__);
