#!/usr/bin/env python3
"""Shy keeps what's yours to itself: the boundaries a page must not cross,
in one hidden probe.

Build first (`./build.sh debug`: only a debug build has the bench), then
`python3 Tests/security.py`, or `Tests/run.sh security`, which adds the
agent's boundaries (agent_mcp.py) and checks a release build has no bench.
Started hidden in a world of its own, quit, everything removed afterwards.
Two local servers stand in for two sites: 127.0.0.1 and localhost.
"""
import json
import sys
import tempfile
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("security")

CODE = "SECRET42"


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        port = self.server.server_port
        url = urlparse(self.path); page = url.path; q = parse_qs(url.query)
        headers = []
        if page == "/login":
            body = """<form id=f><input id=code type=password autocomplete=current-password autofocus><button>Sign in</button></form>
<script>document.getElementById('f').addEventListener('submit', async e => { e.preventDefault();
  await fetch('/api/login', {method: 'POST', body: document.getElementById('code').value}); document.body.innerHTML = '<h1>Signed in</h1>'; });</script>"""
        elif page == "/box":
            # A sign-in box filling its whole frame, so a click on the frame lands in it.
            body = "<input id=code type=password autocomplete=current-password style='position:fixed;inset:0;width:100%;height:100%'>"
        elif page == "/framer":
            body = f"<iframe id=go src='http://127.0.0.1:{q['port'][0]}/box' style='width:400px;height:200px;border:0'></iframe>"
        elif page == "/top":
            body = f"<script>addEventListener('message', e => window.got = e.data)</script><iframe src='http://localhost:{port}/set'></iframe>"
        elif page == "/set":
            body, headers = "<script>location = '/check'</script>", [("Set-Cookie", "framed=1; Path=/")]
        elif page == "/check":
            body = f"<script>parent.postMessage('sent:{self.headers.get('Cookie') or 'none'} read:' + (document.cookie || 'none'), '*')</script>"
        elif page == "/mine":
            body, headers = "set", [("Set-Cookie", f"{q['name'][0]}=1; Path=/")]
        elif page == "/cookies":
            body = f"<p id=c>{self.headers.get('Cookie') or 'none'}</p>"
        elif page == "/click":
            body = "<button id=go onclick=\"window.open('/opened-click')\">Open</button>"
        elif page == "/load":
            body = "<script>setTimeout(() => window.open('/opened-load'), 300)</script>"
        elif page == "/ads":
            body = f"<button id=go>Activate parent only</button><iframe src='http://localhost:{port}/ad'></iframe>"
        elif page == "/ad":
            body = "<script>setInterval(() => window.open('/opened-ad'), 100)</script>"
        else:
            body = f"<p>{page}"
        data = ("<!doctype html><meta charset=utf-8>" + body).encode()
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.send_header("Cache-Control", "no-store")
        for k, v in headers: self.send_header(k, v)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok")

    def log_message(self, *a): pass


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
PORT = srv.server_port
SITE = f"http://127.0.0.1:{PORT}"
OTHER = f"http://localhost:{PORT}"


def open_page(url, **f):
    id = sv.cmd({"do": "open", "url": url, **f})["id"]
    sv.cmd({"do": "wait", "id": id}); time.sleep(0.6)
    return id
def acc(**f): return sv.cmd({"do": "accounts", **f})
def opened(name): return [x for x in sv.cmd({"do": "tabs"})["tabs"] if urlparse(x["url"]).path == f"/opened-{name}"]
def text(id, selector): return sv.ev(id, f"(document.querySelector('{selector}') || {{}}).textContent || ''") or ""


def local_files(t):
    root = Path(sv.SUPPORT) / "files"
    (root / "sub").mkdir(parents=True, exist_ok=True)
    (root / "secret.txt").write_text("SIBLING SECRET")
    (root / "sub" / "deeper.txt").write_text("DEEPER SECRET")
    page = root / "page.html"
    page.write_text("""<!doctype html><pre id=fetch>waiting</pre><pre id=xhr>waiting</pre><pre id=deep>waiting</pre><pre id=list>waiting</pre>
<script>
const put = (id, v) => document.getElementById(id).textContent = v;
const read = (id, path) => fetch(path).then(r => r.text()).then(v => put(id, 'READ ' + v), () => put(id, 'BLOCKED'));
read('fetch', 'secret.txt'); read('deep', 'sub/deeper.txt'); read('list', './');
try { const x = new XMLHttpRequest(); x.open('GET', 'secret.txt');
  x.onload = () => put('xhr', 'READ ' + x.responseText); x.onerror = () => put('xhr', 'BLOCKED'); x.send(); }
catch (e) { put('xhr', 'BLOCKED'); }
</script>""")
    id = sv.sp("open", url=page.as_uri())["resultID"]; time.sleep(2)
    t.ok("a local page can't fetch a file beside it", "SIBLING" not in text(id, "#fetch"))
    t.ok("nor read it with XMLHttpRequest", "SIBLING" not in text(id, "#xhr"))
    t.ok("nor a file in a folder below", "DEEPER" not in text(id, "#deep"))
    t.ok("nor list its folder", not text(id, "#list").startswith("READ"))


def cookies(t):
    id = open_page(f"{SITE}/top")
    got = ""
    for _ in range(20):
        got = sv.ev(id, "window.got") or ""
        if got: break
        time.sleep(0.5)
    t.ok("a site framed in another gets no cookie of its own", got == "sent:none read:none", got)


def private_tabs(t):
    open_page(f"{SITE}/mine?name=yours")
    t.ok("(control) your tabs are sent your cookie", "yours=1" in text(open_page(f"{SITE}/cookies"), "#c"))
    shy = open_page(f"{SITE}/cookies", private=True)
    t.ok("a private tab is sent none of your cookies", text(shy, "#c") == "none", text(shy, "#c"))
    open_page(f"{SITE}/mine?name=private", private=True)
    mine = open_page(f"{SITE}/cookies")
    t.ok("and what a private tab sets never reaches your tabs", "private" not in text(mine, "#c"), text(mine, "#c"))


def popups(t):
    click = open_page(f"{SITE}/click")
    sv.cmd({"do": "tap", "id": click, "selector": "#go"}); time.sleep(2)
    t.ok("(control) a click on a button does open its window", len(opened("click")) == 1)
    open_page(f"{SITE}/load"); time.sleep(1)
    t.ok("a page can't open a window on its own", not opened("load"))
    ads = open_page(f"{SITE}/ads")
    sv.cmd({"do": "tap", "id": ads, "selector": "#go"}); time.sleep(3)
    t.ok("an ad frame can't spend the page's click on a window", not opened("ad"))


def front(url):
    """An ordinary tab, in front: the sign-in list hangs only from the tab you're on."""
    id = sv.sp("open", url=url)["resultID"]
    sv.sp("select", id=id); time.sleep(1.2)
    return id


def passwords(t):
    acc(forget=True)
    a = front(f"{SITE}/login")
    sv.ev(a, "var b = document.getElementById('code'); b.focus();"
             "Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(b, '%s');"
             "b.dispatchEvent(new Event('input', {bubbles: true})); document.querySelector('button').click(); true" % CODE)
    time.sleep(3); acc(keep=True)
    t.ok("a password is kept for 127.0.0.1", acc().get("kept") == 1)
    front(f"{SITE}/login")
    t.ok("its own site's sign-in box offers it", acc().get("shown") is True)
    front(f"{OTHER}/login")
    r = acc()
    t.ok("another site's sign-in box is offered nothing", not r.get("rows"), r)
    framer = front(f"{OTHER}/framer?port={PORT}")
    sv.cmd({"do": "tap", "id": framer, "selector": "#go"}); time.sleep(0.8)
    t.ok("(control) the click landed in the framed box", sv.ev(framer, "document.activeElement.tagName") == "IFRAME")
    r = acc()
    t.ok("its sign-in box framed in another site is offered nothing", not r.get("rows"), r)


def profiles(t):
    """An extension installed in one profile never reaches another's pages."""
    folder = Path(tempfile.mkdtemp(prefix="shy-marker-"))
    (folder / "manifest.json").write_text(json.dumps({
        "manifest_version": 3, "name": "Marker", "version": "1.0", "description": "Marks every page.",
        "host_permissions": ["http://*/*"],
        "content_scripts": [{"matches": ["http://*/*"], "js": ["mark.js"], "run_at": "document_start"}]}))
    (folder / "mark.js").write_text("document.documentElement.setAttribute('data-marked', 'yes')")
    marked = "document.documentElement.getAttribute('data-marked')"
    def installed(): return [e["name"] for e in sv.cmd({"do": "extensions"})["extensions"] if e.get("loaded")]
    sv.cmd({"do": "ext-folder", "path": str(folder), "yes": True})
    for _ in range(40):
        if "Marker" in installed(): break
        time.sleep(0.5)
    t.ok("(control) installed in Personal, it marks Personal's pages",
         sv.ev(open_page(f"{SITE}/personal"), marked) == "yes")
    sv.cmd({"do": "space", "action": "new", "name": "Work", "fresh": True})
    sv.cmd({"do": "space", "action": "go", "index": 2}); time.sleep(0.5)
    sv.cmd({"do": "space", "action": "profile", "name": "Work"}); time.sleep(0.5)
    t.ok("another profile starts with no extensions", installed() == [], installed())
    work = sv.sp("open", url=f"{SITE}/work")["resultID"]; time.sleep(1)
    t.ok("Personal's extension never reaches a page in another profile", sv.ev(work, marked) is None, sv.ev(work, marked))
    sv.cmd({"do": "space", "action": "go", "index": 1}); time.sleep(0.5)
    t.ok("and Personal still has it", "Marker" in installed(), installed())


def main():
    t = sv.T()
    try:
        sv.setup(); sv.launch()
        local_files(t)
        cookies(t)
        private_tabs(t)
        popups(t)
        passwords(t)
        profiles(t)
    finally:
        try: acc(forget=True)
        except Exception: pass
        srv.shutdown(); srv.server_close()
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
