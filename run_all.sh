#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Canonical verification gate. Always rebuilds BOTH sides before running:
# a stale harness binary silently runs old entry tables against new code
# (that exact failure cost a debugging session; do not "optimize" this out).
# NOTE: the full gate now runs every vector file on BOTH builds (plain +
# Next) and takes ~2.5 minutes — run it with a generous timeout; a killed
# gate is not a failed gate, but it is not a passed one either.
# Usage: ./run_all.sh [--quiet]
# Environment:
#   ZENAS        path to the zenas assembler (default: zenas on PATH)
#   VICKERS_ROM  original 48K ROM image (default: the bundled
#                rom/base/48.rom, else the Debian/Ubuntu spectrum-roms
#                package, /usr/share/spectrum-roms/48.rom); also used as
#                the swap-ROM base (ROMPATCH_BASE)
# Runs from a bare checkout: creates build/, generates any missing
# untracked test vectors (tools/genvectors.sh) and fetches the pinned Go
# test dependencies on first use (network needed once; for an offline
# run, prime the module cache and export GOPROXY=off yourself).
set -e
cd "$(dirname "$0")"
ZENAS="${ZENAS:-zenas}"
need() { command -v "$1" >/dev/null 2>&1 || { echo "$2"; exit 1; }; }
need "$ZENAS" "zenas not found; set ZENAS=/path/to/zenas (v0.9.0 or later)"
need go "go not found (Go 1.25 or later: https://go.dev/dl/)"
need python3 "python3 not found (3.10 or later)"
python3 -c "import mpmath" >/dev/null 2>&1 \
    || { echo "python3 module mpmath not found (pip install -r requirements.txt)"; exit 1; }
BASEROM="${VICKERS_ROM:-${ROMPATCH_BASE:-}}"
if [ -z "$BASEROM" ]; then
    if [ -f "$PWD/rom/base/48.rom" ]; then BASEROM="$PWD/rom/base/48.rom"
    else BASEROM=/usr/share/spectrum-roms/48.rom; fi
fi
[ -f "$BASEROM" ] \
    || { echo "original 48K ROM not found at $BASEROM; restore rom/base/48.rom, install the spectrum-roms package, or set VICKERS_ROM=/path/to/48.rom"; exit 1; }
export VICKERS_ROM="$BASEROM" ROMPATCH_BASE="$BASEROM"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
mkdir -p build
Q=""
[ "$1" = "--quiet" ] && Q=1

say() { [ -z "$Q" ] && echo "$@" || true; }
say "base ROM: $BASEROM"

say "== oracle self-tests"
for t in tests/test_oracle.py tests/test_strconv.py tests/test_sqrt.py \
         tests/test_transc.py; do
    if [ -n "$Q" ]; then python3 "$t" >/dev/null; else python3 "$t"; fi
done

for v in all.bin all2.bin str.bin str2.bin circle.txt; do
    if [ ! -f "tests/vectors/$v" ]; then
        say "== generating test vectors (tools/genvectors.sh)"
        if [ -n "$Q" ]; then sh tools/genvectors.sh >/dev/null; else sh tools/genvectors.sh; fi
        break
    fi
done

say "== assemble"
"$ZENAS" assemble src/zenpoint.asm build/zenpoint.bin \
    --sym=build/zenpoint.sym > "$TMPD/zenas.out" 2>&1 \
    || { cat "$TMPD/zenas.out"; exit 1; }
grep -E "^Assembled" "$TMPD/zenas.out" || true
"$ZENAS" assemble src/zenpoint_next.asm build/zenpoint_next.bin \
    --sym=build/zenpoint_next.sym > "$TMPD/zenas2.out" 2>&1 \
    || { cat "$TMPD/zenas2.out"; exit 1; }
grep -E "^Assembled" "$TMPD/zenas2.out" || true

say "== rebuild harness"
( cd tests/harness && go build -o harness . )

say "== circle (T-18 swap-ROM routine)"
"$ZENAS" assemble src/circle.asm build/circle.bin > "$TMPD/zenas3.out" 2>&1 \
    || { cat "$TMPD/zenas3.out"; exit 1; }
[ -f tests/vectors/circle.txt ] \
    || { echo "missing circle.txt (regenerate with tools/gencircle.py)"; exit 1; }
( cd tests/circle && go build -o circletest . \
    && ./circletest ) > "$TMPD/circle.out" 2>&1 \
    || { cat "$TMPD/circle.out"; echo "GATE FAILED: circle"; exit 1; }
tail -1 "$TMPD/circle.out"

say "== differential vectors"
for v in tests/vectors/all.bin tests/vectors/all2.bin \
         tests/vectors/str.bin tests/vectors/str2.bin; do
    [ -f "$v" ] || { echo "missing $v (regenerate with tools/genvec.py / genstrvec.py)"; exit 1; }
    say "-- $v"
    # never pipe the harness: a pipe would report the pipe tail's exit
    # code and swallow failures (working agreement 4.2)
    ( cd tests/harness && ./harness "../../$v" ) > "$TMPD/harness.out" 2>&1 \
        || { cat "$TMPD/harness.out"; echo "GATE FAILED: $v"; exit 1; }
    tail -1 "$TMPD/harness.out"
    ( cd tests/harness && ZEN_Z80N=1 ./harness "../../$v" \
        ../../build/zenpoint_next.bin ) > "$TMPD/harness.out" 2>&1 \
        || { cat "$TMPD/harness.out"; echo "GATE FAILED (next): $v"; exit 1; }
done
say "== interim swap-ROM (rompatch)"
python3 tools/genmsgtab.py build/rompatch > "$TMPD/msgtab.out" 2>&1 \
    || { cat "$TMPD/msgtab.out"; exit 1; }
python3 tools/gencolours.py rompatch/interim.json build/rompatch > "$TMPD/colours.out" 2>&1 \
    || { cat "$TMPD/colours.out"; exit 1; }
ZENAS="$ZENAS" python3 tools/rompatch.py rompatch/interim.json \
    > "$TMPD/rompatch.out" 2>&1 || { cat "$TMPD/rompatch.out"; exit 1; }
grep -E "^rompatch:" "$TMPD/rompatch.out"
( cd tests/boot && go build -o boottest . \
    && ./boottest ) > "$TMPD/boot.out" 2>&1 \
    || { cat "$TMPD/boot.out"; echo "GATE FAILED: interim boot"; exit 1; }
tail -1 "$TMPD/boot.out"

echo "ALL GREEN"
