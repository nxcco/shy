(function () {
  if (Object.prototype.hasOwnProperty.call(window, '__officeForms')) return;

  // What was typed by hand and not yet sent, box by box. A page whose
  // boxes still hold it is not put to sleep: waking it couldn't bring
  // that back. A box emptied by sending — a chat's composer — no longer
  // counts, and neither does a search box.
  var typed = [];
  document.addEventListener('input', function (e) {
    if (!e.isTrusted) return;
    var el = e.target;
    if (!el || typed.indexOf(el) >= 0) return;
    typed.push(el);
    if (typed.length > 40) typed.shift();
  }, true);
  function unsaved() {
    for (var i = 0; i < typed.length; i++) {
      var el = typed[i];
      if (!el.isConnected) continue;
      var tag = (el.tagName || '').toLowerCase();
      if (tag === 'textarea') {
        if (el.value.trim() && el.value !== el.defaultValue) return true;
      } else if (tag === 'input') {
        var kind = (el.type || 'text').toLowerCase();
        if (['text', 'email', 'url', 'tel', 'number'].indexOf(kind) < 0) continue;
        if (el.value.trim() && el.value !== el.defaultValue) return true;
      } else if (el.isContentEditable) {
        if ((el.textContent || '').trim()) return true;
      }
    }
    return false;
  }

  window.__officeForms = { unsaved: unsaved };

  // Whether the caret is somewhere on the page that takes typing.
  //
  // The browser gives Tab to its own row of tabs, which is right until you
  // are filling something in: plenty of fields offer a completion you take
  // with Tab, and stealing the key there would make them unusable.
  function editable(el) {
    if (!el) return false;
    var tag = (el.tagName || '').toLowerCase();
    if (tag === 'textarea') return true;
    if (el.isContentEditable === true) return true;
    if (el.getAttribute && el.getAttribute('role') === 'textbox') return true;
    // A document that types into a frame of its own — Google Docs keeps
    // the caret there. ⌘⇧V is that document's paste, so the frame counts.
    if (tag === 'iframe') {
      try { return editable(el.contentDocument && el.contentDocument.activeElement); }
      catch (e) { return false; }
    }
    if (tag !== 'input') return false;
    var kind = (el.type || 'text').toLowerCase();
    return ['text', 'search', 'email', 'url', 'tel', 'password', 'number',
            'date', 'datetime-local', 'month', 'week', 'time'].indexOf(kind) >= 0;
  }

  // What was last said, so a scroll can keep quiet when nothing moved
  // that anyone is listening for.
  var said = null;
  // A box the page says takes a passkey: autocomplete="username webauthn".
  function forPasskeys(el) {
    return !!(el && (el.tagName || '').toLowerCase() === 'input' &&
      /(^|\s)webauthn(\s|$)/i.test(el.getAttribute('autocomplete') || ''));
  }
  function caret(scrolled) {
    var el = document.activeElement;
    var rect = null;
    if (forPasskeys(el)) {
      var r = el.getBoundingClientRect();
      if (r.width > 0 && r.height > 0) rect = { x: r.left, y: r.top, w: r.width, h: r.height };
    }
    var typing = editable(el);
    var now = typing + (rect ? ' ' + rect.x + ' ' + rect.y + ' ' + rect.w + ' ' + rect.h : '');
    if (scrolled === true && now === said) return;
    said = now;
    window.webkit.messageHandlers.officeForms.postMessage({
      kind: 'focus',
      typing: typing,
      rect: rect
    });
  }

  // The box moves when the page scrolls or the window changes size, and
  // whatever hangs from it has to move too. Once a frame at most, and
  // only when something did change: with the caret nowhere near a passkey box,
  // every frame of every scroll used to send the same answer again.
  var moving = false;
  function moved() {
    if (moving) return;
    moving = true;
    requestAnimationFrame(function () { moving = false; caret(true); });
  }
  window.addEventListener('scroll', moved, true);
  window.addEventListener('resize', moved);

  // A page's full screen, in and out. WebKit's own state says it first
  // (Tab.immersed follows web.fullscreenState): in once WebKit has the
  // page in its window, back as it starts to give it back. This comes
  // after each and is only a fallback. It used to be said early, on the
  // request itself, which laid the page out at the whole window's size
  // in ours a moment before WebKit took it, and the way back then
  // started from that size.
  function immersed() {
    var on = !!(document.fullscreenElement || document.webkitFullscreenElement);
    window.webkit.messageHandlers.officeForms.postMessage({
      kind: 'fullscreen', on: on
    });
  }
  document.addEventListener('fullscreenchange', immersed, true);
  document.addEventListener('webkitfullscreenchange', immersed, true);

  document.addEventListener('focusin', caret, true);
  document.addEventListener('focusout', function () { setTimeout(caret, 0); }, true);
  document.addEventListener('mouseup', function () { setTimeout(caret, 0); }, true);
  caret();
})();
