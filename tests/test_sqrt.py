#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Oracle sqrt: correct rounding verified against exact Fraction math."""
import random, sys
from fractions import Fraction
sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/tools")
import oracle
from oracle import FP5, FPError, encode, ERR_INVALID

random.seed(0x51)
fails = 0
def check(c, m):
    global fails
    if not c: fails += 1; print("FAIL:", m)

# exact squares
for v in (1, 4, 9, 100, 65536, 2**20, 2**126):
    r = oracle.sqrt(encode(Fraction(v), prefer_int=False))
    check(r.to_fraction() ** 2 == v, f"sqrt({v}) exact")
check(oracle.sqrt(encode(Fraction(0))).b == bytes(5), "sqrt(0)")
try:
    oracle.sqrt(encode(Fraction(-1)))
    check(False, "sqrt(-1) no error")
except FPError as ex:
    check(ex.code == ERR_INVALID, "sqrt(-1) code")

# correct rounding: result is the representable value nearest sqrt(x)
for _ in range(20000):
    e = random.randint(1, 255)
    m = random.getrandbits(31) | (1 << 31)
    a = encode(Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)
    r = oracle.sqrt(a).to_fraction()
    x = a.to_fraction()
    # neighbors of r in the format
    er = oracle.sqrt(a).b[0]
    ulp = Fraction(2) ** (er - 160)
    lo, hi = r - ulp, r + ulp
    # |r^2 - x| minimized among {lo, r, hi} (RNE tie cases are exact-rep
    # boundary comparisons on r +- ulp/2)
    def dist(c):
        return abs(c * c - x)
    check(dist(r) <= dist(lo) and dist(r) <= dist(hi),
          f"sqrt not nearest at {a.b.hex()}")
print("PASS" if fails == 0 else f"{fails} FAILURES")
sys.exit(1 if fails else 0)
