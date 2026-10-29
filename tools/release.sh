#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Packages a release: the source tree (git archive of the given ref,
# default HEAD) plus the version-stamped interim swap ROM built from
# it, in one zip. Verifies the assembled tree with repoman badcode
# before zipping -- never with a hand-rolled grep, which misses
# whatever the badcode config doesn't happen to be phrased the same
# way as.
#
# Usage: ZENAS=/path/to/zenas REPOMAN=/path/to/repoman tools/release.sh [ref]
# ref defaults to HEAD. VERSION is read from the checked-out tree, not
# from the ref, so tag first (or check out the ref) before running
# this if they need to match.
set -e
cd "$(dirname "$0")/.."
REF="${1:-HEAD}"
ZENAS="${ZENAS:-zenas}"
REPOMAN="${REPOMAN:-repoman}"
VERSION=$(cat VERSION)
DIST=dist

command -v "$ZENAS" >/dev/null 2>&1 \
    || { echo "release: zenas not found; set ZENAS=/path/to/zenas"; exit 1; }
command -v "$REPOMAN" >/dev/null 2>&1 \
    || { echo "release: repoman not found; set REPOMAN=/path/to/repoman"; exit 1; }

echo "== building interim ROM (v$VERSION) =="
python3 tools/genmsgtab.py build/rompatch
python3 tools/gencolours.py rompatch/interim.json build/rompatch
ZENAS="$ZENAS" python3 tools/rompatch.py rompatch/interim.json

ROM="build/rompatch/zenpoint-interim-v${VERSION}.rom"
WATCH="${ROM}.watch.json"
[ -f "$ROM" ] || {
    echo "release: missing $ROM -- did rompatch.py produce a versioned copy?"
    exit 1
}

echo "== assembling release tree from $REF =="
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
PREFIX="zenpoint-${VERSION}/"
git archive --format=tar --prefix="$PREFIX" "$REF" | tar -x -C "$STAGE"
mkdir -p "$STAGE/${PREFIX}rom"
cp "$ROM" "$WATCH" "$STAGE/${PREFIX}rom/"
cp rompatch/AMSTRAD-ROM-PERMISSION.md "$STAGE/${PREFIX}rom/"

echo "== badcode gate on the assembled release =="
"$REPOMAN" badcode check "$STAGE"

mkdir -p "$DIST"
# Resolve OUT to an absolute path BEFORE entering the zip subshell --
# the subshell cds into $STAGE first, so a command substitution
# evaluated inside it (as this used to be) resolves "dist" against
# $STAGE, not the repo root, and fails with "can't cd to dist".
OUT="$(cd "$DIST" && pwd)/zenpoint-${VERSION}.zip"
rm -f "$OUT"
( cd "$STAGE" && zip -qr "$OUT" "$PREFIX" )

echo "== $OUT =="
sha256sum "$OUT" 2>/dev/null || shasum -a 256 "$OUT"
