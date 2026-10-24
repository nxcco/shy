#!/usr/bin/env python3
"""A window closed and kept goes quiet (Browser.hush), in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/shut_window_quiet.py`.
The last window closed with Shy running is kept, tabs and all; what was
playing in it stops, can't start again while it is shut, and can once the
window is back.
"""
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("shut-window-quiet")

PAGE = b"""<!doctype html><title>Playing</title>
<canvas width=64 height=64></canvas><video muted playsinline autoplay></video>
<script>
const c = document.querySelector('canvas'), g = c.getContext('2d'); let n = 0;
setInterval(() => { g.fillStyle = 'hsl(' + (n++ * 10) + ',80%,50%)'; g.fillRect(0, 0, 64, 64); }, 30);
const v = document.querySelector('video'); v.srcObject = c.captureStream(30); v.play();
</script>"""


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(PAGE)))
        self.end_headers()
        self.wfile.write(PAGE)

    def log_message(self, *a):
        pass


def paused(id):
    return sv.cmd({"do": "eval", "id": id, "js": "document.querySelector('video').paused"})["value"]


def main():
    t = sv.T()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        sv.setup(); sv.launch()
        tab = sv.cmd({"do": "open", "url": f"http://127.0.0.1:{srv.server_port}/"})["id"]
        sv.cmd({"do": "wait", "id": tab}); time.sleep(1)
        t.ok("the video plays", paused(tab) is False, paused(tab))

        sv.cmd({"do": "shut", "on": True}); time.sleep(0.8)
        t.ok("shut, it stops", paused(tab) is True, paused(tab))
        sv.cmd({"do": "eval", "id": tab, "js": "document.querySelector('video').play().catch(() => {}); true"}); time.sleep(0.8)
        t.ok("and the page can't start it again", paused(tab) is True, paused(tab))

        sv.cmd({"do": "shut", "on": False}); time.sleep(0.3)
        sv.cmd({"do": "eval", "id": tab, "js": "document.querySelector('video').play().catch(() => {}); true"}); time.sleep(0.8)
        t.ok("back, it can play again", paused(tab) is False, paused(tab))
    finally:
        t.done(); sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
