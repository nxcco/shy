(() => {
  const keys = new Set();
  function note(e) {
    if (!e.isTrusted) return;
    if (e.type === 'keydown' && (e.key === 'Escape' ||
        ['Shift', 'Control', 'Alt', 'Meta'].includes(e.key))) return;
    if (e.type === 'keydown') keys.add(e.code || e.key);
    if (e.repeat) return;
    // Enter can produce trusted clicks while held; those clicks have no
    // repeat flag. The initial keydown already supplied their one grant.
    if (e.type === 'click' && e.detail === 0 && keys.size) return;
    window.webkit.messageHandlers.officePopupGesture.postMessage(
      e.type === 'click' ? 'click' : e.type === 'contextmenu' ? 'menu' : 'input');
  }
  addEventListener('mousedown', note, true);
  addEventListener('keydown', note, true);
  addEventListener('click', note, true);
  addEventListener('contextmenu', note, true);
  addEventListener('keyup', e => { if (e.isTrusted) keys.delete(e.code || e.key); }, true);
  addEventListener('blur', e => { if (e.isTrusted && e.target === window) keys.clear(); }, true);
})();
