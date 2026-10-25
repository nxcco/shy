var markdown = ['text/markdown', 'text/x-markdown'];
function kind(type) { return (type || '').toLowerCase().split(';')[0].trim(); }
var heading = document.querySelector('h1');
var about = {
  title: (heading && heading.innerText.trim()) || document.title,
  from: location.host.replace(/^www\./, '')
};

var own = kind(document.contentType);
if (markdown.indexOf(own) >= 0 ||
    (own === 'text/plain' && /\.(md|markdown)$/i.test(location.pathname))) {
  return { url: location.href, text: document.body ? document.body.textContent : '',
           title: about.title, from: about.from };
}
if (!/^https?:$/.test(location.protocol)) return null;

// `named`: the page asked for this one by name, and a site that says so
// may serve its markdown as plain text.
function home(address) {
  try { return new URL(address, location.href).origin === location.origin; } catch (e) { return false; }
}
async function read(address, patience, named) {
  if (!home(address)) return null;
  var stop = new AbortController();
  var timer = setTimeout(function () { stop.abort(); }, patience);
  try {
    var answer = await fetch(address, {
      headers: { Accept: 'text/markdown, text/plain;q=0.5' },
      cache: 'no-store', credentials: 'same-origin', signal: stop.signal
    });
    var type = kind(answer.headers.get('content-type'));
    var fits = markdown.indexOf(type) >= 0 || (named && type === 'text/plain');
    if (!answer.ok || !fits || (answer.url && !home(answer.url))) {
      if (answer.body) answer.body.cancel();
      return null;
    }
    var text = await answer.text();
    if (text.length > 4000000 || /^\s*<(!doctype|html)/i.test(text)) return null;
    return { url: answer.url || address, text: text, title: about.title, from: about.from };
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

var links = document.querySelectorAll('link[rel~="alternate" i][type]');
for (var i = 0; i < links.length; i++) {
  if (markdown.indexOf(kind(links[i].type)) < 0 || !/^https?:/.test(links[i].href) || !home(links[i].href)) continue;
  var named = await read(links[i].href, 5000, true);
  if (named) return named;
  break;
}

// Most sites have no twin, so this one is kept short: the reader
// shouldn't wait on an address that was only ever a guess.
var guess = new URL(location.href);
guess.hash = '';
if (/\.(md|markdown)$/i.test(guess.pathname)) return null;
guess.pathname += /\/$/.test(guess.pathname) ? 'index.html.md' : '.md';
return await read(guess.href, 1500, false);
