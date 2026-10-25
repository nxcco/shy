let n = (typeof x === 'number') ? document.elementFromPoint(x, y) : null;
while (n && n !== document.body && n !== document.documentElement) {
  const s = getComputedStyle(n);
  const down = /(auto|scroll)/.test(s.overflowY) && n.scrollHeight > n.clientHeight;
  const across = /(auto|scroll)/.test(s.overflowX) && n.scrollWidth > n.clientWidth;
  if ((dy && down) || (dx && across)) { n.scrollBy(dx, dy); return 'ok'; }
  n = n.parentElement;
}
window.scrollBy(dx, dy);
return 'ok';
