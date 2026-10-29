#!/bin/sh
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Generates the untracked test vectors under tests/vectors/ with fixed
# seeds, so every machine produces byte-identical files. run_all.sh calls
# this automatically when any of them is missing.
#
#   all.bin     genvec.py     seed 1,   N=3000   (~118k numeric vectors)
#   all2.bin    genvec.py     seed 999, N=3000   (second, independent seed)
#   str.bin     genstrvec.py  seed 7,   N=2500   (string conversion)
#   str2.bin    genstrvec.py  seed 13,  N=2500
#   circle.txt  gencircle.py                     (T-18 CIRCLE reference)
#   bench.bin   genbench.py   seed 42,  N=40     (tests/bench only)
#
# Needs python3 with mpmath (see requirements.txt). Run from anywhere.
set -e
cd "$(dirname "$0")/.."
mkdir -p tests/vectors
python3 tools/genvec.py tests/vectors/all.bin 1 3000
python3 tools/genvec.py tests/vectors/all2.bin 999 3000
python3 tools/genstrvec.py tests/vectors/str.bin 7 2500
python3 tools/genstrvec.py tests/vectors/str2.bin 13 2500
python3 tools/gencircle.py tests/vectors/circle.txt
python3 tools/genbench.py tests/vectors/bench.bin 42 40
