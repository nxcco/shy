#!/usr/bin/env python3
"""Claude's pages through shy-mcp (Agent.swift), in a hidden probe.

Build first (`./build.sh debug`), then `python3 Tests/agent_mcp.py`. Speaks
MCP to build/Shy.app/Contents/MacOS/shy-mcp over its standard input
and output, pointed at the test world's agent.sock, against pages served
here. Checks what Claude can do — open, read, picture, click, type, close —
and what a page can't: a file on this Mac, Shy's own pages, a window of
its own, a download, and the tabs that are yours.
"""
import base64
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("agent-mcp")
HELPER = str(Path(sv.APP) / "Contents" / "MacOS" / "shy-mcp")
seen = []


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        seen.append(self.path)
        if self.path == "/form":
            body = b"""<!doctype html><title>Form</title>
<p id=out>untouched</p>
<input id=name oninput="document.getElementById('out').textContent = 'typed ' + this.value">
<button onclick="document.getElementById('out').textContent = 'clicked'">Press me</button>
<a id=away href="/second">Second page</a>
<a id=blank target=_blank href="/second">Elsewhere</a>
<button id=pop onclick="window.open('/second', 'x', 'width=300,height=300')">Pop</button>
<a id=file href="file:///etc/hosts">A file</a>
<a id=get href="/download">Download</a>"""
            kind = "text/html"
        elif self.path == "/second":
            body, kind = b"<!doctype html><title>Second</title>SECOND PAGE", "text/html"
        elif self.path == "/download":
            body, kind = b"\x00\x01binary", "application/octet-stream"
        else:
            body, kind = b"<!doctype html><title>Hello</title>HELLO AGENT", "text/html"
        self.send_response(200)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


class MCP:
    def __init__(self):
        env = {"SHY_AGENT_SOCKET": f"{sv.SUPPORT}/agent.sock", "PATH": "/usr/bin:/bin"}
        self.p = subprocess.Popen([HELPER], stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env, text=True, bufsize=1)
        self.n = 0

    def send(self, method, params=None, notify=False):
        message = {"jsonrpc": "2.0", "method": method, "params": params or {}}
        if not notify:
            self.n += 1
            message["id"] = self.n
        self.p.stdin.write(json.dumps(message) + "\n")
        self.p.stdin.flush()
        return None if notify else json.loads(self.p.stdout.readline())

    def tool(self, name, **args):
        return self.send("tools/call", {"name": name, "arguments": args})["result"]

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)


def words(result):
    return "\n".join(c.get("text", "") for c in result["content"])


def page_id(result):
    for line in words(result).splitlines():
        if line.startswith("tab_id: "):
            return line[8:]
    return ""


def main():
    t = sv.T()
    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_port}"
    mcp = None
    try:
        sv.setup(agent=True)
        sv.launch()
        before = [x["id"] for x in sv.sp("state")["tabs"]]
        mcp = MCP()
        init = mcp.send("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "probe", "version": "1"}})
        t.ok("initialize answers with tools", "tools" in init["result"]["capabilities"], init)
        mcp.send("notifications/initialized", notify=True)
        names = [x["name"] for x in mcp.send("tools/list")["result"]["tools"]]
        t.ok("eight tools", names == ["shy_open", "shy_text", "shy_shot", "shy_click", "shy_type", "shy_go", "shy_wait", "shy_close"], names)

        opened = mcp.tool("shy_open", url=f"{base}/hello")
        pid = page_id(opened)
        t.ok("open gives an id and the title", pid and "Hello" in words(opened), opened)
        t.ok("text reads the page", "HELLO AGENT" in words(mcp.tool("shy_text", tab_id=pid)))
        shot = mcp.tool("shy_shot", tab_id=pid)
        png = shot["content"][0]
        t.ok("shot is a PNG", png.get("type") == "image" and base64.b64decode(png["data"])[:8] == b"\x89PNG\r\n\x1a\n", png.get("type"))
        t.ok("none of your tabs changed", [x["id"] for x in sv.sp("state")["tabs"]] == before)

        form = page_id(mcp.tool("shy_open", url=f"{base}/form"))
        mcp.tool("shy_type", tab_id=form, selector="#name", text="Ada")
        t.ok("type fires the page's input event", "typed Ada" in words(mcp.tool("shy_text", tab_id=form)))
        mcp.tool("shy_click", tab_id=form, selector="text=Press me")
        t.ok("click by words", "clicked" in words(mcp.tool("shy_text", tab_id=form)))
        miss = mcp.tool("shy_click", tab_id=form, selector="#nothing")
        t.ok("a selector matching nothing is an error", miss.get("isError") is True, miss)

        for target in ["file:///etc/hosts", "shy://settings", "javascript:alert(1)", "data:text/html,hi", "ftp://example.com/"]:
            r = mcp.tool("shy_open", url=target)
            t.ok(f"open refuses {target.split(':')[0]}:", r.get("isError") is True, r)
            r = mcp.tool("shy_go", tab_id=form, url=target)
            t.ok(f"go refuses {target.split(':')[0]}:", r.get("isError") is True, r)

        mcp.tool("shy_click", tab_id=form, selector="#file")
        time.sleep(1)
        t.ok("a page's link to a file goes nowhere", "Form" in words(mcp.tool("shy_text", tab_id=form)))
        mcp.tool("shy_click", tab_id=form, selector="#pop")
        time.sleep(1)
        t.ok("a page's pop-up leaves the page where it was", "Form" in words(mcp.tool("shy_text", tab_id=form)))
        seen.clear()
        mcp.tool("shy_click", tab_id=form, selector="#get")
        time.sleep(1.5)
        downloads = list((Path(sv.SUPPORT) / "Downloads").glob("*")) if (Path(sv.SUPPORT) / "Downloads").exists() else []
        t.ok("a download is refused", not downloads, downloads)

        mcp.tool("shy_click", tab_id=form, selector="#blank")
        mcp.tool("shy_wait", tab_id=form, seconds=5)
        t.ok("a link for a new window opens in the same page", "SECOND PAGE" in words(mcp.tool("shy_text", tab_id=form)))

        # Two open: six more fit. One more would mean the pop-up made a page.
        opened = [page_id(mcp.tool("shy_open", url=f"{base}/hello")) for _ in range(8)]
        t.ok("at most eight pages, and the pop-up made none", sum(1 for x in opened if x) == 6, opened)
        closed = mcp.tool("shy_close", tab_id="all")
        t.ok("close all", "Closed 8" in words(closed), closed)
        gone = mcp.tool("shy_text", tab_id=pid)
        t.ok("a closed page is gone", gone.get("isError") is True, gone)

    finally:
        if mcp:
            mcp.close()
        t.done()
        sv.finish()
    sys.exit(1 if t.failed else 0)


if __name__ == "__main__":
    main()
