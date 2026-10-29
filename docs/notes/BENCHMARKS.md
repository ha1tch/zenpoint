# Three-way speed benchmark: Vickers / OpenSE 3.2.1 / zenpoint

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-03 (after the register-resident mul/div rework)

T-states per operation, counted by zen80 v0.5.6 over 520 shared operand
vectors (tools/genbench.py, seed 42; identical 5-byte operand bits fed
to all three). Memory footprint of values is identical by construction
— the format is bit-compatible — so cycle cost is the whole comparison.

Method (tests/bench/main.go): the two ROMs are driven through RST 28
calculator bytecode, the only interface their transcendentals expose;
an empty-program baseline (RST 28 + end-calc) is measured and
subtracted, but the ROM figures still include per-opcode calculator
dispatch (a few hundred T) that any real caller also pays. zenpoint is
called at its entry table, baseline-subtracted the same way. Every
timed run's result was sanity-checked against the true value; runs that
error are excluded (none were, over this operand set). The Vickers ROM
is the canonical 48K image from the Debian spectrum-roms package,
measured locally and not redistributed; OpenSE 3.2.1 was assembled from
its published source with Pasmo.

## Median T-states (min–max over the vector set)

| op   | Vickers | OpenSE 3.2.1 | zenpoint | zp vs Vickers | zp vs OpenSE |
|------|--------:|-------------:|---------:|--------------:|-------------:|
| add  |   2,001 |        2,037 |    1,224 | 1.6× faster | 1.7× faster |
| sub  |   2,239 |        2,275 |    1,625 | 1.4× faster | 1.4× faster |
| mul  |   5,331 |        5,367 |    5,152 | 1.03× faster | 1.04× faster |
| div  |   7,060 |        7,096 |    7,014 | 1.01× faster | 1.01× faster |
| sqrt | 380,125 |      117,263 |   48,725 | 7.8× faster | 2.4× faster |
| ln   | 228,439 |      218,924 |   57,515 | 4.0× faster | 3.8× faster |
| exp  | 147,357 |      142,823 |   78,509 | 1.9× faster | 1.8× faster |
| sin  | 143,982 |      138,051 |   72,620 | 2.0× faster | 1.9× faster |
| cos  | 150,340 |      143,667 |   71,991 | 2.1× faster | 2.0× faster |
| tan  | 303,335 |      290,805 |  112,952 | 2.7× faster | 2.6× faster |
| atn  | 215,246 |      208,244 |   74,848 | 2.9× faster | 2.8× faster |
| asn  | 608,748 |      357,568 |  134,547 | 4.5× faster | 2.7× faster |
| acs  | 614,665 |      361,545 |  135,968 | 4.5× faster | 2.7× faster |

## History

The first measurement (before the rework) had zenpoint mul at 7,058
and div at 12,311 — 1.3× and 1.7× slower than the ROMs. Two changes
closed it, both leaving every result bit identical (full differential
gate, two 118k-vector seeds):

1. **Register-resident operands.** Both loops kept the second operand
   in a stack frame read through (IX+d) at 19T per access. mul now
   holds the multiplicand in alt-BC and IXH:IXL (conditional add 176T
   → ~50T, carry into the high half by an early-out inc chain); div
   holds the divisor in main-BC/alt-BC so each trial subtract is two
   `sbc hl,bc` (108T → 42T).
2. **div develops 34 quotient bits, not 40.** The routine already
   jammed "remainder ≠ 0" into the sticky bit, which makes quotient
   bits beyond guard+1 mathematically redundant: 32 loop iterations
   plus two unrolled guard-bit steps give the identical RNE result.
   (One subtlety cost a debugging round: when q_int shifts the
   mantissa right, the ejected sticky-jam bit must be re-jammed, not
   dropped.)

Every transcendental sped up in the same commit for free — they are
built on mul/div (ln 74.6k → 57.5k, asn 163.5k → 134.5k).

## Reading the numbers

- zenpoint now leads on all thirteen operations at equal-or-better
  accuracy (RNE arithmetic, ≤2.3 ulp transcendentals vs the ROMs'
  ~7–8 digits). mul/div parity was the deliberate stopping point on
  plain Z80: quarter-square table multipliers were studied and
  rejected — with the operands register-resident the bit-serial loop
  already sits at 5.2k, and the table engine's 64-bit accumulation
  (register-starved, through IX) lands at ~4.3–5k: noise, bought with
  512–1024 table bytes. Tables serve no purpose here.
- OpenSE vs Vickers: identical arithmetic within 2%; dramatically
  better exactly where it rewrote routines (sqrt 3.2×, asn/acs 1.7×).

## Spectrum Next build (Z80N hardware multiply)

A separate benchmark category: Z80N's `MUL D,E` exists only on
Next-class machines (Spectrum Next, and compatibles implementing the
extended set), so these figures never mix with the three-way table
above. `src/zenpoint_next.asm` selects a Comba engine of sixteen
hardware multiplies (src/mulz80n.asm) that forms the same exact 64-bit
product — the full differential gate runs on this build too, and every
result is bit-identical to the plain-Z80 build. Same vectors, zen80 in
Z80N mode:

| op   | zenpoint (Z80) | zenpoint-next | gain | next vs Vickers |
|------|---------------:|--------------:|-----:|----------------:|
| mul  |          5,152 |         2,679 | 1.9× | 2.0× faster |
| ln   |         57,515 |        41,188 | 1.4× | 5.5× faster |
| exp  |         78,509 |        53,863 | 1.5× | 2.7× faster |
| sin  |         72,620 |        51,362 | 1.4× | 2.8× faster |
| cos  |         71,991 |        50,575 | 1.4× | 3.0× faster |
| tan  |        112,952 |        79,725 | 1.4× | 3.8× faster |
| atn  |         74,848 |        53,279 | 1.4× | 4.0× faster |
| asn  |        134,547 |       109,909 | 1.2× | 5.5× faster |
| acs  |        135,968 |       111,330 | 1.2× | 5.5× faster |

add/sub/div/sqrt are unchanged (they contain no multiplies). The
engine costs +292 bytes in the Next build only; the plain build is
byte-identical to before.
