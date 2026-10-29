#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Generate differential test vectors for the Z80 implementation.

Record (v2): op(1) a(8) b(8) status(1) result(8) = 26 bytes, LE count header.
ops: 1=add 2=sub 3=cmp 4=mul 5=div (a,b = 5-byte values, zero-padded)
     6=to_f64 (a=5-byte, res=8)   7=from_f64 (a=8-byte double, res=5)
     8=to_f32 (a=5-byte, res=4)   9=from_f32 (a=4-byte float, res=5)
     10=int (floor)  11=trunc     (a=5-byte, res=5)
status 0 = ok, else error code. cmp: result[0] = 0/1/0xFF."""
import math
import random
import struct
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import oracle
import transc
from oracle import FP5, FPError, encode
from fractions import Fraction

random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
N = int(sys.argv[3]) if len(sys.argv) > 3 else 4000

def pad8(b): return b + bytes(8 - len(b))

def rand_fp5():
    r = random.random()
    if r < 0.35:
        return encode(Fraction(random.randint(-65535, 65535)))
    e = random.choice([1, 2, 3, random.randint(4, 252), 253, 254, 255,
                       random.randint(120, 136), random.randint(129, 160)])
    m = random.getrandbits(31) | (1 << 31)
    s = random.choice([1, -1])
    return encode(s * Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)

EDGE = [encode(Fraction(0)), encode(Fraction(1)), encode(Fraction(-1)),
        encode(Fraction(65535)), encode(Fraction(-65535)),
        encode(Fraction(30000)), encode(Fraction(-30000)),
        encode(Fraction(1, 2), prefer_int=False),
        encode(Fraction(1), prefer_int=False),
        encode((1 - Fraction(1, 2**32)) * 2**127, prefer_int=False),
        encode(Fraction(2) ** -128, prefer_int=False),
        encode(-(1 - Fraction(1, 2**32)) * 2**127, prefer_int=False),
        encode(Fraction(2) ** 64 + 12345, prefer_int=False),
        encode(-Fraction(7, 2), prefer_int=False),
        encode(Fraction(2) ** -1, prefer_int=False),
        ]

recs = []
def run_op(op, a, b):
    if op == 1: return oracle.add(a, b).b, 0
    if op == 2: return oracle.sub(a, b).b, 0
    if op == 3: return bytes([oracle.cmp(a, b) & 0xFF]), 0
    if op == 4: return oracle.mul(a, b).b, 0
    if op == 5: return oracle.div(a, b).b, 0
    if op == 6: return oracle.to_f64(a), 0
    if op == 7: return oracle.from_f64(bytes(a)).b, 0
    if op == 8: return oracle.to_f32(a), 0
    if op == 9: return oracle.from_f32(bytes(a)).b, 0
    if op == 10: return oracle.int_floor(a).b, 0
    if op == 11: return oracle.trunc(a).b, 0
    if op == 14: return oracle.sqrt(a).b, 0
    if op == 15: return transc.ln(a).b, 0
    if op == 16: return transc.exp(a).b, 0
    if op == 17: return transc.sin(a).b, 0
    if op == 18: return transc.cos(a).b, 0
    if op == 19: return transc.tan(a).b, 0
    if op == 20: return transc.atn(a).b, 0
    if op == 21: return transc.asn(a).b, 0
    if op == 22: return transc.acs(a).b, 0

def emit(op, a, b=None):
    araw = a if isinstance(a, (bytes, bytearray)) else a.b
    braw = b.b if b is not None else bytes(5)
    try:
        res, st = run_op(op, a, b)
    except FPError as ex:
        res, st = bytes(8), ex.code
    recs.append(bytes([op]) + pad8(araw) + pad8(braw) + bytes([st]) + pad8(res))

BIN = (1, 2, 3, 4, 5)
UNARY5 = (6, 8, 10, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22)

for a in EDGE:
    for b in EDGE:
        for op in BIN:
            emit(op, a, b)
    for op in UNARY5:
        emit(op, a)
for _ in range(N):
    a, b = rand_fp5(), rand_fp5()
    for op in BIN:
        emit(op, a, b)
    for op in UNARY5:
        emit(op, a)
# adjacent/cancellation pairs
for _ in range(N // 2):
    a = rand_fp5()
    av = a.to_fraction()
    if av == 0: continue
    ulp = Fraction(2) ** (max(1, a.b[0]) - 160)
    for d in (0, 1, -1, 2):
        try:
            b = encode(av + d * ulp, prefer_int=False)
        except FPError:
            continue
        for op in BIN:
            emit(op, a, b)

# targeted ln/exp domains: near 1 for ln, exp-representable range
for _ in range(N // 2):
    m = random.getrandbits(31) | (1 << 31)
    e = random.choice([128, 129, 129, 130, 127])
    a = encode(Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)
    emit(15, a)
    x = Fraction(random.randint(-89000, 89000), 1000)
    if x:
        emit(16, encode(x, prefer_int=False))
emit(16, encode(Fraction(88), prefer_int=False))
emit(16, encode(Fraction(89), prefer_int=False))
emit(16, encode(Fraction(-89), prefer_int=False))
emit(16, encode(Fraction(-100), prefer_int=False))
emit(16, encode(Fraction(200), prefer_int=False))
emit(15, encode(Fraction(1)))
emit(15, encode(Fraction(1), prefer_int=False))

# the non-canonical-but-legal integer form of -65536 ([00 FF 00 00 00]):
# never produced by encode (which emits FP form), but a real value on
# hardware that external callers can pass; the oracle computes from the
# exact decoded value, so these vectors verify the Z80 handles it
M64K = FP5(bytes([0, 0xFF, 0, 0, 0]))
for op in UNARY5:
    emit(op, M64K)
for b2 in (encode(Fraction(1)), encode(Fraction(-1)), encode(Fraction(2)),
           encode(Fraction(65535)), encode(Fraction(-65535)), M64K,
           encode(Fraction(1, 2), prefer_int=False),
           encode(Fraction(3), prefer_int=False)):
    for op in BIN:
        emit(op, M64K, b2)
        emit(op, b2, M64K)

# targeted trig domains: near quarter-circle multiples (poles/zeros),
# plain range, the reduction gate boundary, tiny arguments
HALF_PI = Fraction(math.pi) / 2
for _ in range(N // 2):
    k = random.randint(-65000, 65000)
    jitter = Fraction(random.randint(-1000, 1000), 10**9)
    try:
        a = encode(k * HALF_PI + jitter, prefer_int=False)
    except FPError:
        continue
    for op in (17, 18, 19):
        emit(op, a)
    # arctangent family: dense [-1,1] for asn/acs, wide range for atn,
    # fold boundaries 1 and tan(pi/8)
    u = Fraction(random.randint(-10**9, 10**9), 10**9)
    au = encode(u, prefer_int=False) if u else None
    if au is not None:
        for op in (20, 21, 22):
            emit(op, au)
    emit(20, rand_fp5())
    x = Fraction(random.randint(-102900000, 102900000), 1000)
    if x:
        b2 = encode(x, prefer_int=False)
        for op in (17, 18, 19):
            emit(op, b2)
for v in (Fraction(102943), Fraction(102944), Fraction(103000),
          Fraction(-102944), Fraction(2)**20, -Fraction(2)**20,
          Fraction(1, 2**40), -Fraction(1, 2**40), Fraction(3),
          Fraction(65535), Fraction(-65535)):
    try:
        a = encode(v, prefer_int=False)
    except FPError:
        continue
    for op in (17, 18, 19):
        emit(op, a)
for v in (Fraction(1), Fraction(-1), Fraction(41421, 100000),
          Fraction(41422, 100000), Fraction(2), Fraction(-2),
          Fraction(1, 2**40), Fraction(2)**126,
          Fraction(1000001, 1000000), Fraction(999999, 1000000),
          Fraction(-1000001, 1000000)):
    a = encode(v, prefer_int=False)
    for op in (20, 21, 22):
        emit(op, a)

# ---- from_f64 vectors ----
f64_specials = [0.0, -0.0, 1.0, -1.0, 0.5, 1e-320, 2.0 ** -129,
                math.nextafter(2.0 ** -128, 0), 2.0 ** -128, 2.0 ** 127,
                math.nextafter(2.0 ** 127, 0), (2.0 ** 127) * (1 - 2.0 ** -32),
                float("inf"), float("-inf"), float("nan"), 3.141592653589793,
                -65535.0, 65536.0, 1e300, -1e-300]
for v in f64_specials:
    emit(7, struct.pack("<d", v))
for _ in range(N):
    a = rand_fp5()
    emit(7, oracle.to_f64(a))                      # exact round-trips
    m = random.getrandbits(64)
    emit(7, struct.pack("<Q", m))                  # arbitrary bit patterns
    ex = random.randint(890, 1160) << 52           # exponents near our range
    emit(7, struct.pack("<Q", (m & 0x800FFFFFFFFFFFFF) | ex))

# ---- from_f32 vectors ----
f32_specials = [0.0, -0.0, 1.0, -2.0, 2.0 ** -128, 2.0 ** -129, 2.0 ** 126,
                float("inf"), float("-inf"), float("nan"), 3.4e38, 1e-40]
for v in f32_specials:
    emit(9, struct.pack("<f", struct.unpack("<f", struct.pack("<f", v))[0]))
emit(9, bytes([1, 0, 0, 0]))                       # min denormal
emit(9, bytes([0xFF, 0xFF, 0x7F, 0x00]))           # large denormal
emit(9, bytes([0xFF, 0xFF, 0x7F, 0x7F]))           # max finite
emit(9, bytes([0x00, 0x00, 0x80, 0x7E]))           # 2^126
for _ in range(N):
    a = rand_fp5()
    try:
        emit(9, oracle.to_f32(a))
    except FPError:
        pass
    emit(9, struct.pack("<I", random.getrandbits(32)))

out = sys.argv[1] if len(sys.argv) > 1 else "tests/vectors/all.bin"
with open(out, "wb") as f:
    f.write(struct.pack("<I", len(recs)))
    f.write(b"".join(recs))
print(f"{len(recs)} vectors -> {out}")
