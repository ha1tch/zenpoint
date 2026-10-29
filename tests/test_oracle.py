#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Self-tests for the zenpoint oracle. Ground truth: exact Fractions, Python's
own binary64 (struct) for IEEE cross-checks, and known-answer vectors."""

import math
import random
import struct
import sys
from fractions import Fraction

sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/tools")
import oracle
from oracle import FP5, FPError, encode, ERR_OVERFLOW, ERR_INVALID, ERR_DIVZERO

random.seed(0xC0FFEE)
fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print(f"FAIL: {msg}")


# ---- known-answer vectors (format spec section 1) ----
KAT = [
    (Fraction(0), bytes([0, 0, 0, 0, 0])),
    (Fraction(1), bytes([0, 0x00, 1, 0, 0])),
    (Fraction(-1), bytes([0, 0xFF, 0xFF, 0xFF, 0])),
    (Fraction(65535), bytes([0, 0x00, 0xFF, 0xFF, 0])),
    (Fraction(-65535), bytes([0, 0xFF, 0x01, 0x00, 0])),
    # FP form: 0.5 = M=2^31, e=128 -> [80h, 00,00,00,00]
    (Fraction(1, 2), bytes([0x80, 0x00, 0x00, 0x00, 0x00])),
    (Fraction(-1, 2), bytes([0x80, 0x80, 0x00, 0x00, 0x00])),
    # 1.0 in FP form (prefer_int=False): e=129, M=2^31
    (Fraction(1, 4), bytes([0x7F, 0x00, 0x00, 0x00, 0x00])),
    # 10 as preferred encoding is int form
    (Fraction(10), bytes([0, 0x00, 0x0A, 0x00, 0])),
]
for v, expected in KAT:
    prefer = v.denominator == 1 and abs(v) <= 65535
    got = encode(v, prefer_int=prefer).b
    check(got == expected, f"KAT encode {v}: got {got.hex()} want {expected.hex()}")
    check(FP5(expected).to_fraction() == v, f"KAT decode {expected.hex()}")

# 1.0 as FP form decodes to 1 as well
check(FP5(bytes([0x81, 0, 0, 0, 0])).to_fraction() == 1, "FP-form 1.0 decode")
# 10 in forced-FP form: e=132, M=0xA0000000 -> m1=0x20
check(encode(Fraction(10), prefer_int=False).b == bytes([0x84, 0x20, 0, 0, 0]),
      "FP-form encode of 10")


def rand_fp5():
    """Random valid 5-byte value, mixing forms and magnitudes."""
    r = random.random()
    if r < 0.3:
        v = random.randint(-65535, 65535)
        return encode(Fraction(v), prefer_int=True)
    e = random.choice([1, 2, random.randint(3, 253), 254, 255])
    m = random.getrandbits(31) | (1 << 31)
    if e == 255:  # keep clear of overflow-adjacent for general vectors
        m &= 0xFFFF_FFF0 | 0x8000_0000
    sign = random.choice([1, -1])
    return encode(sign * Fraction(m, 1) * Fraction(2) ** (e - 160), prefer_int=False)


# ---- round-trip: encode/decode identity ----
for _ in range(20000):
    a = rand_fp5()
    check(encode(a.to_fraction(), prefer_int=a.is_int_form).b == a.b,
          f"enc/dec roundtrip {a.b.hex()}")

# ---- arithmetic: RNE correctness against independent rounding ----
def rne_ref(x: Fraction) -> Fraction:
    """Independent correctly-rounded-to-32-bits reference using float ops on
    scaled integers (pure int math, different code path from oracle.encode)."""
    if x == 0:
        return Fraction(0)
    neg = x < 0
    a = abs(x)
    e = 129
    while a >= Fraction(2) ** (e - 128):
        e += 1
    while a < Fraction(2) ** (e - 129):
        e -= 1
    num = a.numerator * (1 << max(0, 160 - e))
    den = a.denominator * (1 << max(0, e - 160))
    q, r = divmod(num, den)
    if 2 * r > den or (2 * r == den and q % 2 == 1):
        q += 1
    if q == 1 << 32:
        q, e = 1 << 31, e + 1
    if e > 255:
        raise FPError(ERR_OVERFLOW)
    if e < 1:
        return Fraction(0)
    return (-1 if neg else 1) * Fraction(q) * Fraction(2) ** (e - 160)


for _ in range(20000):
    a, b = rand_fp5(), rand_fp5()
    av, bv = a.to_fraction(), b.to_fraction()
    for name, op, exact in (("add", oracle.add, av + bv),
                            ("sub", oracle.sub, av - bv),
                            ("mul", oracle.mul, av * bv)):
        try:
            got = op(a, b).to_fraction()
        except FPError as ex:
            try:
                rne_ref(exact)
                check(False, f"{name} raised {ex.code} but ref rounded fine")
            except FPError:
                pass
            continue
        try:
            want = rne_ref(exact)
        except FPError:
            check(False, f"{name} ref overflowed but oracle returned {got}")
            continue
        # small-int results are exact by construction; FP results must equal ref
        check(got == want or (a.is_int_form and b.is_int_form and got == exact),
              f"{name}({av},{bv}) = {got}, want {want}")
    if bv != 0:
        try:
            got = oracle.div(a, b).to_fraction()
        except FPError as ex:
            try:
                rne_ref(av / bv)
                check(False, f"div raised {ex.code} but ref rounded fine")
            except FPError:
                pass
        else:
            try:
                want = rne_ref(av / bv)
                check(got == want, f"div({av},{bv}) = {got}, want {want}")
            except FPError:
                check(False, f"div ref overflowed but oracle returned {got}")

# div by zero
try:
    oracle.div(rand_fp5(), encode(Fraction(0)))
    check(False, "div by zero did not raise")
except FPError as ex:
    check(ex.code == ERR_DIVZERO, "div-zero code")

# ---- small-int paths ----
x, y = encode(Fraction(30000)), encode(Fraction(30000))
check(oracle.add(x, y).b == bytes([0, 0, 0x60, 0xEA, 0]), "int add 60000 stays int")
check(not oracle.mul(x, y).is_int_form, "int mul out of range -> FP form")
check(oracle.mul(encode(Fraction(255)), encode(Fraction(255))).b ==
      bytes([0, 0, 0x01, 0xFE, 0]), "int mul 65025 stays int form")
check(not oracle.div(encode(Fraction(4)), encode(Fraction(2))).is_int_form,
      "div always FP form")

# ---- INT floor / TRUNC ----
m35 = oracle.sub(encode(Fraction(0)), encode(Fraction(7, 2)))  # -3.5
check(oracle.int_floor(m35).to_fraction() == -4, "INT(-3.5) = -4")
check(oracle.trunc(m35).to_fraction() == -3, "TRUNC(-3.5) = -3")

# ---- IEEE f64: lossless round-trip invariant (spec 3.1) ----
for _ in range(20000):
    a = rand_fp5()
    raw = oracle.to_f64(a)
    # cross-check against Python's own binary64: raw must equal struct-packed
    pyf = struct.unpack("<d", raw)[0]
    check(Fraction(pyf) == a.to_fraction(), f"f64 export exactness {a.b.hex()}")
    back = oracle.from_f64(raw)
    check(back.to_fraction() == a.to_fraction(), f"f64 roundtrip {a.b.hex()}")

# f64 import edge policy
check(oracle.from_f64(struct.pack("<d", -0.0)).b == bytes(5), "-0.0 -> zero")
check(oracle.from_f64(struct.pack("<d", 1e-320)).b == bytes(5), "tiny -> flush 0")
for bad in (float("inf"), float("nan")):
    try:
        oracle.from_f64(struct.pack("<d", bad))
        check(False, f"f64 import {bad} did not raise")
    except FPError as ex:
        check(ex.code == ERR_INVALID, "f64 inf/nan code")
try:
    oracle.from_f64(struct.pack("<d", 2.0 ** 127))
    check(False, "f64 import 2^127 did not overflow")
except FPError as ex:
    check(ex.code == ERR_OVERFLOW, "f64 overflow code")
# max 5-byte value is exact in binary64 and must import without overflow;
# note nextafter(2^127, 0) legitimately overflows: it RNE-rounds up to 2^127.
check(oracle.from_f64(struct.pack("<d", (2.0 ** 127) * (1 - 2.0 ** -32))).b[0] == 255,
      "f64 import of max 5-byte value ok")
try:
    oracle.from_f64(struct.pack("<d", math.nextafter(2.0 ** 127, 0)))
    check(False, "f64 import of value rounding up to 2^127 did not overflow")
except FPError as ex:
    check(ex.code == ERR_OVERFLOW, "f64 round-up overflow code")

# ---- IEEE f32 ----
for _ in range(20000):
    a = rand_fp5()
    raw = oracle.to_f32(a)
    # cross-check RNE against Python's own float32 conversion where finite
    pyf = struct.unpack("<f", struct.pack("<f", struct.unpack("<d", oracle.to_f64(a))[0]))[0]
    if not math.isinf(pyf):
        check(raw == struct.pack("<f", pyf), f"f32 export RNE {a.b.hex()}")
    # import of the export must round-trip when the f32 value is in 5-byte range
    try:
        back = oracle.from_f32(raw)
        check(back.to_fraction() == Fraction(struct.unpack("<f", raw)[0]),
              f"f32 import exact {raw.hex()}")
    except FPError:
        check(abs(struct.unpack("<f", raw)[0]) >= 2.0 ** 127, "f32 import overflow only above 2^127")

# f32 KATs: 1.0f, -2.0f, smallest denormal (flush), 2^-129 (exact)
check(oracle.from_f32(struct.pack("<f", 1.0)).to_fraction() == 1, "f32 1.0")
check(oracle.from_f32(struct.pack("<f", -2.0)).to_fraction() == -2, "f32 -2.0")
check(oracle.from_f32(bytes([1, 0, 0, 0])).b == bytes(5), "f32 min denormal flushes")
check(oracle.from_f32(struct.pack("<f", 2.0 ** -128)).to_fraction() == Fraction(2) ** -128,
      "f32 2^-128 (5-byte minimum) exact")
check(oracle.from_f32(struct.pack("<f", 2.0 ** -129)).b == bytes(5),
      "f32 2^-129 is below 5-byte minimum -> flush to zero")
try:
    oracle.from_f32(struct.pack("<f", 3.0e38))
    check(False, "f32 3e38 did not overflow")
except FPError as ex:
    check(ex.code == ERR_OVERFLOW, "f32 overflow code")

# f32 export of the 5-byte maximum: rounds to exactly 2^127, finite
check(oracle.to_f32(encode((1 - Fraction(1, 2**32)) * 2**127, prefer_int=False))
      == struct.pack("<f", 2.0 ** 127), "f32 export of 5-byte max is finite 2^127")

# f64 import resurrect boundary: just below 2^-128 rounds UP to 2^-128
res = oracle.from_f64(struct.pack("<d", math.nextafter(2.0 ** -128, 0)))
check(res.b == bytes([0x01, 0, 0, 0, 0]), "f64 import resurrects to 2^-128")
check(oracle.from_f64(struct.pack("<d", 2.0 ** -129)).b == bytes(5),
      "f64 import 2^-129 flushes")

print("PASS" if fails == 0 else f"{fails} FAILURES")
sys.exit(1 if fails else 0)
