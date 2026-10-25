#!/bin/bash
# The test suite, in one place:
#
#   Tests/run.sh unit       the Swift tests (swift test)
#   Tests/run.sh smoke      the everyday journeys, end to end (smoke.py)
#   Tests/run.sh security   the boundaries a page must not cross (security.py),
#                           the agent's (agent_mcp.py), and that a release
#                           build has no bench in it
#   Tests/run.sh            all three
#
# Smoke and security drive a debug build, the only kind with the bench; the
# release check builds release last, so build/Shy.app is a release build
# afterwards. Green is the only good answer: anything else exits 1.
set -uo pipefail
cd "$(dirname "$0")/.."

what="${1:-all}"
failed=()

step() {
    local name="$1"; shift
    echo "▸ $name"
    "$@" || failed+=("$name")
}

debug_build() { ./build.sh debug >/dev/null || { echo "debug build failed"; exit 1; }; }

no_bench_in_release() {
    ./build.sh release >/dev/null || return 1
    local found
    found=$(strings -a build/Shy.app/Contents/MacOS/Shy | grep -ci bench)
    echo "  mentions of the bench in the release binary: $found"
    [ "$found" -eq 0 ]
}

case "$what" in
    unit|smoke|security|all) ;;
    *) echo "usage: Tests/run.sh [unit|smoke|security|all]"; exit 2 ;;
esac
is() { [ "$what" = all ] || [ "$what" = "$1" ]; }

if is unit; then step unit python3 Tests/run-ci-tests.py; fi
if is smoke || is security; then debug_build; fi
if is smoke; then step smoke python3 Tests/smoke.py; fi
if is security; then
    step security python3 Tests/security.py
    step agent python3 Tests/agent_mcp.py
    step "release has no bench" no_bench_in_release
fi

if [ ${#failed[@]} -eq 0 ]; then
    echo "all green"
else
    echo "failed: ${failed[*]}"
    exit 1
fi
