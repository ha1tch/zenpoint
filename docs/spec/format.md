# zenpoint specification — number format and improved-mode semantics

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-02
Status: M0 draft. Clean-room phase-one document: facts and definitions only,
no third-party code. This document is the authority the oracle and the Z80
implementation both answer to.

## 1. The 5-byte value

A value is five bytes `[e, m1, m2, m3, m4]`.

### 1.1 Small-integer form (e = 0)

| Byte | Meaning |
|---|---|
| e | 0 |
| m1 | sign: 00h positive, FFh negative |
| m2, m3 | 16-bit magnitude, little-endian; a negative value n is stored as 65536 minus its magnitude (two's complement) |
| m4 | 0 |

Range: −65535 … +65535, exact. Zero is `[0, 00, 00, 00, 0]`; there is no
negative zero anywhere in the format.

### 1.2 Floating-point form (e ≠ 0)

- `e` is the biased exponent, 1…255.
- `m1..m4` big-endian mantissa; bit 7 of m1 is the **sign** (0 positive,
  1 negative), replacing the always-1 leading mantissa bit.
- Let M be the 32-bit mantissa with bit 31 forced to 1. Then

  value = ± M × 2^(e−160)   equivalently   ± (M/2^32) × 2^(e−128)

  with M/2^32 ∈ [0.5, 1).

- Magnitude range: 2^−128 ≤ \|x\| ≤ (1 − 2^−32) × 2^127 (≈ 1.7014 × 10^38).
  (Minimum: e = 1 with M = 2^31 gives 2^31 × 2^(1−160) = 2^−128.)
- Precision: 32 bits ≈ 9.6 significant decimal digits.

Normalization invariant: FP form always has bit 31 of M set. Encoders must
produce it; decoders may assume it.

## 2. Improved-mode arithmetic semantics

These are zenpoint's own definitions (QUIRKS mode, later, instead mirrors the
original ROM exactly).

1. **Correct rounding.** add, sub, mul, div return the exact mathematical
   result rounded to 32 mantissa bits by round-to-nearest, ties-to-even
   (RNE). This is the accuracy contract for the basic operations
   (resolves PLAN open decision 4 for basic ops; transcendental targets
   are defined with M3).
2. **Rounding carry.** If rounding carries the mantissa to 2^32, use
   M = 2^31 and increment e.
3. **Overflow.** e > 255 after rounding: error (see §4). The maximum
   magnitude is not saturating.
4. **Underflow.** e < 1 after rounding: flush to zero, silently. Signed
   zero does not exist; the result is the single zero.
5. **Small-integer paths.** If both operands are in small-integer form and
   the exact result of add, sub, or mul lies in −65535…65535, the result is
   in small-integer form. div always returns FP form. Arithmetic never
   auto-compresses an FP-form result to integer form; only INT, TRUNC, and
   explicit stacking/conversion entries produce integer form.
6. **INT** is floor (INT(−3.4) = −4), matching Sinclair BASIC's INT.
   **TRUNC** rounds toward zero. Either returns small-integer form when the
   result is in range, FP form otherwise.
7. **Comparison** is exact (unpack, compare sign/magnitude); both forms
   compare correctly against each other.
8. **Division by zero:** error.

## 3. IEEE-754 interchange

Decided policy (register T-02): **error return, never saturation**; underflow
below the 5-byte range flushes to zero, matching §2.4.

### 3.1 f64 pair (lossless direction)

- **Export, 5-byte → binary64: always exact.** 32-bit mantissa fits in 53;
  exponent range e−129 ∈ [−128, 126] is well inside binary64's. Integer form
  exports exactly. This is a standing test invariant: export∘import is the
  identity on every 5-byte value.
- **Import, binary64 → 5-byte:** RNE to 32 bits. \|x\| ≥ 2^127 after
  rounding: overflow error. Rounding is applied before the underflow
  test: a magnitude just below 2^−128 that RNE-rounds up to exactly
  2^−128 imports as 2^−128, not zero (matching §2.2's rounding carry). 0 < \|x\| < 2^−128 after rounding (including all binary64
  denormals): flush to zero. −0.0 imports as zero. Inf/NaN: error.

### 3.2 f32 pair (lossy direction)

- **Export, 5-byte → binary32:** RNE 32 → 24 mantissa bits. Values below
  2^−126 export as binary32 denormals (correctly RNE-rounded); the 5-byte
  minimum 2^−128 is representable as a denormal, so export never errors:
  the 5-byte maximum is 1.99… × 2^126, half of binary32's maximum, so
  overflow is impossible (note the convention gap — Sinclair mantissas
  are in [0.5, 1), IEEE significands in [1, 2)). Integer form with
  \|n\| < 2^24 exports exactly.
- **Import, binary32 → 5-byte:** exact for every normal with unbiased
  exponent ≤ 126. Normals with exponent 127 (\|x\| ≥ 2^127, i.e. above the
  5-byte maximum): overflow error. Denormals ≥ 2^−128: exact (their
  mantissas always fit). Denormals below 2^−128 after RNE: flush to zero,
  per the arithmetic underflow rule. −0.0 imports as
  zero. Inf/NaN: error.

Byte order at the interchange boundary: IEEE values are little-endian in
memory (z80-natural), i.e. binary32 as 4 bytes LSB first, binary64 as 8
bytes LSB first.

## 4. Error model (library builds)

- Success: carry flag clear.
- Error: carry flag set, A = error code:

| Code | Meaning |
|---|---|
| 1 | overflow (arithmetic or import above range) |
| 2 | invalid operand (Inf/NaN import) |
| 3 | division by zero |

No saturation anywhere; no error for underflow (silent flush to zero).
ROM builds map these to the original ROM error path (RST 8 mechanism) at the
pinned boundary; codes at that boundary follow the ROM's own error numbers,
defined in the interface spec.

## 5. Register conventions (library API, draft)

To be finalized with T-03 (ual calling convention). Working draft: operands
and results in memory via pointers (HL = op1/result, DE = op2), 5-byte
buffers; flags per §4. The register-resident accumulator optimization is an
internal matter for operation chains and does not leak into the API.
