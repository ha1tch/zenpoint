# zenpoint — Live Register

Version: 0.1.3
Last reviewed: 2026-09-04

Open actionable items only. Closed items move verbatim to `RESOLVED.md`.

Status legend: ✓ done · ◐ partial · ☐ not started · ✗ dropped

## Dormant guards

Not part of the default gate; each needs its own gating condition met
before it runs. The release gate checks every entry was exercised
since the last tag, or records the skip explicitly.

| Guard | Gating condition | Canonical invocation | Last exercised |
|-------|-------------------|-----------------------|-----------------|
| tests/e2e (real-emulator CIRCLE check) | needs a zenzx-headless built with the interim ROM embedded (ZENZX_ZP) | `ZENZX_ZP=/path/to/zenzx-headless-zenpoint tests/e2e/run.sh` | 2026-09-04, this sandbox, zenzx-headless-zenpoint built from build/rompatch/zenpoint-interim.rom (post colour/version-tracking change) -- PASS, 284/284 ink pixels both cases |

## Status table

| ID | Summary | Theme | Priority | Status | Blocks |
|----|---------|-------|----------|--------|--------|

| T-03 | Decide ual runtime calling convention for library API | api | P2 | ☐ | — |
| T-06 | pow(x,y): dedicated exponentiation with fast paths | extmath | P2 | ☐ | — |
| T-07 | atan2(y,x): two-argument arctangent, quadrant-correct | extmath | P2 | ☐ | — |
| T-08 | hypot(x,y): overflow-safe sqrt(x^2+y^2) | extmath | P3 | ☐ | — |
| T-09 | fmod: floating-point remainder | extmath | P3 | ☐ | — |
| T-10 | round and ceil rounding modes | extmath | P3 | ☐ | — |
| T-11 | fabs as a named routine | extmath | P3 | ☐ | — |
| T-12 | cbrt: dedicated cube root | extmath | P3 | ☐ | — |
| T-13 | Hyperbolic family sinh/cosh/tanh + inverses | extmath | P4 | ☐ | — |
| T-14 | fma: fused multiply-add | extmath | P4 | ☐ | — |
| T-15 | Spectrum Next ROM patch build (zenpoint at Vickers addresses, Z80N engine) | rom | P2 | ☐ | M6 |
| T-17 | M2 engine: fuse div+INT into integer division | perf | P3 | ☐ | M2 |
| T-20 | Reimplement three-argument DRAW as an integer arc (follow-on to T-18) | rom | P3 | ☐ | — |
| T-22 | Per-routine provenance notes missing from every source file except zenpoint.asm | provenance | P2 | ☐ | — |
| T-23 | Docs lag the shipped state: PLAN section 2 distribution text, README status line and QUIRKS wording | docs | P3 | ☐ | — |
## Items

## api

### T-03. Decide ual runtime calling convention for library API

Theme: api · Priority: P2 · Status: ☐

Needed by M7, decide by M4. Trigger: plan sec.8.

## extmath

### T-06. pow(x,y): dedicated exponentiation with fast paths

Theme: extmath · Priority: P2 · Status: ☐

Not exp(y*ln(x)) composition: wrong for negative base with integer exponent, mishandles x=0, imprecise for integer y (wants repeated squaring). Own routine with fast paths. Trigger: extended-math wave filing.

### T-07. atan2(y,x): two-argument arctangent, quadrant-correct

Theme: extmath · Priority: P2 · Status: ☐

Not derivable from one-argument atan without real quadrant logic; effectively mandatory for graphics/navigation angle-from-coordinates work. Trigger: extended-math wave filing.

### T-08. hypot(x,y): overflow-safe sqrt(x^2+y^2)

Theme: extmath · Priority: P3 · Status: ☐

Avoid intermediate overflow/underflow of naive x*x+y*y. Pairs with atan2 as the rectangular/polar toolkit. Trigger: extended-math wave filing.

### T-09. fmod: floating-point remainder

Theme: extmath · Priority: P3 · Status: ☐

INT/TRUNC are conversions, not remainder. Trigger: extended-math wave filing.

### T-10. round and ceil rounding modes

Theme: extmath · Priority: P3 · Status: ☐

INT (floor) and TRUNC exist; round (half away? define) and ceil are separate standard modes. Trigger: extended-math wave filing.

### T-11. fabs as a named routine

Theme: extmath · Priority: P3 · Status: ☐

Trivial (clear sign bit; int form sign byte) but used constantly; name it. Trigger: extended-math wave filing.

### T-12. cbrt: dedicated cube root

Theme: extmath · Priority: P3 · Status: ☐

Not pow(x, 1/3): that composition breaks for negative x; a dedicated odd-root routine does not. Trigger: extended-math wave filing.

### T-13. Hyperbolic family sinh/cosh/tanh + inverses

Theme: extmath · Priority: P4 · Status: ☐

Genuinely separate family from circular trig; worth-it call on an 8-bit target is open. Trigger: extended-math wave filing.

### T-14. fma: fused multiply-add

Theme: extmath · Priority: P4 · Status: ☐

A true fused version (single rounding via the guard machinery) could offer real precision wins; advanced addition, not baseline. Trigger: extended-math wave filing.

## rom

### T-15. Spectrum Next ROM patch build (zenpoint at Vickers addresses, Z80N engine)

Theme: rom · Priority: P2 · Status: ☐ · Blocks/after: M6

Ship zenpoint as a ROM patch for the Spectrum Next: replace the FP and
calculator region of the Next's 48K-compatible BASIC page (enNextZX.rom
page 3) at the classic Vickers addresses, using the Z80N hardware-multiply
engine (src/mulz80n.asm).

Motivation, measured 2026-09-03 against tbblue enNextZX.rom: the Next's
transcendental band 3699h-3862h is byte-identical to the 1982 Vickers ROM
(0 of 458 bytes differ); MULTIPLY differs by 9 bytes and DIVISION by 1
(hooks, not rewrites). NextZXOS's optimisation effort went into NextBASIC
% integer variables outside the calculator, and dec_to_fp (131/141 bytes
rewritten) for extended literal parsing. Next users therefore run stock
1982 floating point; the zenpoint-next build measured 2.0x faster on mul
and up to 7.8x on sqrt against exactly that code (docs/notes/BENCHMARKS.md).

Constraints found during the diff: page 3 carries ~836 changed bytes in
the FP region overall, concentrated in dec_to_fp, truncate/restack, and
the CALCULATE engine (193/830 bytes of hooks for NextBASIC opcodes), and
RST 28 vectors through the Next's ROM banking. A patch must preserve or
reconcile those hooks and the banking entry paths, not blindly overwrite
the band. Depends on the M6 fitting work and T-04 (Next entry-point delta
verification); the M2 engine work determines how much of the CALCULATE
band we can claim.

Trigger: swappable-ROM discussion and the enNextZX.rom byte-diff findings,
benchmarks session of 2026-09-03.

### T-20. Reimplement three-argument DRAW as an integer arc (follow-on to T-18)

Theme: rom · Priority: P3 · Status: ☐

Reimplement three-argument DRAW x,y,a as a proper arc, replacing the
calculator-driven rotation loop the same way T-18 replaced CIRCLE's
polygon.

Measured (disassembly, this session): the arc machinery at
2394h-2476h is 227 bytes. It computes a per-step rotation angle once
via the calculator (sin/cos), then loops DJNZ-counted, applying one
full RST 28h sequence per step -- two multiplies + subtract for the
new x, two multiplies + add for the new y (a hand-rolled complex
rotation). Same character of expense as the old CIRCLE polygon: real
per-pixel work running inside the FP engine instead of in Z80
integer code.

The fix is NOT a straight port of T-18's approach. CIRCLE only ever
needed one FP value (the radius) and could emit all points via 8-way
symmetry. An arc needs the circle's centre AND radius derived from
the two endpoints and the angle (chord length via sqrt, radius via
chord/(2*sin(angle/2)), centre via a perpendicular offset from the
chord midpoint -- all one-time FP work, using the kept, unmodified
SIN/SQR in the Vickers band), then an integer walk bounded to only
the requested angular span between the two endpoints, in the correct
direction, crossing octant boundaries correctly -- real bookkeeping
CIRCLE's uniform 8-way emission didn't need.

At least one edge case needs verifying against the ROM's actual
algorithm before implementation, not assumed from memory: a
zero-length chord (DRAW 0,0,a) with a nonzero angle.

Not blocking M6: T-19 lands a straight-line fallback for the
three-argument form in the interim ROM, so DRAW is correct (if less
capable) without this. This ticket is the follow-on to restore real
arcs once the octant-walking algorithm is designed and differentially
verified the way T-18's was (tools/gencircle.py-style Python
reference, zen80 harness, then the real-emulator keyboard-entry path
per tests/e2e).

## perf

### T-17. M2 engine: fuse div+INT into integer division

Theme: perf · Priority: P3 · Status: ☐ · Blocks/after: M2

Calculator-engine fusion of div followed by INT (M2 tier). BASIC's
INT(a/b) idiom reaches the RST 28 engine as a div opcode then an fint
opcode; a peephole in our M2 engine can execute the pair as one integer
division for integer operands, skipping the FP development entirely —
invisible in results, large in time. Belongs to the M2 calculator
engine work and lands free in the T-15 Next ROM variant and any
integer-leaning ROM build. Requires T-05 (opcode table) and M2.

Trigger: swappable integer-turbo ROM discussion 2026-09-03.

## rompatch

## provenance

### T-22. Per-routine provenance notes missing from every source file except zenpoint.asm

Theme: provenance · Priority: P2 · Status: ☐

PLAN section 2 requires every routine's header to state which technique
it uses, where the technique was learned, and that the implementation is
original. Only src/zenpoint.asm does (rounding: feilipu's math32
documentation; small-integer fast paths: the original format design).
sqrt.asm, transc.asm, trig.asm, strio.asm, mulz80n.asm and circle.asm
describe the algorithm and the oracle that mirrors it but carry no
provenance line, so the record the clean-room protocol relies on is
incomplete for the restoring integer square root, the atanh-kernel ln,
Cody-Waite reduction in exp and trig, the Chebyshev kernels, Comba
accumulation on Z80N, decimal string conversion and the midpoint
circle. The generated tables (lnexpconst, trigconst, p10const)
regenerate byte-identically from tools/gencoeff.py, gentrig.py and
genconst.py, so their derivation is already checkable; the hand-written
routines need the author's own account of where each technique came
from, not a reconstruction from the code. trig.asm, mulz80n.asm and the
three generated tables also lack the Copyright line the other files
carry.

Trigger: clean-room review of the 0.1.3p checkpoint, 2026-10-28.

## docs

### T-23. Docs lag the shipped state: PLAN section 2 distribution text, README status line and QUIRKS wording

Theme: docs · Priority: P3 · Status: ☐

Three statements no longer match what the tree does. (1) docs/PLAN.md
section 2 says ROM deliverables ship as patch files, never as
pre-patched images in the Apache repository; tools/release.sh now
bundles the built interim swap ROM under rom/ in each release archive
under the Amstrad permission (README and LICENSE already say so; the git
tree itself still holds no image, so only the repository half of the
rule is current). (2) README's status line still reads "M0/M1 in
progress"; the changelog shows M1, M3 and M4 complete and the register
holds M2, M5, M6 and M7 work as open. (3) README describes QUIRKS
builds in the present tense; there is no QUIRKS code in src/ (M5). The
interim swap ROM keeps the original Vickers floating-point routines
byte-identical and does not yet contain zenpoint's arithmetic (M6,
T-15).

Trigger: documentation review of the 0.1.3p checkpoint, 2026-10-28.

