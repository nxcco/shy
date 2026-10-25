((key) => {
  const d = document.documentElement, v = document.compatMode === "BackCompat" ? document.body : d;
  if (!v) return null;
  if (key === "height") return d.scrollHeight;
  const own = d.getBoundingClientRect().width, gutter = innerWidth - v.clientWidth;
  if (own > v.clientWidth + 1) return own + gutter;
  const saved = d.getAttribute("style");
  d.style.setProperty("width", "min-content", "important");
  const narrowest = d.getBoundingClientRect().width;
  saved === null ? d.removeAttribute("style") : d.setAttribute("style", saved);
  return (narrowest >= 100 ? narrowest : Math.max(narrowest, d.scrollWidth)) + gutter;
})
