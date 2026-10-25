(function () {
  // The engine may have put the video in its own floating window as well —
  // some players ask for that themselves. Leaving one and not the other
  // leaves you with two.
  try {
    var out = document.querySelector('video[data-office-float]')
      || document.querySelector('video');
    if (out) {
      if (out.webkitPresentationMode === 'picture-in-picture') {
        out.webkitSetPresentationMode('inline');
      }
      if (document.pictureInPictureElement && document.exitPictureInPicture) {
        document.exitPictureInPicture();
      }
    }
  } catch (e) {}

  var root = document.documentElement;
  var landing = window.__officeFloatLanding = {};
  var wait = window.__officeFloatWait = { settled: false, landing: true };
  function put() {
    // Floated again in the meantime: that is the float's now.
    if (window.__officeFloatLanding !== landing) return;
    window.__officeFloatLanding = null;
    clearInterval(window.__officeFloatWatch);
    window.__officeFloatWatch = null;
    root.classList.remove('office-floating');
    var sheet = document.getElementById('office-float');
    if (sheet) sheet.textContent = '';
    var video = document.querySelector('[data-office-float]');
    if (video) video.removeAttribute('data-office-float');
    settle(video);
    reopen();
  }
  // Twitch, in its Studio mode, folds its chat away in a page as narrow as
  // the little window, and opens it again only when asked: back in its
  // tab, the chat stayed shut. Asked here, if it was open as the video
  // went out, once the page is the tab's size again.
  function reopen() {
    var home = window.__officeFloatHome;
    if (!home || !home.chat || root.classList.contains('office-floating')) return;
    if (innerWidth === wide && innerHeight === high) {
      // Put back by the clock, its tab not in front: once it is.
      addEventListener('resize', function again() {
        removeEventListener('resize', again);
        reopen();
      });
      return;
    }
    var shut = document.querySelector('.right-column--collapsed [data-a-target="right-column__toggle-collapse-btn"]');
    if (shut) shut.click();
  }
  // The tab covers the page with a picture of it as it was left, until
  // it is that again (Browser.land). Put back, the page still has the
  // player at the size it was given in the little window, and a player
  // such as YouTube's measures again on a clock of its own, half a
  // second later. So: settled once the video is back where it was, at
  // the size it was, in a page of the size it was, looked at as each
  // frame is drawn. A window resized meanwhile has no such place to go
  // back to, and settles once the video has kept still for 0.3 s.
  function settle(video) {
    var home = window.__officeFloatHome, began = Date.now(), last = null, still = 0;
    function near(a, b) {
      for (var i = 0; i < 4; i++) if (Math.abs(a[i] - b[i]) > 2) return false;
      return true;
    }
    function done() { wait.settled = true; }
    (function frame() {
      if (window.__officeFloatWait !== wait) return;
      var v = video && video.isConnected ? video : document.querySelector('video');
      if (!home || !v || Date.now() - began > 3000) return done();
      var r = v.getBoundingClientRect(), box = [r.left + scrollX, r.top + scrollY, r.width, r.height];
      if (innerWidth === home.wide && innerHeight === home.high) {
        if (near(box, home.box)) return done();
      } else {
        still = last && near(box, last) ? still || Date.now() : 0;
        last = box;
        if (still && Date.now() - still >= 300) return done();
      }
      requestAnimationFrame(frame);
    })();
  }
  // Each frame until the page is laid out at another size than the
  // little window's — the tab's — and its player has had that frame's
  // resize to fit the video to it. A page not drawn, its tab no longer
  // the one in front, is put back by the clock.
  var wide = innerWidth, high = innerHeight, began = Date.now();
  (function frame() {
    if (window.__officeFloatLanding !== landing) return;
    if (innerWidth !== wide || innerHeight !== high || Date.now() - began > 400) return put();
    requestAnimationFrame(frame);
  })();
  setTimeout(put, 1000);
  return 'landing';
})();
