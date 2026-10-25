() => {
  const d = document.documentElement, v = document.compatMode === "BackCompat" ? document.body : d;
  if (!v) return null;
  const m = window.__shySizing || (window.__shySizing = {});
  const saved = d.getAttribute("style");
  const back = () => saved === null ? d.removeAttribute("style") : d.setAttribute("style", saved);
  const box = d.getBoundingClientRect();
  // A width the page sets for itself shows as one the view doesn't
  // have, excluding its scrollbar; one equal to the view is either
  // filling it or the width it was given last time, remembered.
  let w;
  if (Math.abs(box.width - v.clientWidth) > 1) w = m.w = box.width;
  else if (m.w && Math.abs(m.w - v.clientWidth) <= 1) w = m.w;
  else {
    d.style.setProperty("width", "min-content", "important");
    const narrowest = d.getBoundingClientRect().width;
    back();
    w = narrowest >= 100 ? narrowest : Math.max(narrowest, d.scrollWidth);
  }
  const gutter = innerWidth - v.clientWidth;
  w = Math.min(800, Math.max(25, Math.ceil(w + gutter)));
  d.style.setProperty("width", (w - gutter) + "px", "important");
  let h = d.getBoundingClientRect().height;
  if (Math.abs(h - innerHeight) > 1) m.h = h;
  else if (m.h && Math.abs(m.h - innerHeight) <= 1) h = m.h;
  else {
    d.style.setProperty("height", "auto", "important");
    d.style.setProperty("min-height", "0", "important");
    h = d.getBoundingClientRect().height;
  }
  back();
  return [w, Math.min(600, Math.max(25, Math.ceil(h + innerHeight - v.clientHeight)))];
}
