#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
# Copyright (c) 2026 haitch <h@ual.li>
"""zenpoint oracle: exact reference model of the 5-byte format and its
improved-mode semantics, per docs/spec/format.md. Pure integer/Fraction
arithmetic; this file is the ground truth the Z80 implementation is
differentially tested against."""

from fractions import Fraction
from dataclasses import dataclass

# Error codes (spec section 4)
ERR_OVERFLOW = 1
ERR_INVALID = 2
ERR_DIVZERO = 3


class FPError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(f"fp error {code}")


@dataclass(frozen=True)
class FP5:
    """A 5-byte value, held in canonical encoded form."""
    b: bytes  # exactly 5 bytes

    def __post_init__(self):
        assert len(self.b) == 5

    @property
    def is_int_form(self):
        return self.b[0] == 0

    def to_fraction(self) -> Fraction:
        e, m1, m2, m3, m4 = self.b
        if e == 0:
            sign, lo, hi = m1, m2, m3
            v = lo | (hi << 8)
            if sign == 0xFF:
                v = v - 0x10000
            elif sign != 0x00:
                raise FPError(ERR_INVALID)
            return Fraction(v)
        neg = (m1 & 0x80) != 0
        M = ((m1 | 0x80) << 24) | (m2 << 16) | (m3 << 8) | m4
        v = Fraction(M, 1) * Fraction(2) ** (e - 160)
        return -v if neg else v


def _rne(num: int, den: int) -> int:
    """Round num/den (both positive ints) to nearest integer, ties to even."""
    q, r = divmod(num, den)
    if 2 * r > den or (2 * r == den and (q & 1)):
        q += 1
    return q


def encode(x: Fraction, prefer_int: bool = True) -> FP5:
    """Encode an exact Fraction as a 5-byte value with RNE.
    prefer_int: integers in range use the small-integer form."""
    if x == 0:
        return FP5(bytes(5))
    if prefer_int and x.denominator == 1 and -65535 <= x <= 65535:
        v = int(x)
        sign = 0x00 if v >= 0 else 0xFF
        u = v & 0xFFFF
        return FP5(bytes([0, sign, u & 0xFF, (u >> 8) & 0xFF, 0]))
    neg = x < 0
    a = -x if neg else x
    # Find e with 2^31 <= a * 2^(160-e) < 2^32, i.e. 2^(e-129) <= a < 2^(e-128)
    e = a.numerator.bit_length() - a.denominator.bit_length() + 129
    # bit_length estimate can be off by one; correct exactly.
    while a >= Fraction(2) ** (e - 128):
        e += 1
    while a < Fraction(2) ** (e - 129):
        e -= 1
    scaled = a * Fraction(2) ** (160 - e)  # in [2^31, 2^32)
    M = _rne(scaled.numerator, scaled.denominator)
    if M == 1 << 32:  # rounding carried
        M = 1 << 31
        e += 1
    if e > 255:
        raise FPError(ERR_OVERFLOW)
    if e < 1:
        return FP5(bytes(5))  # silent underflow flush (spec 2.4)
    m1 = (M >> 24) & 0x7F
    if neg:
        m1 |= 0x80
    return FP5(bytes([e, m1, (M >> 16) & 0xFF, (M >> 8) & 0xFF, M & 0xFF]))


# ---- arithmetic (spec section 2) ----

def _both_int(a: FP5, b: FP5) -> bool:
    return a.is_int_form and b.is_int_form


def add(a: FP5, b: FP5) -> FP5:
    r = a.to_fraction() + b.to_fraction()
    return encode(r, prefer_int=_both_int(a, b) and -65535 <= r <= 65535)


def sub(a: FP5, b: FP5) -> FP5:
    r = a.to_fraction() - b.to_fraction()
    return encode(r, prefer_int=_both_int(a, b) and -65535 <= r <= 65535)


def mul(a: FP5, b: FP5) -> FP5:
    r = a.to_fraction() * b.to_fraction()
    return encode(r, prefer_int=_both_int(a, b) and -65535 <= r <= 65535)


def div(a: FP5, b: FP5) -> FP5:
    bv = b.to_fraction()
    if bv == 0:
        raise FPError(ERR_DIVZERO)
    return encode(a.to_fraction() / bv, prefer_int=False)


def cmp(a: FP5, b: FP5) -> int:
    d = a.to_fraction() - b.to_fraction()
    return (d > 0) - (d < 0)


def int_floor(a: FP5) -> FP5:
    import math
    v = a.to_fraction()
    f = Fraction(math.floor(v))
    return encode(f, prefer_int=True)


def trunc(a: FP5) -> FP5:
    v = a.to_fraction()
    t = Fraction(int(v))  # int() truncates toward zero
    return encode(t, prefer_int=True)


# ---- IEEE-754 interchange (spec section 3) ----

def _ieee_encode(x: Fraction, mant_bits: int, exp_bits: int) -> int:
    """Exact Fraction -> IEEE bit pattern, RNE, denormal support.
    Raises FPError(ERR_OVERFLOW) if the rounded magnitude exceeds the format."""
    if x == 0:
        return 0
    bias = (1 << (exp_bits - 1)) - 1
    neg = x < 0
    a = -x if neg else x
    k = a.numerator.bit_length() - a.denominator.bit_length()
    while a >= Fraction(2) ** (k + 1):
        k += 1
    while a < Fraction(2) ** k:
        k -= 1
    # normal candidate: significand = a / 2^k in [1,2), field = (sig-1)*2^mant_bits
    if k + bias >= 1:
        scaled = a * Fraction(2) ** (mant_bits - k)
        M = _rne(scaled.numerator, scaled.denominator)  # in [2^mant, 2^mant+1)
        if M == 1 << (mant_bits + 1):
            M >>= 1
            k += 1
        exp_field = k + bias
        if exp_field >= (1 << exp_bits) - 1:
            raise FPError(ERR_OVERFLOW)
        bits = (exp_field << mant_bits) | (M - (1 << mant_bits))
    else:
        # denormal: value = f * 2^(1 - bias - mant_bits), f integer
        scaled = a * Fraction(2) ** (mant_bits + bias - 1)
        f = _rne(scaled.numerator, scaled.denominator)
        if f >= 1 << mant_bits:  # rounded up into the smallest normal
            bits = 1 << mant_bits
        else:
            bits = f  # f == 0 means flush to zero
    if neg and bits != 0:
        bits |= 1 << (exp_bits + mant_bits)
    return bits


def _ieee_decode(bits: int, mant_bits: int, exp_bits: int) -> Fraction:
    """IEEE bit pattern -> exact Fraction. Raises ERR_INVALID on Inf/NaN.
    -0.0 decodes to 0."""
    bias = (1 << (exp_bits - 1)) - 1
    sign = (bits >> (exp_bits + mant_bits)) & 1
    exp_field = (bits >> mant_bits) & ((1 << exp_bits) - 1)
    frac = bits & ((1 << mant_bits) - 1)
    if exp_field == (1 << exp_bits) - 1:
        raise FPError(ERR_INVALID)  # Inf or NaN
    if exp_field == 0:
        v = Fraction(frac) * Fraction(2) ** (1 - bias - mant_bits)
    else:
        v = Fraction(frac + (1 << mant_bits)) * Fraction(2) ** (exp_field - bias - mant_bits)
    if v == 0:
        return Fraction(0)
    return -v if sign else v


def to_f64(a: FP5) -> bytes:
    bits = _ieee_encode(a.to_fraction(), 52, 11)  # cannot overflow from 5-byte range
    return bits.to_bytes(8, "little")


def from_f64(raw: bytes) -> FP5:
    v = _ieee_decode(int.from_bytes(raw, "little"), 52, 11)
    return encode(v, prefer_int=False)


def to_f32(a: FP5) -> bytes:
    # Never overflows: the 5-byte maximum is 1.99..*2^126, half of
    # binary32's max (Sinclair mantissa in [0.5,1) vs IEEE [1,2)).
    bits = _ieee_encode(a.to_fraction(), 23, 8)
    return bits.to_bytes(4, "little")


def from_f32(raw: bytes) -> FP5:
    v = _ieee_decode(int.from_bytes(raw, "little"), 23, 8)
    return encode(v, prefer_int=False)


def sqrt(a: FP5) -> FP5:
    """Correctly rounded square root per docs/spec/transcendentals.md sec.1."""
    v = a.to_fraction()
    if v < 0:
        raise FPError(ERR_INVALID)
    if v == 0:
        return FP5(bytes(5))
    # unpack (int form normalizes through to_fraction/encode)
    fp = encode(v, prefer_int=False)
    e = fp.b[0]
    M = ((fp.b[1] | 0x80) << 24) | (fp.b[2] << 16) | (fp.b[3] << 8) | fp.b[4]
    er = (e + 128 + (e & 1)) >> 1
    N = M << 32
    if e & 1:
        N >>= 1
    import math
    root = math.isqrt(N)              # same outcome as the restoring method
    rem = N - root * root
    if rem > root:
        root += 1
        if root == 1 << 32:
            root = 1 << 31
            er += 1
    m1 = (root >> 24) & 0x7F
    return FP5(bytes([er, m1, (root >> 16) & 0xFF, (root >> 8) & 0xFF,
                      root & 0xFF]))
