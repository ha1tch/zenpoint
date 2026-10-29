#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""ln/exp oracle: accuracy vs mpmath, identities, edge policy."""
import random, sys
from fractions import Fraction
sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/tools")
import mpmath as mp
import oracle, transc
from oracle import FP5, FPError, encode, ERR_INVALID, ERR_OVERFLOW

mp.mp.prec = 120
random.seed(0x1E)
fails = 0
def check(c, m):
    global fails
    if not c: fails += 1; print("FAIL:", m)

def ulps(got: FP5, true) -> float:
    if got.b == bytes(5):
        return 0.0 if abs(true) < mp.mpf(2) ** -128 else float("inf")
    e = got.b[0] if not got.is_int_form else 145
    ulp = mp.mpf(2) ** (e - 160)
    return float(abs(mp.mpf(got.to_fraction().numerator) /
                     got.to_fraction().denominator - true) / ulp)

# edges
check(transc.ln(encode(Fraction(1))).b == bytes(5), "ln(1) = 0")
for bad in (Fraction(0), Fraction(-1)):
    try:
        transc.ln(encode(bad))
        check(False, f"ln({bad}) no error")
    except FPError as ex:
        check(ex.code == ERR_INVALID, f"ln({bad}) code")
check(transc.exp(encode(Fraction(0))).to_fraction() == 1, "exp(0) = 1")
try:
    transc.exp(encode(Fraction(200)))
    check(False, "exp(200) no overflow")
except FPError as ex:
    check(ex.code == ERR_OVERFLOW, "exp(200) code")
check(transc.exp(encode(Fraction(-200))).b == bytes(5), "exp(-200) flushes")

# accuracy sweeps
worst_ln = worst_exp = 0.0
for _ in range(4000):
    e = random.randint(1, 255)
    m = random.getrandbits(31) | (1 << 31)
    a = encode(Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)
    r = transc.ln(a)
    t = mp.log(mp.mpf(a.to_fraction().numerator) / a.to_fraction().denominator)
    worst_ln = max(worst_ln, ulps(r, t))
for _ in range(4000):
    x = Fraction(random.randint(-88000, 88000), 1000)
    if x == 0: continue
    a = encode(x, prefer_int=False)
    try:
        r = transc.exp(a)
    except FPError:
        continue
    av = a.to_fraction()               # judge against the value exp actually saw
    t = mp.exp(mp.mpf(av.numerator) / av.denominator)
    worst_exp = max(worst_exp, ulps(r, t))
print(f"ln worst: {worst_ln:.2f} ulp, exp worst: {worst_exp:.2f} ulp")
check(worst_ln <= 4, f"ln worst {worst_ln}")
check(worst_exp <= 4, f"exp worst {worst_exp}")

# round-trip: exp(ln(x)) drifts by conditioning: exp amplifies ln's own
# output rounding by |ln(x)|/ulp-scale, so the bound grows with |ln(x)|.
worst_rt_n = 0.0
for _ in range(2000):
    e = random.randint(20, 235)
    m = random.getrandbits(31) | (1 << 31)
    a = encode(Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)
    rt = transc.exp(transc.ln(a))
    t = mp.mpf(a.to_fraction().numerator) / a.to_fraction().denominator
    lnmag = abs(float(mp.log(t))) if t > 0 else 0.0
    bound = 6.0 + 6.0 * max(1.0, lnmag)   # ulps allowed at this conditioning
    u = ulps(rt, t)
    worst_rt_n = max(worst_rt_n, u / bound)
print(f"exp(ln(x)) worst normalized: {worst_rt_n:.2f} of conditioning bound")
check(worst_rt_n <= 1.0, f"roundtrip beyond conditioning bound {worst_rt_n}")

# ---- circular functions vs mpmath ----
# ulp measured where the true result is not vanishingly small; near the
# zeros of sin/cos the error is the (absolute) reduction residual and a
# relative measure is meaningless. tan near poles is conditioning-bound:
# d(tan) = (1+tan^2) dr, so allow ulp growth ~ |tan|.
worst_sin = worst_cos = 0.0
worst_tan_n = 0.0
for _ in range(4000):
    x = Fraction(random.randint(-102900000000, 102900000000), 10**6)
    if x == 0:
        continue
    a = encode(x, prefer_int=False)
    t = mp.mpf(a.to_fraction().numerator) / a.to_fraction().denominator
    s_true, c_true, t_true = mp.sin(t), mp.cos(t), mp.tan(t)
    if abs(s_true) > 1e-7:
        worst_sin = max(worst_sin, ulps(transc.sin(a), s_true))
    if abs(c_true) > 1e-7:
        worst_cos = max(worst_cos, ulps(transc.cos(a), c_true))
    if abs(c_true) > 1e-7:
        bound = 6.0 + abs(float(t_true)) / 4.0
        try:
            worst_tan_n = max(worst_tan_n, ulps(transc.tan(a), t_true) / bound)
        except FPError:
            pass
print(f"sin worst: {worst_sin:.2f} ulp, cos worst: {worst_cos:.2f} ulp, "
      f"tan worst: {worst_tan_n:.2f} of conditioning bound")
check(worst_sin <= 6, f"sin worst {worst_sin}")
check(worst_cos <= 6, f"cos worst {worst_cos}")
check(worst_tan_n <= 1.0, f"tan beyond conditioning bound {worst_tan_n}")

# exact points and the reduction gate
check(transc.sin(encode(Fraction(0))).b == bytes(5), "sin(0) != 0")
check(transc.cos(encode(Fraction(0))).b == bytes([0, 0, 1, 0, 0]), "cos(0) != 1")
check(transc.tan(encode(Fraction(0))).b == bytes(5), "tan(0) != 0")
for big in (Fraction(2) ** 20, -Fraction(2) ** 20, Fraction(2) ** 100):
    try:
        transc.sin(encode(big, prefer_int=False))
        check(False, f"sin({big}) did not gate")
    except FPError as ex:
        check(ex.code == ERR_INVALID, "gate error code")

# ---- arctangent family vs mpmath ----
# atn and asn are well-conditioned in ulp terms. acs near +1 cancels
# in pi/2 - asn: relative error grows as the result shrinks while the
# absolute error stays at ulp-of-pi/2 scale — assert both regimes.
worst_atn = worst_asn = worst_acs = 0.0
worst_acs_abs = 0.0
for _ in range(4000):
    x = Fraction(random.randint(-10**12, 10**12),
                 10 ** random.choice([0, 3, 6, 9, 12]))
    if x == 0:
        continue
    a = encode(x, prefer_int=False)
    xv = a.to_fraction()
    t = mp.mpf(xv.numerator) / xv.denominator
    worst_atn = max(worst_atn, ulps(transc.atn(a), mp.atan(t)))
    if abs(xv) <= 1:
        worst_asn = max(worst_asn, ulps(transc.asn(a), mp.asin(t)))
        ac_true = mp.acos(t)
        got = transc.acs(a)
        if abs(ac_true) > mp.mpf("0.1"):
            worst_acs = max(worst_acs, ulps(got, ac_true))
        gv = got.to_fraction()
        err_abs = abs(mp.mpf(gv.numerator) / gv.denominator - ac_true)
        worst_acs_abs = max(worst_acs_abs, float(err_abs))
print(f"atn worst: {worst_atn:.2f} ulp, asn worst: {worst_asn:.2f} ulp, "
      f"acs worst: {worst_acs:.2f} ulp (>0.1), abs {worst_acs_abs:.2e}")
check(worst_atn <= 6, f"atn worst {worst_atn}")
check(worst_asn <= 6, f"asn worst {worst_asn}")
check(worst_acs <= 6, f"acs worst {worst_acs}")
check(worst_acs_abs <= 1.5e-9, f"acs absolute {worst_acs_abs}")

# exact points, boundaries, domain errors
HALF_PI_B = transc.CPI2.b
one_f = encode(Fraction(1), prefer_int=False)
mone_f = encode(Fraction(-1), prefer_int=False)
check(transc.atn(encode(Fraction(0))).b == bytes(5), "atn(0) != 0")
check(transc.asn(one_f).b == HALF_PI_B, "asn(1) != pi/2")
check(transc.acs(one_f).b == bytes(5), "acs(1) != 0")
check(transc.asn(mone_f).b == transc._negate_pk(transc.CPI2).b,
      "asn(-1) != -pi/2")
for bad in (Fraction(1000001, 1000000), Fraction(-2), Fraction(30000)):
    for fn in (transc.asn, transc.acs):
        try:
            fn(encode(bad, prefer_int=False))
            check(False, f"{fn.__name__}({bad}) did not error")
        except FPError as ex:
            check(ex.code == ERR_INVALID, f"{fn.__name__}({bad}) code")

print("PASS" if fails == 0 else f"{fails} FAILURES")
sys.exit(1 if fails else 0)
