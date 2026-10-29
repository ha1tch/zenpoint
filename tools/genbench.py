#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Generate shared operand vectors for the three-way speed benchmark
(Vickers 48K ROM / OpenSE 3.2.1 / zenpoint). Record: op(1) a(5) b(5)
true(f64 LE, 8) = 19 bytes; LE u32 count header.

ops: 1 add, 2 sub, 4 mul, 5 div (binary); 14 sqrt, 15 ln, 16 exp,
17 sin, 18 cos, 19 tan, 20 atn, 21 asn, 22 acs (unary). Numbers match
the differential harness's op ids. Values avoid every error path in
all three implementations (no overflow, poles, or domain edges) so a
timed run is always a completed computation."""
import math
import random
import struct
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from fractions import Fraction
from oracle import encode

random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 42)
N = int(sys.argv[3]) if len(sys.argv) > 3 else 40

recs = []


def emit(op, a, b=None, true=0.0):
    recs.append(bytes([op]) + a.b + (b.b if b else bytes(5)) +
                struct.pack("<d", true))


def fp(x):
    return encode(Fraction(x).limit_denominator(10**12), prefer_int=False)


for _ in range(N):
    # binary ops: magnitudes spread but safely away from overflow/zero
    av = random.uniform(-1000.0, 1000.0) or 1.0
    bv = random.uniform(0.01, 100.0) * random.choice([1, -1])
    a, b = fp(av), fp(bv)
    av, bv = float(a.to_fraction()), float(b.to_fraction())
    emit(1, a, b, av + bv)
    emit(2, a, b, av - bv)
    emit(4, a, b, av * bv)
    emit(5, a, b, av / bv)
    # unary domains
    p = fp(random.uniform(0.001, 10000.0))
    pv = float(p.to_fraction())
    emit(14, p, None, math.sqrt(pv))
    emit(15, p, None, math.log(pv))
    e = fp(random.uniform(-70.0, 70.0))
    emit(16, e, None, math.exp(float(e.to_fraction())))
    t = fp(random.uniform(-6.0, 6.0))
    tv = float(t.to_fraction())
    emit(17, t, None, math.sin(tv))
    emit(18, t, None, math.cos(tv))
    if abs(math.cos(tv)) > 0.05:
        emit(19, t, None, math.tan(tv))
    w = fp(random.uniform(-500.0, 500.0))
    emit(20, w, None, math.atan(float(w.to_fraction())))
    u = fp(random.uniform(-0.98, 0.98))
    uv = float(u.to_fraction())
    emit(21, u, None, math.asin(uv))
    emit(22, u, None, math.acos(uv))

out = sys.argv[1] if len(sys.argv) > 1 else "tests/vectors/bench.bin"
with open(out, "wb") as f:
    f.write(struct.pack("<I", len(recs)))
    f.write(b"".join(recs))
print(f"{len(recs)} bench vectors -> {out}")
