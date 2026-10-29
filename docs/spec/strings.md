# zenpoint specification — decimal string conversion (M4)

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-02
Status: M4 draft. Improved-mode semantics; QUIRKS mode (ROM-identical
DEC-TO-FP / PRINT-FP behavior) comes with M5.

Both conversions are **algorithm-defined**: the exact fixed-point recipe
below is implemented twice (Python oracle, Z80) and differential-tested
bit-exact / byte-exact. Accuracy relative to the true decimal value is a
measured, documented property of the recipe, not a per-call promise.

## 1. String to 5-byte (`fp_str2fp`)

Grammar (ASCII): `[+|-] digits [ . [digits] ] [ (E|e) [+|-] digits ]`,
where at least one decimal digit must appear before the exponent marker
(a leading `.` is permitted: `.5`). Anything else: error 2 (invalid).
Parsing stops at the first character that cannot extend the number; the
routine reports the consumed length.

Algorithm:

1. **Digit accumulation.** Significant digits (leading zeros skipped)
   accumulate into a 32-bit integer I, value-capped: a digit is taken
   while I ≤ 429 496 728 (so I·10+9 still fits 32 bits — up to 10
   digits). Further mantissa digits are dropped:
   each dropped *integer-part* digit increments the decimal exponent
   `dexp`; dropped *fraction* digits only set a sticky flag when
   nonzero. In-capacity fraction digits decrement `dexp`. The E-exponent
   (clamped to ±999 during parse) is added to `dexp`.
2. **Sticky jam.** If sticky is set, I := I | 1 (jam into the integer's
   LSB — breaks downstream rounding ties in the dropped digits' favor).
3. **Trivial cases.** I = 0 → result 0. `dexp` > 39 → error 1 (overflow;
   I ≥ 1 forces magnitude > the 5-byte maximum). `dexp` < −49 → result 0
   (I < 2^32 forces magnitude below 2^−128).
4. **Seed.** `dexp` = 0 and I ≤ 65535: small-integer form (sign applied);
   done. Otherwise encode I exactly as FP form.
5. **Power-of-ten scaling.** For bit k = 0..5 of |dexp|: if set, multiply
   (dexp > 0) or divide (dexp < 0) by the constant P10[k], using the
   package's own RNE multiply/divide. P10 = the 5-byte encodings of
   10^1, 10^2, 10^4, 10^8, 10^16, 10^32 (the first four exact; the last
   two correctly rounded).
6. Apply the sign. Composite error, measured over randomized campaigns:
   ≤ 3 ulp for inputs within the format's ~9.6-digit precision; ≤ 16 ulp
   worst case for longer inputs, where dropped-tail value dominates
   (8.8 ulp measured; the bound is asserted by the test suite). Integers
   of up to 10 in-cap digits with dexp = 0 convert exactly.

API (library): HL = string pointer, IX = result. Out: CF=0, A = number
of characters consumed; CF=1 with A = error code (1 overflow, 2 invalid).

## 2. 5-byte to string (`fp_fp2str`)

Output is Sinclair-like: up to 8 significant digits, fixed notation for
decimal exponents −5..12, E-notation outside, trailing fraction zeros
stripped, no `+` on positive numbers, `-` prefix on negatives.

Algorithm:

1. Zero → `0`. Small-integer form → plain decimal digits of the stored
   value (sign first if negative).
2. FP form: work on the magnitude; remember the sign.
3. **Coarse decimal scaling.** Estimate e10 ≈ (e − 129) × 77 / 256
   (integer arithmetic; 77/256 approximates log10(2)). Using the P10
   table bits of the estimate's magnitude, divide (positive estimate) or
   multiply (negative) to bring the value near [10^7, 10^8).
4. **Fine adjustment.** While value ≥ 10^8: divide by 10, e10 += 1.
   While value < 10^7: multiply by 10, e10 −= 1. (After the coarse step
   this is at most a few iterations.) e10 counts the weight of the first
   digit: magnitude = N8 × 10^(e10−7).
5. **Digit rounding.** N8 = floor(value + 0.5) (half-up display
   rounding, via the package add and floor). If N8 = 10^8: N8 = 10^7,
   e10 += 1.
6. **Digit extraction.** N8 (< 2^27, held exactly) is split into 8
   decimal digits by repeated integer division by 10. Strip trailing
   zeros → digits d1..dn (n ≥ 1).
7. **Layout.** With E = e10:
   - 0 ≤ E ≤ 12: fixed. If E ≥ n−1: digits then (E−n+1) zeros.
     Else: d1..d(E+1), `.`, remainder.
   - −5 ≤ E < 0: `0.`, (−E−1) zeros, digits.
   - otherwise: d1 [`.` d2..dn] `E` [−] decimal(|E|).

API (library): HL = source, DE = output buffer. Out: CF=0, A = length,
buffer NUL-terminated. Maximum length 15 bytes including the NUL
(`-1.2345678E-38`). No errors are possible.

## 3. Shared constant table

P10[0..5] = 5-byte values of 10^1, 10^2, 10^4, 10^8, 10^16, 10^32,
plus C7 = 10^7 and C8 = 10^8 (both exact) and CHALF = 0.5. All emitted
by `tools/genconst.py` from the oracle encoder — never hand-typed —
into `src/p10const.asm` (assembly DEFB) and importable Python.
