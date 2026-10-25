const el = find(selector);
if (el === undefined) return 'not a selector: ' + selector;
if (!el) return 'nothing matches ' + selector;
el.scrollIntoView({ block: 'center', inline: 'nearest' });
el.focus();
if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
  if (el instanceof HTMLInputElement && el.type === 'file') return 'not a field to type into: ' + selector;
  const proto = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
  Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return 'ok';
}
if (el.isContentEditable) {
  document.execCommand('insertText', false, text);
  return 'ok';
}
return 'not a field: ' + selector;
