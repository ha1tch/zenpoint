#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Oracle side of the M3 ln/exp recipes (docs/spec/transcendentals.md).
Every step uses the package's own RNE operations so the Z80 mirrors it
bit-exact. Constants/coefficients come from tools/gencoeff.py only."""
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from fractions import Fraction
import oracle
from oracle import FP5, FPError, encode, ERR_OVERFLOW, ERR_INVALID
import gencoeff

T = gencoeff._cached()
P = T["P"]                 # ln kernel coefficients, highest degree first
Q = T["Q"]                 # exp kernel coefficients, highest degree first
CLN2 = T["named"]["CLN2"]
CL1 = T["named"]["CL1"]
CL2 = T["named"]["CL2"]
CINVLN2 = T["named"]["CINVLN2"]
CSQRT2O2 = T["named"]["CSQRT2O2"]
ONE = encode(Fraction(1), prefer_int=False)
CHALF = FP5(bytes([0x80, 0, 0, 0, 0]))
INT_ONE = encode(Fraction(1))


def _scale2(a: FP5, delta: int) -> FP5:
    """Exact scale by 2^delta via the exponent byte (FP form, nonzero).
    Underflow flushes to zero; overflow raises."""
    if a.b[0] == 0:
        # int form: renormalize through encode
        v = a.to_fraction() * Fraction(2) ** delta
        return encode(v, prefer_int=False)
    e = a.b[0] + delta
    if e <= 0:
        return FP5(bytes(5))
    if e > 255:
        raise FPError(ERR_OVERFLOW)
    return FP5(bytes([e]) + a.b[1:])


def _poly(coeffs, x: FP5) -> FP5:
    r = coeffs[0]
    for c in coeffs[1:]:
        r = oracle.add(oracle.mul(r, x), c)
    return r


def ln(a: FP5) -> FP5:
    v = a.to_fraction()
    if v <= 0:
        raise FPError(ERR_INVALID)
    fp = encode(v, prefer_int=False)
    e = fp.b[0]
    # s = mantissa with exponent forced to 128 (value in [0.5, 1))
    s = FP5(bytes([128]) + fp.b[1:])
    k = e - 128
    if oracle.cmp(s, CSQRT2O2) < 0:
        s = _scale2(s, 1)              # s in [sqrt2/2, sqrt2)
        k -= 1
    # z = (s-1)/(s+1); w = z^2; ln(s) = 2 z P(w)
    z = oracle.div(oracle.sub(s, ONE), oracle.add(s, ONE))
    if z.b == bytes(5):
        lns = FP5(bytes(5))            # s == 1 exactly
    else:
        w = oracle.mul(z, z)
        lns = oracle.mul(_scale2(z, 1), _poly(P, w))
    kf = encode(Fraction(k))
    return oracle.add(oracle.mul(kf, CLN2), lns)


def exp(a: FP5) -> FP5:
    v = a.to_fraction()
    if v == 0:
        return INT_ONE
    # magnitude pre-gate (mirrors the Z80 exactly): FP form with e >= 136
    # (|x| >= 128), or int form whose high byte is not the sign extension
    # (|x| >= 257), certainly overflows/underflows before any arithmetic.
    if a.b[0] >= 136 or (a.b[0] == 0 and a.b[3] != a.b[1]):
        if a.b[1] & 0x80:
            return FP5(bytes(5))
        raise FPError(ERR_OVERFLOW)
    # n = half-up round of x/ln2
    t = oracle.mul(a, CINVLN2)
    nf = oracle.int_floor(oracle.add(t, CHALF))
    n = int(nf.to_fraction())
    if n > 140:
        raise FPError(ERR_OVERFLOW)
    if n < -140:
        return FP5(bytes(5))
    # Cody-Waite reduction: r = (x - n*L1) - n*L2
    nfp = encode(Fraction(n))
    r = oracle.sub(oracle.sub(a, oracle.mul(nfp, CL1)), oracle.mul(nfp, CL2))
    q = _poly(Q, r)
    return _scale2(q, n)


# ---- circular functions (spec section 4) ----
import gentrig
TT = gentrig._cached()
PS = TT["PS"]              # sin kernel coefficients, highest degree first
PC = TT["PC"]              # cos kernel coefficients, highest degree first
C2OPI = TT["named"]["C2OPI"]
CP1 = TT["named"]["CP1"]
CP2 = TT["named"]["CP2"]
CP3 = TT["named"]["CP3"]


def _negate_pk(a: FP5) -> FP5:
    """Mirror of the Z80 negate_pk: FP form flips the mantissa sign bit;
    int form two's-complement-negates the 16-bit field (zero canonical)."""
    if a.b[0] != 0:
        return FP5(bytes([a.b[0], a.b[1] ^ 0x80]) + a.b[2:])
    u = a.b[2] | (a.b[3] << 8)
    u = (-u) & 0xFFFF
    if u == 0:
        if a.b[1] != 0:            # input was -65536: +65536 needs FP form
            return FP5(bytes([0x91, 0, 0, 0, 0]))
        return FP5(bytes(5))
    return FP5(bytes([0, a.b[1] ^ 0xFF, u & 0xFF, u >> 8, 0]))


def _trig_core(a: FP5):
    """Shared reduction + both kernels, mirroring the Z80 op for op.
    Returns (n_low_byte, S, C)."""
    t = oracle.mul(a, C2OPI)
    nf = oracle.int_floor(oracle.add(t, CHALF))
    if nf.b[0] != 0:
        raise FPError(ERR_INVALID)      # |x*(2/pi)| beyond int form
    r = oracle.sub(a, oracle.mul(nf, CP1))
    r = oracle.sub(r, oracle.mul(nf, CP2))
    r = oracle.sub(r, oracle.mul(nf, CP3))
    w = oracle.mul(r, r)
    S = oracle.mul(r, _poly(PS, w))
    C = _poly(PC, w)
    return nf.b[2], S, C


def sin(a: FP5) -> FP5:
    if a.to_fraction() == 0:
        return FP5(bytes(5))
    nlo, S, C = _trig_core(a)
    q = nlo & 3
    v = C if (q & 1) else S
    return _negate_pk(v) if (q & 2) else v


def cos(a: FP5) -> FP5:
    if a.to_fraction() == 0:
        return INT_ONE
    nlo, S, C = _trig_core(a)
    q = (nlo + 1) & 3
    v = C if (q & 1) else S
    return _negate_pk(v) if (q & 2) else v


def tan(a: FP5) -> FP5:
    if a.to_fraction() == 0:
        return FP5(bytes(5))
    nlo, S, C = _trig_core(a)
    if nlo & 1:
        return _negate_pk(oracle.div(C, S))
    return oracle.div(S, C)


# ---- arctangent family (spec section 5) ----
PA = TT["PA"]              # atan kernel coefficients, highest degree first
CT8 = TT["named"]["CT8"]
CPI4 = TT["named"]["CPI4"]
CPI2 = TT["named"]["CPI2"]


def atn(a: FP5) -> FP5:
    if a.to_fraction() == 0:
        return FP5(bytes(5))
    neg = (a.b[1] & 0x80) != 0
    x = _negate_pk(a) if neg else a
    inv = oracle.cmp(x, ONE) == 1
    if inv:
        x = oracle.div(ONE, x)
    oct8 = oracle.cmp(x, CT8) == 1
    if oct8:
        x = oracle.div(oracle.sub(x, ONE), oracle.add(x, ONE))
    w = oracle.mul(x, x)
    k = oracle.mul(x, _poly(PA, w))
    if oct8:
        k = oracle.add(CPI4, k)
    if inv:
        k = oracle.sub(CPI2, k)
    return _negate_pk(k) if neg else k


def _asn_value(a: FP5) -> FP5:
    """asn(a) exactly as the Z80 computes it (shared by asn and acs).
    d = (1-|a|)(1+|a|), never the cancelling 1-a^2: the subtraction is
    Sterbenz-exact for |a| in [0.5,1], so d keeps full relative accuracy
    where asin conditioning is worst."""
    neg = (a.b[1] & 0x80) != 0
    ax = _negate_pk(a) if neg else a
    if oracle.cmp(ax, ONE) == 1:
        raise FPError(ERR_INVALID)      # |a| > 1: domain error, uniformly
    u = oracle.sub(ONE, ax)
    v = oracle.add(ONE, ax)
    s = oracle.sqrt(oracle.mul(u, v))
    if s.b == bytes(5):                 # |a| == 1 -> +/- pi/2
        val = CPI2
    else:
        val = atn(oracle.div(ax, s))
    return _negate_pk(val) if neg else val


def asn(a: FP5) -> FP5:
    return _asn_value(a)


def acs(a: FP5) -> FP5:
    return oracle.sub(CPI2, _asn_value(a))
