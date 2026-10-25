const el = find(selector);
if (el === undefined) return 'not a selector: ' + selector;
if (!el) return 'nothing matches ' + selector;
el.scrollIntoView({ block: 'center', inline: 'nearest' });
// A link for a new window goes in this page instead: a page here
// opens no windows, and WebKit refuses one a script's click asks
// for before Shy is asked. Not when the page took the click itself.
const link = el.closest('a[href]');
const away = link && /^https?:$/.test(link.protocol) && link.target && !['_self', '_parent', '_top'].includes(link.target);
if (!away) { el.click(); return 'ok'; }
let taken = false;
const watch = e => { taken = e.defaultPrevented; };
window.addEventListener('click', watch);
el.click();
window.removeEventListener('click', watch);
if (!taken) location.assign(link.href);
return 'ok';
