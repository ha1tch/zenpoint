# Spectrum-Compatible Floating Point — Implementation Plan

Updated: 2026-09-02
Status: Draft for review — not yet frozen
Working name: **zenpoint** (proposal; rename freely)

## 1. Objectives

Produce an original, quad-licensed (Apache 2.0 / GPL 2.0 / GPL 3.0 / MPL 2.0) Z80 floating point package implementing the Sinclair 5-byte number format ("Vickers maths") with two deployment shapes from one source tree:

1. **Library build** — relocatable, linkable into ual programs for targets with no ROM and no hardware FP. Improved numerics by default. Includes the IEEE-754 interchange module: a lossy binary32 pair and a lossless binary64 pair (see §4).
2. **ROM builds** — address-pinned images whose public entry points sit at the exact 48K ROM addresses, delivered as patch sets against (a) the original 48K ROM, (b) 128K ROM 1, (c) the OpenSE ROM, plus (d) a z80n-accelerated variant for the Spectrum Next.

Default numerics are *improved* (better sqrt, better rounding, recomputed coefficients). A build-time **QUIRKS** flag produces bit-exact original-ROM behavior, bugs included, for software that depends on identical results.

### Non-goals (this phase)

- No IEEE-754 *arithmetic* (math32 under MPL-2.0 already covers that need). IEEE-754 *interchange* — conversion to/from binary32 and binary64 — IS in scope (§4).
- No BASIC interpreter work beyond the calculator/FP region's external contract.
- No 6-byte/40-bit-mantissa format.

## 2. Licensing and clean-room protocol

All new code is released under a **disjunctive quad license — `Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0`** — the recipient picks whichever one term suits their project. Each option earns its place: Apache 2.0 for permissive use and patent grant; GPL 2.0 explicitly, because Apache 2.0 is GPL2-incompatible and GPL2-only projects could not otherwise consume the code; GPL 3.0 explicitly, avoiding any reliance on one-way compatibility arguments; MPL 2.0 for file-level-copyleft consumers (and symmetry with math32-adjacent ecosystems). Every source file carries the SPDX expression in its header; license texts live in `LICENSES/`. A quad grant is only possible because we own every line — which makes the clean-room discipline below a hard requirement, not hygiene. Inbound contributions must be accepted under the same quad terms (DCO note in CONTRIBUTING).

**Technique sources vs. code sources.** Ideas and algorithms may be learned from the OpenSE Basic library (CC BY-SA 3.0 / GPL2 depending on release), the Hejlsberg math48 package (unlicensed, personal permission to pasta80 only), and feilipu's math32 (MPL-2.0). No code, no code structure, and no expression is copied from any of them. Each routine carries a provenance note in its header: which technique it uses, where the technique was learned, and a statement that the implementation is original.

**Two-phase discipline.** Phase one (study): read references, write specification notes — formats, entry addresses, register conventions, algorithms, quirk catalogue — into `docs/spec/`. Phase two (implement): write code from the spec notes with third-party sources closed. The spec notes stay in the repository as evidence of process. The Complete Spectrum ROM Disassembly and similar references document facts (formats, addresses, interfaces); facts are not copyrightable, but implementation must not transcribe the disassembly's code.

**Coefficients.** Improved mode uses minimax/Chebyshev coefficients recomputed from scratch (Remez exchange via mpmath, script kept in `tools/`). QUIRKS mode must use the original ROM's coefficient values — these are numeric facts required for bit-identical output and are not copyrightable expression.

**Distribution boundaries.** The library and all source: the quad license above. ROM deliverables ship as **patch files** (IPS/BPS plus a patcher script), never as pre-patched images in the Apache repository:

| Patched base | Combined image governed by |
|---|---|
| Original 48K / 128K ROM | Amstrad permission (notices intact, no charge for ROM code, acknowledgement included) |
| OpenSE ROM | OpenSE's license (CC BY-SA 3.0 or GPL2 per the release patched); if the GPL2 release is the base, our GPL 2.0 option makes the combined image uniformly GPL2 |

The copyleft/permission terms attach to the combined images only, never to this package's source.

## 3. Interface contract (what "compatible" binds us to)

1. **Number format.** 5-byte values: FP form (biased 8-bit exponent; 32-bit mantissa, sign bit replacing the implicit leading 1) and the small-integer short form (exact -65535..65535). Both forms, both directions, everywhere.
2. **Calculator bytecode ABI.** RST 28h calculator semantics: full opcode table with original numbering, embedded literals (including the compressed stk-data literal format), jump/branch opcodes, the mem-0..mem-5 areas, BREG. Programs embed these bytecodes; the numbering is load-bearing.
3. **Pinned entry points.** Every ROM address that third-party software historically calls must hold the same routine with the same register contract. Working table below — **all addresses to be verified in M0 against the references before anything is frozen**; entries here are from memory and are indicative only:

| Routine | Address (indicative) |
|---|---|
| CALCULATE (RST 28 target) | 335Bh |
| STACK-A / STACK-BC | 2D28h / 2D2Bh |
| DEC-TO-FP | 2C9Bh |
| INT-TO-FP | 2D3Bh |
| FP-TO-BC / FP-TO-A | 2DA2h / 2DD5h |
| PRINT-FP | 2DE3h |
| Arithmetic block (add/mul/div/truncate/re-stack) | ~3014h–3297h |
| Series generator | 3449h |
| Transcendentals (ln/exp/trig/sqr/power) | ~36C4h–3851h |

4. **System variables and workspace.** Calculator stack between STKBOT and STKEND, MEM pointer, MEMBOT scratch, BREG — same locations, same meanings.
5. **Error behavior.** Same error paths and codes (RST 8 mechanism, arithmetic overflow, etc.).

Internal layout *between* pinned entries is free. Routines that outgrow their region trampoline (JP) into the spare ROM area (approx. 386Eh–3CFFh in the 48K ROM, ~1.1 KB, before the character set at 3D00h — extent to be confirmed in M0 per target, and its allocation coordinated so multiple patches do not collide).

## 4. Architecture

One source tree, profile-selected at assembly time:

| Profile | Pinning | Numerics | Notes |
|---|---|---|---|
| LIB | relocatable | improved | ual-linkable; direct-call API; bytecode engine optional module; IEEE-754 interchange module |
| LIB-QUIRKS | relocatable | ROM-exact | for cross-checking and for callers needing ROM-identical results |
| ROM48 / ROM128 | pinned | improved (QUIRKS optional) | emitted as patches |
| ROMNEXT | pinned | improved + z80n `mul de` paths | Next-only instructions gated |

**Speed technique catalogue** (all reimplemented, none copied):

| Technique | Learned from | Compat impact |
|---|---|---|
| Register-resident accumulators across operation chains (memory calc stack only at boundaries) | math48 | none — same results, less traffic |
| Unpacked constants table | OpenSE | none |
| Newton–Raphson sqrt (seed from exponent halving) instead of exp(ln(x)/2) | OpenSE / math32 | changes results — improved mode only |
| Round-to-nearest-even on a residual byte; jam-sticky addition | math32 | changes results — improved mode only |
| Unrolled software multiply kernels; separate square kernel | math32 | none |
| z80n `mul de` mantissa multiply | math32 | none (Next profile) |
| Small-integer fast paths retained and extended | original ROM design | none |

QUIRKS mode disables every "changes results" row and reinstates ROM rounding order, ROM coefficients, exp/ln-based SQR, and the documented bug catalogue (e.g. the -65536 INT class of quirks, enumerated in M0).

**IEEE-754 interchange module** (library builds; ROM builds may include it in spare space if room allows):

| Routine pair | Direction | Fidelity |
|---|---|---|
| f32 export | 5-byte → binary32 | Lossy: 32-bit mantissa rounds to 24 (RNE); small-int form exact for \|n\| < 2^24; overflow per policy |
| f32 import | binary32 → 5-byte | Exact for all normals; denormals underflow per policy; Inf/NaN rejected per policy |
| f64 export | 5-byte → binary64 | **Lossless, always**: 32-bit mantissa fits 52, exponent range fully covered |
| f64 import | binary64 → 5-byte | Lossy: RNE to 32 bits; out-of-range per policy |

The lossless guarantee of f64 export is a test invariant: export→import round-trips must be bit-identical for every 5-byte value. Non-finite/denormal policy is an open decision (§8).

## 5. Toolchain and verification harness

- **Assembler:** zenas. Needed features to confirm early: ORG/section control per region and assemble-time asserts on region end addresses (every pinned gap gets a hard assert; overflow is a build failure, not a surprise).
- **Execution harness:** zen80 core drives routines directly with generated operand vectors; T-state counts recorded per routine for performance tracking against ROM baselines.
- **Oracles:** improved mode → mpmath reference model of 5-byte arithmetic (exact semantics defined in the spec notes); QUIRKS mode → the original ROM executed under zenzx, vectors captured in batch. Differential fuzzing: directed edge cases (zeros, both signs, exponent extremes, small-int boundaries, re-stack transitions) plus randomized campaigns.
- **Acceptance (ROM builds):** patched ROM boots in zenzx; a BASIC test program exercises PRINT/arithmetic/functions and its full screen/printer output is compared against the unpatched ROM (QUIRKS) or against golden approved output (improved).
- **Discipline:** default test suite stays fast; long fuzz campaigns are deferred/local and registered as dormant guards with invocation and last-exercised records. Register (docs/TRACKING.md) from day one.

## 6. Milestones

| # | Deliverable | Exit criterion | Est. sessions |
|---|---|---|---|
| M0 | Spec pack: format spec, verified entry-point table, calculator ABI, quirk catalogue, spare-space map, oracle rig capturing ROM vectors via zenzx; zenas capability check | Spec reviewed; vectors flowing | 2–3 |
| M1 | Core arithmetic (pack/unpack, add/sub/mul/div, cmp, int/truncate, re-stack, small-int paths) plus the IEEE-754 interchange module, improved mode | Differential green vs. mpmath oracle; f64 round-trip invariant green | 3–5 |
| M2 | Calculator engine (bytecode dispatch, literals, jumps, mem areas, BREG, series generator) | Bytecode conformance suite green | 2–3 |
| M3 | Transcendentals, improved mode (ln, exp, sin/cos/tan, atn/asn/acs, N-R sqr, power) with recomputed coefficients | Accuracy targets met and documented | 3–4 |
| M4 | String I/O (DEC-TO-FP, PRINT-FP, FP-TO-A/BC, INT conversions) | Formatting suite green | 2–3 |
| M5 | QUIRKS mode complete | Bit-identical to ROM across fuzz campaigns | 3–5 |
| M6 | ROM fitting: pinned layouts for 48K/128K/Next, budgets asserted, trampolines, patch generation, boot acceptance | Patched ROMs pass acceptance in zenzx | 2–3 |
| M7 | ual library packaging: API adapter to ual runtime conventions, docs, benchmarks, tagged release | Linked ual demo program; docs complete | 1–2 |

**Total: roughly 18–28 focused sessions.** Verification dominates; M5 (bit-exactness) and M4 (PRINT-FP formatting) are the two risk concentrations. M1–M4 deliver the ual library value even if ROM work pauses; M5 is skippable until a consumer actually needs QUIRKS.

Suggested order: M0 → M1 → M4 → M7 (library shipped early) → M2 → M3 → M6 → M5.

## 7. Risks

| Risk | Mitigation |
|---|---|
| PRINT-FP formatting equivalence is subtle (rounding of displayed digits, E-notation boundaries) | Treat as its own milestone; exhaustive boundary vectors; ROM-oracle diffing even in improved mode to bound divergence |
| Entry-point table incomplete — software calls undocumented addresses | M0 sweep of references + scan of known machine-code software for CALLs into the FP region; publish the supported-entry list |
| Series/rounding order sensitivity makes QUIRKS mode expensive | Confine to M5; ship improved mode first; ROM-vector capture automated so campaigns are cheap to rerun |
| 128K ROM 1 differs from 48K in small ways | Verify both images in M0; diff-driven address table per target |
| Spare-space collisions with other ROM patches (especially patching OpenSE) | Spare-space map is part of the spec; per-base patch layouts |
| zenas lacks a needed feature (asserts, section maps) | M0 capability check; small assembler additions are in-house work |
| Coefficient recomputation misses ROM accuracy in improved mode | Accuracy targets defined numerically in M0; mpmath Remez tooling checked in and reproducible |

## 8. Open decisions

1. Package name (zenpoint is a placeholder).
2. ual runtime calling convention for the library API — needed by M7, decide by M4.
3. Whether the LIB profile includes the bytecode calculator engine by default or as an optional module (size vs. convenience for ual programs).
4. Improved-mode accuracy contract: guarantee correctly-rounded last digit, or "no worse than ROM everywhere, better where documented"?
5. Which OpenSE release (CC BY-SA 3.0 itch build vs. GPL2 2012 build) is the patch base — determines the combined-image license (the GPL2 base now composes cleanly with our own GPL 2.0 option).
6. IEEE interchange policy for values with no 5-byte representation: Inf/NaN and denormals on import, overflow on f64 import — error return vs. saturation, and the ual-level error surface.
