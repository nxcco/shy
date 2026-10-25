#!/usr/bin/env python3
"""Shy works: the everyday journeys, end to end, in one hidden probe.

Build first (`./build.sh debug`: only a debug build has the bench), then
`python3 Tests/smoke.py`, or `Tests/run.sh smoke`. Started hidden in a
world of its own, driven through the bench, quit; everything it made is
removed afterwards. Pages come from a server here; nothing leaves the Mac.
"""
import json
import sys
import threading
import time
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("smoke")

CODE = "SMOKE42"
LOGIN = """<!doctype html><title>login</title>
<form id=f><input id=code type=password autocomplete=current-password autofocus><button>Sign in</button></form>
<script>
document.getElementById('f').addEventListener('submit', async e => {
  e.preventDefault();
  const r = await fetch('/api/login', {method: 'POST', body: document.getElementById('code').value});
  if (r.ok) { history.pushState({}, '', '/'); document.body.innerHTML = '<h1>Signed in</h1>'; document.title = 'signed in'; }
});
</script>"""


class H(BaseHTTPRequestHandler):
    def send(self, code, body):
        body = body.encode()
        self.send_response(code); self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

    def do_GET(self):
        name = self.path.strip("/")
        asked.append(name)
        # A page that never arrives in time: the load is under way, nothing commits.
        if name == "stall": time.sleep(8)
        self.send(200, LOGIN if name == "login" else f"<!doctype html><title>{name}</title><p>{name}")

    def do_POST(self):
        sent = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        self.send(200 if sent == CODE else 401, json.dumps({"ok": sent == CODE}))

    def log_message(self, *a): pass


asked = []
srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{srv.server_port}"


def st(): return sv.sp("state")
def tab(id): return next(x for x in st()["tabs"] if x["id"] == id)
def last(url): return url.rstrip("/").rsplit("/", 1)[-1]
def open_page(name):
    """An ordinary tab, in front: the sign-in list hangs only from the tab you're on."""
    id = sv.sp("open", url=f"{BASE}/{name}")["resultID"]
    sv.sp("select", id=id); sv.cmd({"do": "wait", "id": id}); time.sleep(1.2)
    return id
def go(id, name):
    sv.cmd({"do": "go", "id": id, "url": f"{BASE}/{name}"}); sv.cmd({"do": "wait", "id": id}); time.sleep(0.4)
def pin(id, **f): return sv.cmd({"do": "pin", "id": id, **f})
def acc(**f): return sv.cmd({"do": "accounts", **f})
def sign_in(id, code):
    sv.ev(id, "var b = document.getElementById('code'); b.focus();"
              "Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(b, '%s');"
              "b.dispatchEvent(new Event('input', {bubbles: true})); true" % code)
    sv.ev(id, "document.activeElement.blur(); document.querySelector('button').click(); true")
    time.sleep(3)


def tabs_and_pages(t):
    a = open_page("first")
    t.ok("a page opens and shows its words", sv.ev(a, "document.body.innerText") == "first")
    b = open_page("second")
    count = len(st()["tabs"])
    sv.sp("close", id=b)
    t.ok("a tab closes", len(st()["tabs"]) == count - 1 and all(x["id"] != b for x in st()["tabs"]))
    sv.cmd({"do": "press", "code": 43, "chars": ",", "mods": ["cmd"]}); time.sleep(0.6)
    t.ok("⌘, opens Settings", sv.cmd({"do": "probe"}).get("settings") is True)
    return a


def pins(t, a):
    r = pin(a)
    t.ok("a tab pins", r.get("pin") and last(r["home"]) == "first", r)
    go(a, "elsewhere")
    sv.sp("close", id=a)
    t.ok("⌘W on a pin that wandered puts it back home", last(tab(a)["url"]) == "first", tab(a)["url"])
    sv.sp("select", id=a); sv.cmd({"do": "wait", "id": a})
    go(a, "newhome")
    r = pin(a, repin=True)
    t.ok("Make This the Pinned Page moves its home", last(r["home"]) == "newhome", r)


def passwords(t):
    r = acc(forget=True)
    t.ok("this world keeps no passwords to begin with", r.get("kept") == 0, r)
    a = open_page("login")
    sign_in(a, CODE)
    t.ok("a sign-in is offered a place in the keychain", (acc().get("offer") or {}).get("host") == "127.0.0.1")
    t.ok("and kept once said yes to", acc(keep=True).get("kept") == 1)
    b = open_page("login")
    r = acc()
    t.ok("the sign-in box offers it", r.get("shown") and len(r.get("rows") or []) == 1, r)
    time.sleep(0.6); acc(pick=0); time.sleep(0.6)
    t.ok("a pick fills the box", sv.ev(b, "document.getElementById('code').value") == CODE)


def developer(t):
    a = open_page("deep/page?q=1#here")
    sv.cmd({"do": "ui", "developer": True}); time.sleep(0.6)
    r = sv.cmd({"do": "probe"})
    t.ok("Developer Mode puts its bar under the page, with the whole address",
         r.get("developer") is True and r.get("developerBar") == f"{BASE}/deep/page?q=1#here", r.get("developerBar"))
    # The page sends itself to another site that never arrives (localhost
    # is another host than 127.0.0.1): the tab is on its way there, the bar
    # stays with the page on screen.
    sv.ev(a, f"location.href = 'http://localhost:{srv.server_port}/stall'; true"); time.sleep(1.5)
    bar = sv.cmd({"do": "probe"}).get("developerBar")
    t.ok("a load under way to another site has started",
         "stall" in asked and tab(a)["url"] == f"http://localhost:{srv.server_port}/stall", (asked[-3:], tab(a)["url"]))
    t.ok("and the bar still says the page on screen", bar == f"{BASE}/deep/page?q=1#here", bar)
    host = BASE.replace("http://", "")
    go(a, "plain"); sv.ev(a, f"location.href = 'http://someone:secret@{host}/signed?x=1#y'; true")
    sv.cmd({"do": "wait", "id": a}); time.sleep(1)
    bar = sv.cmd({"do": "probe"}).get("developerBar") or ""
    t.ok("an address with a password in it shows without it",
         "secret" not in bar and "someone" not in bar and bar.endswith(f"{host}/signed?x=1#y"), bar)
    sv.cmd({"do": "ui", "developer": False}); time.sleep(0.6)
    t.ok("and turned off, the bar goes", sv.cmd({"do": "probe"}).get("developerBar") is None)
    sv.sp("close", id=a)


def restore(t):
    sv.sp("save"); sv.quit(); sv.launch(); time.sleep(0.5)
    pinned = [x for x in st()["tabs"] if x["id"] in st()["pins"]]
    t.ok("after quitting and opening again, the pin is back at its new home",
         len(pinned) == 1 and last(pinned[0]["url"]) == "newhome", [x["url"] for x in pinned])


def main():
    t = sv.T()
    try:
        sv.setup(**{"pins.home": True}); sv.launch()
        a = tabs_and_pages(t)
        pins(t, a)
        passwords(t)
        developer(t)
        restore(t)
    finally:
        try: acc(forget=True)
        except Exception: pass
        srv.shutdown(); srv.server_close()
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
