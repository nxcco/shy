(function () {
  var videos = document.querySelectorAll('video');
  var best = null, area = 0;
  for (var i = 0; i < videos.length; i++) {
    var v = videos[i];
    if (v.paused || v.ended || v.readyState < 2) continue;
    var box = v.getBoundingClientRect();
    if (box.width * box.height >= area) { area = box.width * box.height; best = v; }
  }
  if (!best) return 'none';

  // Where the video's picture is, for cutting it out of a picture of the
  // page (Float.still): inside its box as `contain` fits it, which is
  // how a video is drawn unless the page says otherwise.
  var r = best.getBoundingClientRect(), pic = [r.left, r.top, r.width, r.height];
  var vw = best.videoWidth, vh = best.videoHeight;
  if (vw && vh && r.width && r.height && getComputedStyle(best).objectFit === 'contain') {
    var fit = Math.min(r.width / vw, r.height / vh);
    pic = [r.left + (r.width - vw * fit) / 2, r.top + (r.height - vh * fit) / 2, vw * fit, vh * fit];
  }
  // And where the video was in the page, at what size of page, for the
  // landing to wait for (see off). Not while the last float is still
  // landing: the page isn't as it was yet, and the place it is going
  // back to is the one kept from before. And whether Twitch's chat was
  // open, for opening it again (see off).
  var wait = window.__officeFloatWait;
  if (!window.__officeFloatHome || !(window.__officeFloatLanding || (wait && wait.landing && !wait.settled))) {
    window.__officeFloatHome = {
      box: [r.left + scrollX, r.top + scrollY, r.width, r.height],
      size: [best.offsetWidth, best.offsetHeight],
      wide: innerWidth, high: innerHeight,
      chat: !!document.querySelector('.right-column:not(.right-column--collapsed) [data-a-target="right-column__toggle-collapse-btn"]')
    };
  }
  var size = window.__officeFloatHome.size;
  // And the picture in it, as `contain` fits it. Twitch's player, in its
  // Studio mode, gives the video the page's whole height and draws the
  // picture in the middle of it, between black bars: scaled whole, the
  // bars took up the little window, and the picture a part of it.
  var shown = size;
  if (vw && vh && size[0] && size[1]) {
    var within = Math.min(size[0] / vw, size[1] / vh);
    shown = [vw * within, vh * within];
  }

  // A landing still waiting for its tab is called off: the page is out
  // again.
  window.__officeFloatLanding = null;
  window.__officeFloatWait = null;
  best.setAttribute('data-office-float', '');
  var sheet = document.getElementById('office-float');
  if (!sheet) {
    sheet = document.createElement('style');
    sheet.id = 'office-float';
    (document.head || document.documentElement).appendChild(sheet);
  }
  sheet.textContent = [
    'html.office-floating, html.office-floating body {',
    'background:#000 !important; overflow:hidden !important; margin:0 !important}',
    'html.office-floating body > * { visibility:hidden !important }',
    'html.office-floating [data-office-float] {',
    'visibility:visible !important; position:fixed !important;',
    'left:0 !important; top:0 !important; right:0 !important; bottom:0 !important;',
    'width:100vw !important; height:100vh !important;',
    'max-width:none !important; max-height:none !important;',
    // The player's own box and clipping must not cut off the floating picture.
    'min-width:0 !important; min-height:0 !important; margin:0 !important; padding:0 !important; border:0 !important;',
    'clip-path:none !important; mask:none !important; -webkit-mask:none !important;',
    // Players such as Netflix center the element with a translation.
    // With our top/left at zero, that moves it out of the floating window.
    'transform:none !important; translate:none !important; rotate:none !important; scale:none !important;',
    'opacity:1 !important; object-fit:contain !important; z-index:2147483647 !important}',
    // Better, where WebKit can divide one length by another: the video
    // keeps the size it had in its tab, and is only scaled to the
    // window, its picture as large as it goes whole and in the middle,
    // and whatever is around the picture off the window's edges. Made the
    // window's size, its picture is redrawn at that size by another of
    // WebKit's processes a third of a second after everything else, and
    // until then it showed at its old size shrunk with the page, in a
    // part of the window, before growing to fill it.
    size[0] && size[1] ? [
      '@supports (scale: calc(100vw / 1px)) {',
      'html.office-floating [data-office-float] {',
      '--office-float-by: min(calc(100vw / ' + shown[0] + 'px), calc(100vh / ' + shown[1] + 'px));',
      'right:auto !important; bottom:auto !important; margin:0 !important; box-sizing:border-box !important;',
      'width:' + size[0] + 'px !important; height:' + size[1] + 'px !important;',
      'min-width:0 !important; min-height:0 !important; transform-origin:0 0 !important;',
      'transform:translate(calc((100vw - ' + size[0] + 'px * var(--office-float-by)) / 2),',
      ' calc((100vh - ' + size[1] + 'px * var(--office-float-by)) / 2)) scale(var(--office-float-by)) !important}}'
    ].join('') : '',
    // Netflix renders timed text after the video, in a layer of its own
    // beside it or one level up. Keep it above the video without
    // exposing the rest of the player.
    'html.office-floating [data-office-float] ~ .player-timedtext,',
    'html.office-floating :has(> [data-office-float]) > .player-timedtext,',
    'html.office-floating :has([data-office-float]) > .player-timedtext {',
    'visibility:visible !important; z-index:2147483647 !important}',
    // Fixed or not, the video is still cut to the box of any ancestor
    // that clips — YouTube's player does — and in a window this small
    // that box sits partly or wholly off screen, more so on a page that
    // was scrolled. That was the black window.
    'html.office-floating body :has([data-office-float]) {',
    'overflow:visible !important;',
    // And fixed is only fixed to the window while no ancestor makes a
    // box of its own for it: a transform, a filter, containment, a
    // perspective, a backdrop, a container query — Twitch's player has
    // some — and the video was placed and sized inside that box instead,
    // part of it or none of it in the window. An ancestor drawn only
    // when on screen (content-visibility) wasn't drawn at all once the
    // rest of the page was hidden, and one faded out hid the video too.
    'transform:none !important; translate:none !important; rotate:none !important; scale:none !important;',
    'filter:none !important; backdrop-filter:none !important; -webkit-backdrop-filter:none !important;',
    'perspective:none !important; contain:none !important; container-type:normal !important;',
    'will-change:auto !important; content-visibility:visible !important;',
    'clip-path:none !important; mask:none !important; -webkit-mask:none !important;',
    'opacity:1 !important}',
    // The player's own controls would sit under ours, and two sets of
    // buttons on one small window is one set too many.
    'html.office-floating [data-office-float]::-webkit-media-controls {',
    'display:none !important}'
  ].join('');
  document.documentElement.classList.add('office-floating');

  // The mark has to be defended.
  //
  // Everything but the marked element is hidden, so the moment a player
  // rebuilds its DOM — and they all do, on a quality change, an ad break,
  // a React re-render — the mark goes with the old element and the window
  // turns pure black while still holding a perfectly live page. That is the
  // black rectangle, and it is not an orphaned window at all.
  //
  // So the mark is put back on whatever is playing now, four times a
  // second, for as long as the page is out.
  clearInterval(window.__officeFloatWatch);
  window.__officeFloatWatch = setInterval(function () {
    if (document.querySelector('[data-office-float]')) return;
    var again = null, most = 0;
    var all = document.querySelectorAll('video');
    for (var j = 0; j < all.length; j++) {
      var one = all[j];
      if (one.paused || one.ended || one.readyState < 2) continue;
      var shape = one.getBoundingClientRect();
      if (shape.width * shape.height >= most) {
        most = shape.width * shape.height;
        again = one;
      }
    }
    if (again) again.setAttribute('data-office-float', '');
  }, 250);

  return { floating: true, picture: pic, page: [innerWidth, innerHeight] };
})();
