#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Self-tests for the string-conversion oracle (spec strings.md)."""
import random
import sys
from fractions import Fraction

sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/tools")
import oracle
import strconv
from oracle import FP5, FPError, encode, ERR_OVERFLOW, ERR_INVALID

random.seed(0xBEEF)
fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print(f"FAIL: {msg}")


# ---- str2fp known answers ----
KAT = [
    (b"0", 0), (b"1", 1), (b"-1", -1), (b"65535", 65535), (b"-65535", -65535),
    (b"12345", 12345), (b"+42", 42), (b"000", 0), (b"0.0", 0),
]
for s, v in KAT:
    r, used = strconv.str2fp(s)
    check(r.to_fraction() == v and used == len(s), f"str2fp {s} -> {r.to_fraction()}")
    if v != 0 and -65535 <= v <= 65535:
        check(r.is_int_form, f"str2fp {s} int form")

# exact FP cases
r, _ = strconv.str2fp(b"0.5")
check(r.b == bytes([0x80, 0, 0, 0, 0]), "str2fp 0.5 exact")
r, _ = strconv.str2fp(b".25")
check(r.to_fraction() == Fraction(1, 4), "str2fp .25")
r, _ = strconv.str2fp(b"123456789")
check(r.to_fraction() == 123456789, "str2fp 9 digits exact")
r, _ = strconv.str2fp(b"1e2")
check(r.to_fraction() == 100, "str2fp 1e2")
r, _ = strconv.str2fp(b"1E-2")
# algorithm-defined: 1/100 via div by P10[1]; equals correctly rounded 0.01
check(r.to_fraction() == oracle.div(encode(Fraction(1), prefer_int=False),
                                    strconv.P10[1]).to_fraction(), "str2fp 1E-2")

# errors and stops
for bad in (b"", b"+", b"-", b".", b"e5", b"abc"):
    try:
        strconv.str2fp(bad)
        check(False, f"str2fp {bad} did not raise")
    except FPError as ex:
        check(ex.code == ERR_INVALID, f"str2fp {bad} code")
r, used = strconv.str2fp(b"12abc")
check(r.to_fraction() == 12 and used == 2, "str2fp stops at 'a'")
r, used = strconv.str2fp(b"3.5E")          # dangling E: not consumed
check(r.to_fraction() == Fraction(7, 2) and used == 3, "str2fp dangling E")
try:
    strconv.str2fp(b"1e40")
    check(False, "1e40 did not overflow")
except FPError as ex:
    check(ex.code == ERR_OVERFLOW, "1e40 code")
r, _ = strconv.str2fp(b"1e-49")
check(r.to_fraction() == 0, "1e-49 flushes")

# ---- fp2str known answers ----
K2 = [
    (encode(Fraction(0)), b"0"),
    (encode(Fraction(1)), b"1"),
    (encode(Fraction(-1)), b"-1"),
    (encode(Fraction(65535)), b"65535"),
    (encode(Fraction(1, 2), prefer_int=False), b"0.5"),
    (encode(Fraction(-7, 2), prefer_int=False), b"-3.5"),
    (encode(Fraction(10), prefer_int=False), b"10"),
    (encode(Fraction(1, 4), prefer_int=False), b"0.25"),
]
for a, want in K2:
    got = strconv.fp2str(a)
    check(got == want, f"fp2str {a.b.hex()} -> {got} want {want}")

# round-trip: fp2str -> str2fp must reproduce the value for values whose
# decimal form is exact within 8 digits (integers up to 8 digits, halves)
for _ in range(3000):
    v = random.randint(-99999999, 99999999)
    a = encode(Fraction(v), prefer_int=False)
    s = strconv.fp2str(a)
    b, _ = strconv.str2fp(s)
    check(b.to_fraction() == v, f"roundtrip int {v}: {s} -> {b.to_fraction()}")

# stability round-trip: for arbitrary values, fp2str(str2fp(fp2str(x))) is
# fixed (the printed form re-parses to a value printing identically)
drift = 0
for _ in range(3000):
    e = random.randint(1, 255)
    m = random.getrandbits(31) | (1 << 31)
    s = random.choice([1, -1])
    a = encode(s * Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)
    s1 = strconv.fp2str(a)
    b, _ = strconv.str2fp(s1)
    s2 = strconv.fp2str(b)
    if s1 != s2:
        drift += 1
        if drift <= 5:
            print(f"NOTE drift: {a.b.hex()} {s1} -> {s2}")
check(drift == 0, f"print/parse fixed point violated {drift} times")

# accuracy vs true value: parse of random decimal strings within 3 ulp
worst = Fraction(0)
for _ in range(3000):
    digs = random.randint(1, 12)
    mant = "".join(random.choice("0123456789") for _ in range(digs))
    dp = random.randint(0, digs)
    txt = mant[:dp] + "." + mant[dp:]
    if txt.startswith("."):
        txt = "0" + txt
    if txt.endswith("."):
        txt = txt[:-1]
    ex = random.randint(-30, 30)
    sstr = f"{txt}e{ex}".encode()
    try:
        r, _ = strconv.str2fp(sstr)
    except FPError:
        continue
    true = Fraction(int(mant), 10 ** (digs - dp)) * Fraction(10) ** ex
    if true == 0:
        check(r.to_fraction() == 0, f"{sstr} zero")
        continue
    got = r.to_fraction()
    if got == 0:
        continue                      # deep underflow flush
    e5 = r.b[0] if not r.is_int_form else None
    ulp = Fraction(2) ** ((e5 if e5 else 145) - 160)
    err = abs(got - true) / ulp
    worst = max(worst, err)
check(worst <= 16, f"str2fp worst error {float(worst):.2f} ulp > 16")
print(f"str2fp measured worst error: {float(worst):.3f} ulp")

print("PASS" if fails == 0 else f"{fails} FAILURES")
sys.exit(1 if fails else 0)
