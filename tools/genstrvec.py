#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
"""String-conversion vectors. Header 'ZS1\\0' + count(4).
Record: op(1) len(1) payload(16) status(1) resLen(1) res(16) = 36 bytes.
op 12 = str2fp: payload=string; ok: res[0..4]=value, resLen=consumed.
op 13 = fp2str: payload[0..4]=value; res=string bytes, resLen=length."""
import random, struct, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import strconv, oracle
from oracle import FPError, encode
from fractions import Fraction

random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 7)
N = int(sys.argv[3]) if len(sys.argv) > 3 else 2500
recs = []

def emit12(s: bytes):
    if len(s) > 15: return
    try:
        r, used = strconv.str2fp(s)
        recs.append(bytes([12, len(s)]) + s.ljust(16, b"\0") + bytes([0, used])
                    + r.b.ljust(16, b"\0"))
    except FPError as ex:
        recs.append(bytes([12, len(s)]) + s.ljust(16, b"\0") + bytes([ex.code, 0])
                    + bytes(16))

def emit13(a):
    s = strconv.fp2str(a)
    assert len(s) <= 15
    recs.append(bytes([13, 5]) + a.b.ljust(16, b"\0") + bytes([0, len(s)])
                + s.ljust(16, b"\0"))

KAT = [b"0", b"1", b"-1", b"65535", b"-65535", b"12345", b"+42", b"000",
       b"0.0", b"0.5", b".25", b"123456789", b"1e2", b"1E-2", b"12abc",
       b"3.5E", b"1e40", b"1e-49", b"1e-40", b"9999999999", b"4294967295",
       b"-.5", b"1.", b"0.000000001", b"3.1415926", b"2.5", b"3.5",
       b"1e38", b"-1.7e38", b"2.9e-39", b"1E+3", b"6e4", b"65536",
       b"", b"+", b"-", b".", b"e5", b"abc", b"-0"]
for s in KAT:
    emit12(s)

def rand_fp5():
    r = random.random()
    if r < 0.3:
        return encode(Fraction(random.randint(-65535, 65535)))
    e = random.choice([1, 2, random.randint(3, 253), 254, 255,
                       random.randint(120, 170)])
    m = random.getrandbits(31) | (1 << 31)
    s = random.choice([1, -1])
    return encode(s * Fraction(m) * Fraction(2) ** (e - 160), prefer_int=False)

for _ in range(N):
    digs = random.randint(1, 12)
    mant = "".join(random.choice("0123456789") for _ in range(digs))
    dp = random.randint(0, digs)
    txt = mant[:dp] + "." + mant[dp:]
    if txt.startswith("."): txt = "0" + txt
    if txt.endswith("."): txt = txt[:-1]
    ex = random.randint(-42, 42)
    sign = random.choice(["", "-", "+"])
    form = random.choice([f"{txt}", f"{txt}e{ex}", f"{txt}E{ex}"])
    emit12((sign + form).encode())
    a = rand_fp5()
    emit13(a)
    emit12(strconv.fp2str(a))          # parse what we print

out = sys.argv[1] if len(sys.argv) > 1 else "tests/vectors/str.bin"
with open(out, "wb") as f:
    f.write(b"ZS1\0")
    f.write(struct.pack("<I", len(recs)))
    f.write(b"".join(recs))
print(f"{len(recs)} string vectors -> {out}")
