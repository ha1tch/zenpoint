# zenpoint specification — transcendental functions (M3)

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-02
Status: M3 in progress. Algorithm-defined per the accepted testing
contract: each recipe is implemented twice (Python oracle, Z80) and
differential-tested bit-exact; accuracy vs the true function is measured
against mpmath once and documented.

## 1. Square root (`fp_sqrt`)

Negative input: error 2 (invalid). Zero: zero. Otherwise the result is
**correctly rounded** (RNE) — not merely faithful — via an exact integer
method; no seed tables, no iteration-count tuning.

Algorithm. Unpack to M ∈ [2^31, 2^32) and exponent e (small-integer form
normalizes first):

1. **Exponent split.** er = (e + 128 + (e AND 1)) >> 1. Build the 64-bit
   radicand N = M << 32, then shift N right once when e is odd
   (net N = M·2^32 or M·2^31, so N ∈ [2^62, 2^64) and
   value = N · 2^(2·er − 320)).
2. **Binary restoring square root.** 32 iterations of the classic
   digit-by-digit integer method: bring down two bits of N into the
   remainder; trial-subtract (root·4 + 1); accept sets the new root bit.
   Yields root = floor(sqrt(N)) ∈ [2^31, 2^32) — already normalized —
   and the exact remainder rem = N − root².
3. **Rounding.** The true value lies in [root, root+1); its fractional
   part exceeds ½ exactly when rem > root (rem = root is below the tie
   point since (root+½)² = root²+root+¼ > N). Round up iff rem > root;
   a mantissa carry to 2^32 becomes root = 2^31 with er += 1.
4. Result: mantissa root, exponent er (er ∈ [65, 192]: no overflow or
   underflow is possible), sign positive. FP form always.

API: HL = source, IX = result. CF=0 on success; CF=1, A=2 for negative
input. Entry table slot 8027h.

## 2. Natural logarithm (`fp_ln`)

Zero or negative input: error 2 (invalid). Otherwise, with the input
normalized to FP form (mantissa M, exponent e):

1. **Range split.** s = value with exponent forced to 128, so
   s ∈ [0.5, 1); k = e − 128. If s < sqrt(2)/2 (compare against the
   stored constant `CSQRT2O2`), double s (exact exponent bump) and
   decrement k. Now s ∈ [sqrt(2)/2, sqrt(2)) and value = s·2^k.
2. **Kernel.** z = (s − 1)/(s + 1). The subtraction is Sterbenz-exact
   in this range. If z = 0 the kernel is 0; otherwise w = z²,
   ln(s) = 2z·P(w) with P the degree-4 Chebyshev fit emitted by
   `tools/gencoeff.py` (fit error 4.3e-12, comment header of
   `src/lnexpconst.asm`).
3. **Reassembly.** result = k·ln2 + ln(s), with k encoded as an
   integer and `CLN2` the stored 5-byte ln 2. All steps use the
   package's own RNE add/sub/mul/div, in this exact order, so oracle
   and Z80 agree bit for bit.

Measured accuracy vs mpmath: worst 1.29 ulp (`tests/test_transc.py`).
API: HL = source, IX = result. CF=0 ok; CF=1, A=2 domain error.
Entry table slot 802Ah.

## 3. Exponential (`fp_exp`)

exp(0) = 1 (small-integer form), exactly.

1. **Magnitude pre-gate**, before any arithmetic: an input in FP form
   with exponent byte ≥ 136 (|x| ≥ 128), or in integer form whose high
   magnitude byte is not the sign extension (|x| ≥ 257), certainly
   overflows or underflows: positive → error 1, negative → 0. This also
   guarantees every later intermediate (x/ln2, n, n·L1) stays in safe
   range, so no interior operation can fault.
2. **Reduction.** n = floor(x·(1/ln2) + 0.5) — a half-up round, kept as
   a 16-bit integer. n > 140 → error 1; n < −140 → result 0. Cody-Waite:
   r = (x − n·L1) − n·L2, where `CL1` is ln 2 with its mantissa cut to
   16 bits (so n·L1 is exact for |n| ≤ 140) and `CL2` = ln2 − L1.
   r ∈ [−ln2/2, ln2/2] up to rounding.
3. **Kernel.** q = Q(r), the degree-8 Chebyshev fit from
   `tools/gencoeff.py` (fit error 8.1e-13), evaluated by Horner with
   RNE ops.
4. **Scaling.** result = q·2^n via the exponent byte (`fp_scale2`):
   overflow → error 1, underflow flushes to 0.

Measured accuracy vs mpmath: worst 0.98 ulp; exp(ln x) round-trip
stays within 0.31 of the conditioning bound (`tests/test_transc.py`).
API: HL = source, IX = result. CF=0 ok; CF=1, A=1 overflow.
Entry table slot 802Dh.

## 4. Circular functions (`fp_sin`, `fp_cos`, `fp_tan`)

Arguments in radians. sin(0) = tan(0) = 0 and cos(0) = 1 (integer
form), exactly. All three share one reduction:

1. **Quarter-circle count.** n = floor(x·(2/π) + 0.5), the nearest
   quarter-circle, kept in integer form. If the floor result does not
   fit integer form (|x·(2/π)| ≥ 65536, i.e. |x| beyond ≈ 102 943):
   error 2 — the reduction range is exceeded and no meaningful result
   exists at 32-bit precision. Only n's low byte is consumed further.
2. **Three-term Cody-Waite.** r = ((x − n·P1) − n·P2) − n·P3, with
   `CP1` = π/2 truncated to 16 mantissa bits, `CP2` the next 16 bits
   (both products exact in the 32-bit mantissa for every gated n), and
   `CP3` the 5-byte remainder — the only product that rounds. |r| ≤ π/4
   plus rounding slack.
3. **Kernels.** w = r², S = r·PS(w), C = PC(w): degree-4 and degree-5
   Chebyshev fits from `tools/gentrig.py` (fit errors 4.4e-12 and
   5.7e-14; table comment header of `src/trigconst.asm`).
4. **Selection.** q = n mod 4 (low two bits; two's complement makes
   negative n correct for free). sin: q = 0,1,2,3 → S, C, −S, −C.
   cos: same table at q+1. tan: q even → S/C, q odd → −(C/S), the
   division delegated to `fp_div` — near a pole the quotient may
   overflow (error 1 propagates) and at a representable zero of the
   denominator tan reports error 3.
   Negation is the exact packed negate (sign-bit flip), never a
   rounding operation.

Measured accuracy vs mpmath over the full reduction range: sin 1.76,
cos 1.62 ulp worst; tan stays within 0.39 of its conditioning bound
6 + |tan x|/4 ulp (`tests/test_transc.py`). Near zeros of sin/cos the
error is bounded absolutely by the reduction residual rather than
relatively — inherent to fixed-format argument reduction.
API: HL = source, IX = result, radians. CF=0 ok; CF=1 with A=2
(reduction range), A=1 (tan overflow), A=3 (tan pole). Entry table
slots 8030h, 8033h, 8036h.

## 5. Arctangent family (`fp_atn`, `fp_asn`, `fp_acs`)

atn accepts every representable value — no range gate; atn(0) = 0
exactly. Reduction is by exact sign symmetry plus two folds:

1. **Sign.** Work on |x| (exact packed negate); reapply at the end.
2. **Reciprocal fold.** |x| > 1: x ← 1/x, result later subtracted from
   π/2.
3. **Octant fold.** x > tan(π/8) (`CT8`): x ← (x−1)/(x+1), result
   later offset by +π/4. Kernel argument |z| ≤ tan(π/8) either way.
4. **Kernel.** w = z², atn(z) = z·PA(w), the degree-7 Chebyshev fit
   from `tools/gentrig.py` (fit error 8.1e-13). Then the folds unwind
   in order: +π/4 if octant-folded, π/2 − k if reciprocal-folded,
   negate if sign-folded.

asn and acs derive from atn, on |x| with the sign reapplied exactly
(asn is odd). |x| > 1 is rejected up front with error 2 — a uniform
pre-gate, so no interior operation can fault. The discriminant is
**factored**: d = (1 − |x|)(1 + |x|), never the cancelling 1 − x²;
the subtraction is Sterbenz-exact for |x| ∈ [0.5, 1], exactly where
asin's conditioning is worst (the naive form measured 5.5+ ulp, the
factored form 2.3). Then s = sqrt(d), asn = atn(|x|/s), with s = 0
(exactly |x| = 1) short-circuiting to π/2 (`CPI2`).
acs = π/2 − asn, computed from the identical asn value.

Measured accuracy vs mpmath: atn 1.94, asn 2.29 ulp worst. acs is
exact at +1 and good in absolute terms everywhere, but near +1 the
π/2 − asn cancellation makes the *relative* error large while the
absolute error stays at ~1 ulp of π/2 (measured 7.8e-10) — the test
asserts ≤ 6 ulp where the result exceeds 0.1 and 1.5e-9 absolutely
elsewhere (`tests/test_transc.py`). This is the standard cost of the
derived form; the QUIRKS-mode ROM computes acs the same way.
API: HL = source, IX = result, radians. CF=0 ok; asn/acs CF=1, A=2
for |x| > 1. Entry table slots 8039h, 803Ch, 803Fh.

## 6. Planned

M3 is complete when sections 1–5 are all differential-green. The
extended-math wave (register items T-06..T-14) follows as its own
programme.
