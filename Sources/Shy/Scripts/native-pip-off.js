(function () {
  var videos = document.querySelectorAll('video'), out = false;
  for (var i = 0; i < videos.length; i++) {
    if (videos[i].webkitPresentationMode === 'picture-in-picture') {
      try { videos[i].webkitSetPresentationMode('inline'); out = true; } catch (e) {}
    }
  }
  return out ? 'out' : 'none';
})();
