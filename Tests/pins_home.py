#!/usr/bin/env python3
"""Settings › Tabs › Pins go back home: a pin closed with ⌘W, or open when
Shy quits, comes back at the page it was pinned at, as in Arc.

Build first (`./build.sh`), then `python3 Tests/pins_home.py`. It uses the
split suite's harness: started hidden, no window made or shown, everything
removed afterwards.
"""
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_view as sv  # noqa: E402

sv.use("pins-home")

t = sv.T()
def tab(st, id): return next(x for x in st["tabs"] if x["id"] == id)
def last(url): return url.rsplit("/", 1)[-1]
def pinned(st): return [last(tab(st, id)["url"]) for id in st["pins"]]
def pin(id, **f): return sv.cmd({"do": "pin", "id": id, **f})
def relaunch(on):
    sv.sp("save"); sv.quit()
    subprocess.run(["defaults", "write", sv.SUITE, "pins.home", "-bool", "true" if on else "false"])
    sv.launch(); time.sleep(0.5)
    return sv.sp("state")
def wander(id, to):
    sv.cmd({"do": "go", "id": id, "url": f"{sv.BASE}/{to}"}); sv.cmd({"do": "wait", "id": id}); time.sleep(0.3)

try:
    sv.setup(sidebar=True); sv.launch()
    a = sv.page("a"); sv.page("b")
    pin(a)

    # Arc's pin, always: taken elsewhere and put down, it goes home.
    wander(a, "elsewhere")
    sv.sp("close", id=a)
    st = relaunch(True)
    t.ok("on: after a restart the pin is at the page it was pinned at", pinned(st) == ["a"], pinned(st))
    a = st["pins"][0]
    sv.sp("select", id=a); sv.cmd({"do": "wait", "id": a})
    wander(a, "away")
    t.ok("on: the pin goes where it is taken", last(tab(sv.sp("state"), a)["url"]) == "away")
    sv.sp("close", id=a); st = sv.sp("state")
    t.ok("on: ⌘W puts it down at its pinned page", last(tab(st, a)["url"]) == "a", tab(st, a)["url"])
    sv.sp("save")
    entry = next(x for x in sv.session()["tabs"] if x.get("pin"))
    t.ok("on: the session holds it at its pinned page", last(entry["url"]) == "a" and last(entry["home"]) == "a", entry)
    sv.sp("select", id=a); sv.cmd({"do": "wait", "id": a}); time.sleep(0.3)
    t.ok("on: picked again, it opens its pinned page", last(tab(sv.sp("state"), a)["url"]) == "a", tab(sv.sp("state"), a)["url"])

    # Taken somewhere and left open when Shy quits.
    wander(a, "later")
    st = relaunch(True)
    t.ok("on: left elsewhere at quit, it opens again at home", pinned(st) == ["a"], pinned(st))

    # Made This the Pinned Page: the page it wandered to is its home now.
    a = st["pins"][0]
    sv.sp("select", id=a); sv.cmd({"do": "wait", "id": a})
    t.ok("at home, there is nothing to repin", last(pin(a, repin=True)["home"]) == "a")
    wander(a, "newhome")
    t.ok("repinned, its home is the page it is on", last(pin(a, repin=True)["home"]) == "newhome")
    wander(a, "away")
    sv.sp("close", id=a); st = sv.sp("state")
    t.ok("repinned: ⌘W puts it down at the new page", last(tab(st, a)["url"]) == "newhome", tab(st, a)["url"])
    st = relaunch(True)
    t.ok("repinned: after a restart it opens at the new page", pinned(st) == ["newhome"], pinned(st))
finally:
    t.done(); sv.finish()
sys.exit(1 if t.failed else 0)
