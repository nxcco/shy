#!/usr/bin/env python3
"""The harness every probe drives Shy through: a hidden Shy in a world of
its own, spoken to over the bench's socket, and everything it made removed
afterwards.

A probe calls use(name) for its world, setup(), launch(), then cmd()/sp()/
ev() to drive it, T() to count checks, and finish() at the end. Build first
(`./build.sh debug`: only a debug build has the bench). Nothing here makes,
shows or brings forward a window, and it never touches the Shy you use.
"""

import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = str(ROOT / "build" / "Shy.app")
HOME = os.path.expanduser("~")
def use(name):
    """This checkout's own world for a suite: the name, then a tag made from
    the checkout's path. Two checkouts testing at once (a worktree beside
    the main one, another session's) share no socket, settings or folder,
    so a run in one is never answered by the other's build. A suite that
    wants a world apart from the split suite's calls it with its own name."""
    global W, SUPPORT, SUITE, SOCK
    W = f"{name}-{hashlib.sha1(str(ROOT).encode()).hexdigest()[:8]}"
    SUPPORT = f"{HOME}/Library/Application Support/Shy ({W})"
    SUITE = f"io.github.nxcco.shy.test.{W}"
    SOCK = f"{SUPPORT}/bench.sock"
use("split-tests")
# Only ever a probe of this world: the one this run started, or one a run
# before left holding this world's socket. Never the Shy someone is using,
# even one running from this very build (see running()).
started = set()
def running(): return set(subprocess.run(["pgrep", "-f", APP + "/Contents/MacOS"], capture_output=True, text=True).stdout.split())
def holding(): return set(subprocess.run(["lsof", "-t", "--", SOCK], capture_output=True, text=True).stdout.split()) if os.path.exists(SOCK) else set()
def pids(): return sorted((started & running()) | (holding() & running()))
WEBKIT = f"{HOME}/Library/WebKit/io.github.nxcco.shy"
def stores():
    """The WebKit stores this world's runs made, where WebKit keeps them and
    named as the app names them (Store.probeStore, Spaces.store): its
    websites', its extensions', and one for each of its spaces with sign-ins
    of its own, read from its own list of spaces and of spaces it was still
    erasing. Only those: a real Shy's spaces keep their stores beside
    them, and a store is never guessed at by its look."""
    h = 2166136261
    for byte in W.encode(): h = ((h ^ byte) * 16777619) & 0xFFFFFFFF
    probe = lambda kind: f"5E4C{h >> 16:04X}-{h & 0xFFFF:04X}-4000-8000-{kind:012X}"
    found = [f"{WEBKIT}/WebsiteDataStore/{probe(1).lower()}", f"{WEBKIT}/WebExtensions/{probe(2)}"]
    # A space's or profile's store is named from the world and its id
    # (Store.webKitID); the ones still being erased are already.
    def named(id):
        digest = bytearray(hashlib.sha256(f"shy-store:{W}:{str(id).upper()}".encode()).digest()[:16])
        digest[6] = (digest[6] & 0x0F) | 0x40
        digest[8] = (digest[8] & 0x3F) | 0x80
        return str(uuid.UUID(bytes=bytes(digest)))
    ids = []
    try:
        ids += [named(uuid.UUID(space["id"])) for space in json.load(open(f"{SUPPORT}/spaces.json"))
                if space.get("sharesSignIns") is not True and str(uuid.UUID(space["id"])) != FIRST_SPACE]
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        pass
    try:
        ids += [named(uuid.UUID(profile["id"])) for profile in json.load(open(f"{SUPPORT}/profiles.json"))]
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        pass
    erasing = subprocess.run(["defaults", "read", SUITE, "spaces.erasing"], capture_output=True, text=True).stdout
    ids += re.findall(r"[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}", erasing)
    for id in ids:
        try: id = str(uuid.UUID(id))
        except (ValueError, AttributeError, TypeError): continue
        found.append(f"{WEBKIT}/WebsiteDataStore/{id}")
    return found
# The real Shy's folder, beside whose stores these are removed.
REAL = f"{HOME}/Library/Application Support/Shy"
FIRST_SPACE = "00000000-0000-0000-0000-000000000001"
def guarded():
    """Store ids no wipe removes, whatever stores() names: every space of the
    real Shy's own list, and the first space's fixed id. A wrong hash, or
    a test world's list holding a real space's id, then never reaches a real
    space's sign-ins: rm -rf runs in the folder where those live."""
    ids = {FIRST_SPACE}
    try:
        ids |= {str(uuid.UUID(space["id"])) for space in json.load(open(f"{REAL}/spaces.json"))}
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        pass
    return ids
def wipe():
    # The stores first: which spaces had one is in the folder and settings
    # about to go.
    keep = guarded()
    for path in stores():
        if os.path.basename(path).lower() in keep:
            print(f"wipe: not removing {path}: the real Shy's spaces use that id", file=sys.stderr)
            continue
        subprocess.run(["rm", "-rf", path])
    subprocess.run(["rm", "-rf", SUPPORT]); subprocess.run(["defaults", "delete", SUITE], capture_output=True)
def probe(pid):
    names = subprocess.run(["lsof", "-a", "-U", "-p", pid, "-Fn"], capture_output=True, text=True).stdout
    return any(n.startswith("n") and "/Shy (" in n and n.endswith("/bench.sock") for n in names.splitlines())
def main_checkout():
    git = lambda *a: subprocess.run(["git", "-C", str(ROOT), "rev-parse", *a], capture_output=True, text=True).stdout.strip()
    return git("--git-dir") != "" and Path(git("--absolute-git-dir")) == Path(ROOT, git("--git-common-dir")).resolve()
# Someone's own Shy running from this build: no probe starts beside it
# from here. Run the tests from a worktree of your own instead.
if main_checkout() and any(not probe(p) for p in running()):
    sys.exit(f"{APP} is in use by a Shy that isn't a probe. Run the tests from a worktree (git worktree add).")
def setup(**prefs):
    for p in pids(): subprocess.run(["kill", p])
    started.clear()
    time.sleep(1); wipe()
    for k in ["bench", "welcomed"]: subprocess.run(["defaults", "write", SUITE, k, "-bool", "true"])
    for k, v in prefs.items(): subprocess.run(["defaults", "write", SUITE, k, "-bool", "true" if v else "false"])
def launch():
    # Only a debug build has the bench: a release build leaves it out.
    binary = Path(APP) / "Contents" / "MacOS" / "Shy"
    if b"bench.sock" not in binary.read_bytes():
        sys.exit(f"{APP} is a release build, which has no bench: build it with `./build.sh debug` first")
    if os.path.exists(SOCK): os.remove(SOCK)
    before = running()
    subprocess.run(["open", "-n", "-g", "-j", "--env", f"SHY_PROBE={W}", APP])
    for _ in range(150):
        if os.path.exists(SOCK): break
        time.sleep(0.1)
    time.sleep(2)
    # Whatever came up from this build just now and holds this world's socket.
    started.update((running() - before) & holding())
def quit():
    try: cmd({"do": "quit"})
    except Exception: pass
    for _ in range(30):
        if not pids(): break
        time.sleep(0.2)
    for p in pids(): subprocess.run(["kill", p])
def cmd(req):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as c:
        c.settimeout(30); c.connect(f"{SUPPORT}/bench.sock"); c.sendall(json.dumps(req).encode() + b"\n")
        data = b""
        while True:
            ch = c.recv(65536)
            if not ch: break
            data += ch
    a = json.loads(data.split(b"\n", 1)[0] or b"{}")
    if "error" in a: raise RuntimeError(f"{req}: {a['error']}")
    return a
def sp(action, **f): return cmd({"do": "split", "action": action, **f})
def ev(id, js): return cmd({"do": "eval", "id": id, "js": js}).get("value")
class T:
    def __init__(self): self.passed = self.failed = 0
    def ok(self, name, cond, extra=""):
        if cond: self.passed += 1; print("  ok  ", name)
        else: self.failed += 1; print("  FAIL", name, extra)
    def done(self):
        print(f"{self.passed} passed, {self.failed} failed")
def finish():
    quit(); time.sleep(0.5); wipe()
