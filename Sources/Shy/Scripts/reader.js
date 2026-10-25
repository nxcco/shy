
  function prose(el) {
    var paragraphs = el.querySelectorAll('p');
    if (paragraphs.length < 2) return 0;
    var letters = 0;
    for (var i = 0; i < paragraphs.length; i++) {
      letters += (paragraphs[i].innerText || '').length;
    }
    if (letters < 400) return 0;
    // A rail of related links has plenty of text and nothing to read.
    var links = el.querySelectorAll('a').length;
    return letters / (1 + links * 14);
  }

  function best() {
    var candidates = document.querySelectorAll(
      'article, main, [role="main"], .post, .entry, .article, .content, #content, div, section'
    );
    var top = null, mark = 0;
    for (var i = 0; i < candidates.length; i++) {
      var score = prose(candidates[i]);
      if (score > mark) { mark = score; top = candidates[i]; }
    }
    return top;
  }

  // Already an article: going back can bring one as it was left.
  if (document.getElementById('office-reader')) return 'read';

  var article = best();
  if (!article) return 'none';

  // The photo an article opens with isn't always in it: the FT keeps its
  // own in a topper beside the <article>. So the first large picture
  // before the text comes too, looked for no more than four boxes out,
  // and never in a menu, a rail or a footer.
  var lead = null;
  for (var up = article.parentElement, depth = 0;
       up && up !== document.body && depth < 4 && !lead;
       up = up.parentElement, depth++) {
    var shown = up.querySelectorAll('figure, picture');
    for (var l = 0; l < shown.length && !lead; l++) {
      var face = shown[l].querySelector('img');
      // Before the text, and not around it.
      if (face && article.compareDocumentPosition(shown[l]) === Node.DOCUMENT_POSITION_PRECEDING &&
          !shown[l].closest('nav, aside, footer, [role="banner"]') &&
          face.getBoundingClientRect().width >= 400) lead = shown[l];
    }
  }

  // A chart's frame is as tall as its own script made it, and that script
  // won't run in the reader: the height is read while the page shows it.
  var framed = article.querySelectorAll('iframe');
  for (var z = 0; z < framed.length; z++) {
    framed[z].setAttribute('data-office-height', Math.round(framed[z].getBoundingClientRect().height));
  }

  // Bloomberg keeps an article's byline, its takeaways and the video it
  // opens with between the headline and the text, outside the part with
  // the most prose. Such parts of its head come along, in the page's
  // order: those drawn on the page, and never one from a menu, a rail or
  // a footer. Class names are matched in part and whatever their case,
  // as sites build them (BasicByline_byline__VTyoS); a subheading is an
  // h2.
  // The size a drawing in the text is given, an icon as often as not,
  // goes with the page's styles: left to itself, an <svg> fills the
  // column. The size it is drawn at is written onto it.
  var drawings = article.querySelectorAll('svg');
  for (var dr = 0; dr < drawings.length; dr++) {
    if (drawings[dr].parentElement.closest('svg')) continue;
    var drawn = drawings[dr].getBoundingClientRect();
    drawings[dr].setAttribute('width', Math.round(drawn.width));
    drawings[dr].setAttribute('height', Math.round(drawn.height));
  }

  var heading = document.querySelector('h1');
  var above = [];
  if (heading) {
    var found = document.querySelectorAll(
      '[class*="byline" i],[class*="takeaways" i],[class*="lede" i],h2'
    );
    for (var a = 0; a < found.length; a++) {
      var part = found[a];
      if (part.contains(article) || article.contains(part) ||
          above.some(function (o) { return o.contains(part); })) continue;
      if (!(heading.compareDocumentPosition(part) & Node.DOCUMENT_POSITION_FOLLOWING)) continue;
      if (!(article.compareDocumentPosition(part) & Node.DOCUMENT_POSITION_PRECEDING)) continue;
      if (part.closest('nav, aside, footer, [role="banner"]') || !part.getClientRects().length) continue;
      above.push(part);
    }
  }

  // Every picture is resolved while the real page is still standing.
  //
  // currentSrc is what the browser actually chose and loaded, after srcset,
  // sizes and <picture> have had their say. Reading it here and writing it
  // back as a plain src is the only way to be sure the reader shows the
  // same image the page did — copying the markup alone gets you a lazy
  // placeholder, or nothing at all.
  var late = ['data-src', 'data-original', 'data-lazy-src', 'data-lazy',
              'data-full-src', 'data-hi-res-src', 'data-image', 'data-echo'];
  var pictures = Array.prototype.slice.call(article.querySelectorAll('img'));
  if (lead) pictures = pictures.concat(Array.prototype.slice.call(lead.querySelectorAll('img')));
  above.forEach(function (o) {
    pictures = pictures.concat(Array.prototype.slice.call(o.querySelectorAll('img')));
  });
  for (var i = 0; i < pictures.length; i++) {
    var picture = pictures[i];
    picture.setAttribute('loading', 'eager');
    var real = picture.currentSrc || picture.getAttribute('src') || '';
    // A one-pixel placeholder counts as nothing.
    if (!real || real.indexOf('data:image') === 0 || picture.naturalWidth <= 2) {
      for (var k = 0; k < late.length; k++) {
        var kept = picture.getAttribute(late[k]);
        if (kept) { real = kept; break; }
      }
    }
    if (real) picture.setAttribute('src', real);
    var lateSet = picture.getAttribute('data-srcset');
    if (lateSet && !picture.getAttribute('srcset')) {
      picture.setAttribute('srcset', lateSet);
    }
  }

  // What the page's own styles hide, seen while they still apply: the
  // reading page goes without them (see present), and a label meant
  // only for screen readers, a menu folded shut or the mobile copy of a
  // table would all come into view. Pictures' sources and the like are
  // hidden by WebKit itself, which the reading page keeps.
  // Not a box that holds paragraphs, though: an article's folded-away
  // rest is still the article. The head's parts are looked at the same.
  var inherent = /^(SOURCE|TRACK|PARAM|AREA|TEMPLATE|BR|WBR|SCRIPT|STYLE|NOSCRIPT)$/;
  var all = [];
  [article].concat(above).forEach(function (root) {
    all = all.concat(Array.prototype.slice.call(root.querySelectorAll('*')));
  });
  for (var h = 0; h < all.length; h++) {
    var el = all[h];
    if (inherent.test(el.tagName) || el.closest('details:not([open])')) continue;
    var look = getComputedStyle(el);
    var gone = look.display === 'none' || look.visibility === 'hidden';
    if (!gone && (look.overflow === 'hidden' || look.clip !== 'auto')) {
      var box = el.getBoundingClientRect();
      // The usual way of hiding text from sight but not from a screen
      // reader: a box a pixel square, its overflow cut off.
      gone = box.width <= 1 && box.height <= 1;
    }
    if (gone && !(look.display === 'none' && el.querySelector('p'))) el.setAttribute('data-office-hidden', '');
  }

  var title = (heading && heading.innerText.trim()) || document.title;

  var wrap = document.createElement('div');
  wrap.innerHTML = article.innerHTML;
  for (var o = above.length - 1; o >= 0; o--) {
    var copy = above[o].cloneNode(true);
    copy.classList.add('office-above');
    wrap.insertBefore(copy, wrap.firstChild);
  }

  var hidden = wrap.querySelectorAll('[data-office-hidden]');
  for (var d = 0; d < hidden.length; d++) hidden[d].remove();
  // A style written on an element is the page's styling too: a fixed
  // width, a white font for a dark box that isn't there any more.
  var styled = wrap.querySelectorAll('[style]');
  for (var y = 0; y < styled.length; y++) styled[y].removeAttribute('style');
  // The photo comes without the topper's own classes and styles, which
  // the page's stylesheet would still lay out as a topper: off to one
  // side, cropped.
  if (lead) {
    var opening = lead.cloneNode(true);
    var parts = [opening].concat(Array.prototype.slice.call(opening.querySelectorAll('*')));
    for (var x = 0; x < parts.length; x++) {
      parts[x].removeAttribute('class');
      parts[x].removeAttribute('style');
    }
    var after = wrap.firstChild;
    while (after && after.classList && after.classList.contains('office-above')) after = after.nextSibling;
    wrap.insertBefore(opening, after);
  }

  // A picture in a button, a click to see it larger, is the picture:
  // Bloomberg puts every photo in one. The button goes and what it holds
  // stays.
  var pressed = wrap.querySelectorAll('button');
  for (var b = 0; b < pressed.length; b++) {
    if (!pressed[b].querySelector('img, picture, video')) continue;
    while (pressed[b].firstChild) pressed[b].parentNode.insertBefore(pressed[b].firstChild, pressed[b]);
    pressed[b].remove();
  }

  // What was arranged around the words rather than being part of them.
  // Not header: an article's opening image lives there as often as not.
  // A video.js player's controls, title bar and read-outs go too; the
  // video stays.
  var clutter = wrap.querySelectorAll(
    'script,style,noscript,form,nav,aside,footer,button,input,select,textarea,' +
    '[role="complementary"],[role="navigation"],[role="banner"],[aria-hidden="true"],' +
    '.video-js > [class*="vjs-"]:not(video)'
  );
  for (var c = 0; c < clutter.length; c++) clutter[c].remove();

  // So does a box inviting you to a newsletter, which Bloomberg sets in
  // the middle of the text. Only a short one: a newsletter's own page
  // may keep its whole text in a box named the same.
  var invites = wrap.querySelectorAll('[class*="newsletter" i]');
  for (var n = 0; n < invites.length; n++) {
    if (invites[n].querySelectorAll('p').length < 3) invites[n].remove();
  }

  // Embedded video is part of the article, and so is a chart or a map
  // from one of the chart makers a newsroom puts in it, at the height it
  // had. Any other frame is not: an advertisement, a widget.
  var players = /youtube|youtu\.be|vimeo|dailymotion|loom\.com|streamable|wistia|ted\.com/i;
  var charts = /flourish|flo\.uri\.sh|datawrapper|dwcdn\.net|infogram|tableau|ig\.ft\.com|google\.com\/maps/i;
  var frames = wrap.querySelectorAll('iframe');
  for (var f = 0; f < frames.length; f++) {
    var where = frames[f].getAttribute('src') || frames[f].getAttribute('data-src') || '';
    if (players.test(where)) {
      frames[f].setAttribute('src', where);
      frames[f].removeAttribute('height');
      frames[f].removeAttribute('width');
    } else if (where && charts.test(where)) {
      var tall = +frames[f].getAttribute('data-office-height');
      frames[f].setAttribute('src', where);
      frames[f].setAttribute('style', 'height:' + (tall > 60 ? tall : 420) + 'px');
      frames[f].className = 'office-chart';
    } else {
      frames[f].remove();
    }
  }

  // A video's poster, which its player also shows as a picture beside it:
  // once is enough.
  var videos = wrap.querySelectorAll('video'), posters = [];
  for (var v = 0; v < videos.length; v++) {
    if (videos[v].poster) posters.push(videos[v].poster);
  }
  var stills = wrap.querySelectorAll('img');
  for (var t = 0; t < stills.length; t++) {
    if (posters.indexOf(stills[t].src) >= 0 && !stills[t].closest('video')) stills[t].remove();
  }

  // A video its player fed from the page itself, through a blob: address,
  // has nothing to play once that player is gone. It plays from the plain
  // stream it names beside that, which WebKit plays on its own, with
  // controls and never by itself, and fetches nothing of until play is
  // pressed; with none, it is its poster; with no poster, it goes.
  for (var q = 0; q < videos.length; q++) {
    var video = videos[q], fed = /^blob:/.test(video.getAttribute('src') || ''), plain = '';
    var named = video.querySelectorAll('source');
    for (var m = 0; m < named.length; m++) {
      if (/^blob:/.test(named[m].getAttribute('src') || '')) fed = true;
      else if (!plain && /^https?:/.test(named[m].src)) plain = named[m].src;
    }
    if (!fed) continue;
    if (plain) {
      for (var r = 0; r < named.length; r++) named[r].remove();
      video.setAttribute('preload', 'metadata');
      video.setAttribute('src', plain);
      video.setAttribute('controls', '');
      video.setAttribute('playsinline', '');
      video.removeAttribute('autoplay');
      // Out of the player's box, which the page's stylesheet still sizes
      // for the player.
      var player = video.parentNode.closest('.video-js');
      if (player) player.parentNode.replaceChild(video, player);
    } else if (video.poster) {
      var still = document.createElement('img');
      still.setAttribute('src', video.poster);
      video.parentNode.replaceChild(still, video);
    } else {
      video.remove();
    }
  }

  // A picture with nothing behind it is a broken icon, which is worse than
  // no picture at all.
  var kept = wrap.querySelectorAll('img');
  for (var g = 0; g < kept.length; g++) {
    var src = kept[g].getAttribute('src') || '';
    if (!src || src.indexOf('data:image') === 0) kept[g].remove();
  }

  // A box whose content went (the figure a frame sat in, the one a
  // picture with nothing behind it left) goes too, rather than stay as
  // an empty band.
  var boxes = wrap.querySelectorAll('figure, picture, div, section, p');
  for (var e = boxes.length - 1; e >= 0; e--) {
    if (!boxes[e].textContent.trim() &&
        !boxes[e].querySelector('img, video, audio, iframe, svg, canvas, table')) boxes[e].remove();
  }

  // The article's own heading goes when it only says the title again,
  // which the reader puts on top.
  var own = wrap.querySelector('h1');
  if (own && own.textContent.replace(/\s+/g, ' ').trim().toLowerCase() ===
      title.replace(/\s+/g, ' ').toLowerCase()) own.remove();

  present(wrap, title, location.host.replace(/^www\./, ''), sheet);
  return 'read';
