#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# End-to-end CIRCLE check on a real Spectrum emulator (ZenZX headless).
#
# Not part of the default gate: it needs a zenzx-headless binary built
# with the interim ROM embedded as rom/48.rom (see docs). Drives the
# genuine keyboard/editor path -- EXTEND MODE, SYMBOL-SHIFT+H for the
# CIRCLE token, parameters, ENTER -- on BOTH a direct command and a
# stored program + RUN, and requires the screen to show a drawn circle.
#
# Usage: ZENZX_ZP=/path/to/zenzx-headless-zenpoint tests/e2e/run.sh
# Why the emulator, not a snapshot: ZenZX snapshots restore the ROM
# region, so loading one silently swaps the stock ROM back in and tests
# the wrong code. Typing through the editor is the only honest path.
set -e
cd "$(dirname "$0")"
ZX="${ZENZX_ZP:?set ZENZX_ZP to a zenzx-headless built with the interim ROM}"
OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
sed "s#OUT#direct.png#" circle-direct.zen > "$OUT/d.zen"
sed "s#OUT#prog#g"      circle-program.zen > "$OUT/p.zen"
"$ZX" -model=48k -romdir=/nonexistent -script="$OUT/d.zen" -shot-dir="$OUT" -frames=900  -quiet >/dev/null 2>&1
"$ZX" -model=48k -romdir=/nonexistent -script="$OUT/p.zen" -shot-dir="$OUT" -frames=1200 -quiet >/dev/null 2>&1
python3 - "$OUT/direct.png" "$OUT/prog-run.png" <<'PY'
import sys
from PIL import Image
ok = True
for p in sys.argv[1:]:
    im = Image.open(p).convert("RGB"); px = im.load(); w,h = im.size
    bg = px[0, 0]     # sample the actual paper colour -- do not assume
                       # dark-on-light: the interim ROM's cold-boot
                       # default is paper 1/ink 7 (light-on-dark)
    # ink inside the plotting area (exclude the bottom status rows)
    ink = sum(1 for y in range(0, h-16) for x in range(w) if px[x,y] != bg)
    good = 240 <= ink <= 330          # midpoint circle r=50: ~4*sqrt(2)*r = 283
    print(f"{p.split('/')[-1]}: {ink} ink pixels (bg={bg}) -> {'OK' if good else 'FAIL'}")
    ok &= good
sys.exit(0 if ok else 1)
PY
echo "E2E CIRCLE OK"
