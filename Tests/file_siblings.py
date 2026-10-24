#!/usr/bin/env python3
"""A page on this Mac can't read the files beside it, in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/file_siblings.py`.
An .html opened from a folder (Downloads, say) gets that folder for its
pictures and styles, but its scripts reading another file there with fetch
or XMLHttpRequest, or the folder's own listing, is a cross-origin read, as
in Safari, Chrome and Firefox: each file is an origin of its own. Pages are
written into the test world's own folder; nothing is drawn.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("file-siblings")

# A 1×1 PNG, to show a picture beside the page still loads.
PIXEL = bytes.fromhex(
    "89504e470d0a1a0a0000000d4948445200000001000000010806000000"
    "1f15c4890000000d49444154789c6360f8cfc0f01f0005000201e2b1d8"
    "a70000000049454e44ae426082")


def text(tid):
    return sv.ev(tid, "document.body ? document.body.innerText : ''") or ""


def main():
    t = sv.T()
    try:
        sv.setup()
        root = Path(sv.SUPPORT) / "files"
        (root / "sub").mkdir(parents=True, exist_ok=True)
        (root / "secret.txt").write_text("SIBLING SECRET")
        (root / "sub" / "deeper.txt").write_text("DEEPER SECRET")
        (root / "pixel.png").write_bytes(PIXEL)
        (root / "style.css").write_text("#styled { color: rgb(1, 2, 3); }")
        poc = root / "poc.html"
        poc.write_text("""<!doctype html><title>poc</title>
<link rel=stylesheet href="style.css">
<p id=styled>styled</p><img id=pic src="pixel.png">
<pre id=fetch>waiting</pre><pre id=xhr>waiting</pre><pre id=deep>waiting</pre>
<pre id=list>waiting</pre><pre id=self>waiting</pre>
<script>
const put = (id, v) => document.getElementById(id).textContent = v;
const read = (id, path) => fetch(path).then(r => r.text()).then(v => put(id, 'READ ' + v), e => put(id, 'BLOCKED'));
read('fetch', 'secret.txt');
read('deep', 'sub/deeper.txt');
read('list', './');
read('self', 'poc.html');
try {
  const x = new XMLHttpRequest();
  x.open('GET', 'secret.txt');
  x.onload = () => put('xhr', 'READ ' + x.responseText);
  x.onerror = () => put('xhr', 'BLOCKED');
  x.send();
} catch (e) { put('xhr', 'BLOCKED'); }
</script>""")
        sv.launch()
        tid = sv.sp("open", url=poc.as_uri())["resultID"]
        time.sleep(2)
        shown = text(tid)
        t.ok("fetch can't read a file beside the page", "SIBLING SECRET" not in sv.ev(tid, "document.getElementById('fetch').textContent"), shown)
        t.ok("nor can XMLHttpRequest", "SIBLING SECRET" not in sv.ev(tid, "document.getElementById('xhr').textContent"), shown)
        t.ok("nor a file in a folder below", "DEEPER SECRET" not in sv.ev(tid, "document.getElementById('deep').textContent"), shown)
        t.ok("nor the folder's listing", not sv.ev(tid, "document.getElementById('list').textContent").startswith("READ"), shown)
        t.ok("a picture beside the page still shows",
             sv.ev(tid, "document.getElementById('pic').naturalWidth") == 1, shown)
        t.ok("and its stylesheet still applies",
             sv.ev(tid, "getComputedStyle(document.getElementById('styled')).color") == "rgb(1, 2, 3)", shown)
    finally:
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
