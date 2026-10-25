function find(s) {
  if (s.indexOf('text=') === 0) {
    const want = s.slice(5).trim().toLowerCase();
    const all = Array.from(document.querySelectorAll('a, button, input[type=submit], input[type=button], [role=button], [role=link], label, summary'));
    const words = e => (e.innerText || e.value || e.getAttribute('aria-label') || '').trim().toLowerCase();
    return all.find(e => words(e) === want) || all.find(e => words(e).includes(want)) || null;
  }
  try { return document.querySelector(s); } catch (e) { return undefined; }
}
