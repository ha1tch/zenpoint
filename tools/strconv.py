#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""Oracle side of the M4 string conversions, implementing exactly the
algorithm in docs/spec/strings.md. Built on oracle.py's RNE operations so
the Z80 implementation can be differential-tested bit-exact."""
import sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from fractions import Fraction
import oracle
from oracle import FP5, FPError, encode, ERR_OVERFLOW, ERR_INVALID
from genconst import table

T = table()
P10 = [FP5(T[f"P10_{k}"]) for k in range(6)]
C1E7, C1E8, CHALF = FP5(T["C1E7"]), FP5(T["C1E8"]), FP5(T["CHALF"])
TEN = encode(Fraction(10))


def str2fp(s: bytes):
    """Returns (FP5, consumed). Raises FPError(ERR_INVALID/ERR_OVERFLOW)."""
    i, n = 0, len(s)
    neg = False
    if i < n and s[i] in b"+-":
        neg = s[i] == ord("-")
        i += 1
    I = 0
    sig = 0            # significant digits accumulated (0 = none yet)
    CAP = 429496728    # while I <= CAP, I*10+9 still fits in 32 bits
    dexp = 0
    sticky = False
    seen_digit = False
    # integer part
    while i < n and 0x30 <= s[i] <= 0x39:
        seen_digit = True
        d = s[i] - 0x30
        if sig == 0 and d == 0:
            pass                      # leading zero
        elif I <= CAP:
            I = I * 10 + d
            sig += 1
        else:
            dexp += 1
            if d:
                sticky = True
        i += 1
    if i < n and s[i] == ord("."):
        i += 1
        while i < n and 0x30 <= s[i] <= 0x39:
            seen_digit = True
            d = s[i] - 0x30
            if sig == 0 and d == 0:
                dexp -= 1             # leading zeros after the point scale
            elif I <= CAP:
                I = I * 10 + d
                sig += 1
                dexp -= 1
            else:
                if d:
                    sticky = True
            i += 1
    if not seen_digit:
        raise FPError(ERR_INVALID)
    if i < n and s[i] in b"Ee":
        j = i + 1
        eneg = False
        if j < n and s[j] in b"+-":
            eneg = s[j] == ord("-")
            j += 1
        if j < n and 0x30 <= s[j] <= 0x39:
            ev = 0
            while j < n and 0x30 <= s[j] <= 0x39:
                ev = min(999, ev * 10 + (s[j] - 0x30))
                j += 1
            dexp += -ev if eneg else ev
            i = j                     # consume exponent only if well-formed
    # sticky jam
    if sticky:
        I |= 1
    if I == 0:
        return encode(Fraction(0)), i
    if dexp > 39:
        raise FPError(ERR_OVERFLOW)
    if dexp < -49:
        return encode(Fraction(0)), i
    if dexp == 0 and I <= 65535:
        return encode(Fraction(-I if neg else I)), i
    r = encode(Fraction(I), prefer_int=False)
    m = abs(dexp)
    for k in range(6):
        if m & (1 << k):
            r = oracle.mul(r, P10[k]) if dexp > 0 else oracle.div(r, P10[k])
    if neg:
        rv = r.to_fraction()
        r = encode(-rv, prefer_int=False)
    return r, i


def _digits_of(v: int) -> str:
    return str(v)


def fp2str(a: FP5) -> bytes:
    v = a.to_fraction()
    if v == 0:
        return b"0"
    if a.is_int_form:
        return str(int(v)).encode()
    neg = v < 0
    if neg:
        a = encode(-v, prefer_int=False)
    # coarse decimal scaling from the binary exponent
    e = a.b[0]
    est = ((e - 129) * 77) >> 8 if e >= 129 else -(((129 - e) * 77 + 255) >> 8)
    e10 = 7 + est
    m = abs(est)
    r = a
    for k in range(6):
        if m & (1 << k):
            r = oracle.div(r, P10[k]) if est > 0 else oracle.mul(r, P10[k])
    # fine adjustment into [1e7, 1e8)
    while oracle.cmp(r, C1E8) >= 0:
        r = oracle.div(r, TEN)
        e10 += 1
    while oracle.cmp(r, C1E7) < 0:
        r = oracle.mul(r, TEN)
        e10 -= 1
    # half-up to integer
    r = oracle.add(r, CHALF)
    r = oracle.int_floor(r)
    n8 = int(r.to_fraction())
    if n8 >= 10**8:
        n8 = 10**7
        e10 += 1
    ds = _digits_of(n8)               # exactly 8 digits
    ds = ds.rstrip("0") or "0"
    n = len(ds)
    E = e10
    out = "-" if neg else ""
    if 0 <= E <= 12:
        if E >= n - 1:
            out += ds + "0" * (E - n + 1)
        else:
            out += ds[:E + 1] + "." + ds[E + 1:]
    elif -5 <= E < 0:
        out += "0." + "0" * (-E - 1) + ds
    else:
        out += ds[0]
        if n > 1:
            out += "." + ds[1:]
        out += "E" + str(E)
    return out.encode()
