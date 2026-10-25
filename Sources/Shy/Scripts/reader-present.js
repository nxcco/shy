function present(wrap, title, from, sheet) {
  // Light unless reading mode follows the window (`readerLook`, when given).
  var chosen = typeof readerLook === 'string' ? readerLook : 'light';
  if (chosen === 'system') document.documentElement.removeAttribute('data-office-look');
  else document.documentElement.setAttribute('data-office-look', chosen);
  var theirs = document.querySelectorAll('style, link[rel~="stylesheet" i]');
  for (var i = 0; i < theirs.length; i++) {
    if ((theirs[i].id || '').indexOf('office-') !== 0) theirs[i].remove();
  }
  document.documentElement.removeAttribute('style');
  document.body.removeAttribute('style');
  var style = document.createElement('style');
  style.id = 'office-reader-sheet';
  style.textContent = sheet;
  var top = document.createElement('h1');
  top.textContent = title;
  var line = document.createElement('p');
  line.className = 'office-from';
  line.textContent = from;
  wrap.id = 'office-reader';
  document.body.innerHTML = '';
  (document.head || document.documentElement).appendChild(style);
  wrap.insertBefore(line, wrap.firstChild);
  wrap.insertBefore(top, wrap.firstChild);
  document.body.appendChild(wrap);
  window.scrollTo(0, 0);
}
