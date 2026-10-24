#!/bin/bash
# Shy has no download site and no update feed: nothing to publish to. The
# script that copied the disk image, the ZIP and an appcast into the old
# site is gone with the updater. Attach build/Shy.dmg (and build/intel/Shy.dmg,
# renamed Shy-Intel.dmg) to a GitHub release instead; ./tap.sh then points
# Homebrew at it.
echo "publish.sh: Shy has no site or update feed to publish to — attach build/Shy.dmg to a GitHub release instead" >&2
exit 1
