# zenpoint — Resolution Record

Append-only, newest first. Closed items move here verbatim from the live
register (docs/TRACKING.md), stamped with closing version and date.

## [0.1.3-dev] T-21 — Test modules and gate depend on the author's workspace layout (sibling replaces, offline proxy, undocumented vectors) (v0.1.3-dev, 2026-10-28)

Theme: tooling · closed 0.1.3-dev · 2026-10-28
The test drivers and the gate only ran in the author's workspace. Four
of the five Go test modules (tests/harness, circle, boot, bench)
required github.com/ha1tch/zen80 v0.0.0 and tests/dbg also required
zendis v0.0.0, each replaced by a sibling checkout (../../../zen80,
../../../zendis), so `go build` failed anywhere else with "replacement
directory ../../../zen80 does not exist". run_all.sh forced GOPROXY=off
(which no fresh module cache can satisfy), assumed build/ existed,
wrote scratch output to fixed /tmp/*.out names, and needed vector files
whose seeds and sizes were recorded nowhere. genmsgtab.py,
gencolours.py and rompatch.py did not create build/rompatch/, so the
swap-ROM step (run_all.sh and tools/release.sh alike) failed on a fresh
checkout. The base 48K ROM and mpmath were undocumented requirements,
and README gave Go 1.24+ where zen80 v0.5.6 declares go 1.25.

Fix: all five modules pin the published zen80 v0.5.6 (zendis v0.4.0 for
dbg) with go.sum committed; run_all.sh checks go, python3, mpmath, zenas
and the base ROM up front, creates build/, uses a per-run mktemp
directory, and generates missing vectors through the new
tools/genvectors.sh (fixed seeds, now recorded); the three rompatch
tools create their output directories; requirements.txt added; README
requirements corrected. Verified: full ./run_all.sh ALL GREEN in a copy
of the tree at a different path with an empty Go module cache and no
sibling checkouts (135 s); tools/release.sh on a fresh git repo, badcode
clean.

Trigger: portability review of the 0.1.3p checkpoint, 2026-10-28.

Cross-ref: CHANGELOG 0.1.3-dev.

## [0.0.1-dev] T-19 — Interim swap ROM overwrites the DRAW command entry at 2382h (v0.0.1-dev, 2026-09-04)

Theme: rom · closed 0.0.1-dev · 2026-09-04
The interim swap ROM overwrites the DRAW command entry. The command
table entry at 1AD4h points at 2382h, which falls inside the 240 B
CIRCLE patch at 2320h-240Fh, so `DRAW x,y` enters the middle of the
midpoint-circle routine. Confirmed on the emulator: `PLOT 0,0: DRAW
100,100` draws a curve running off the top of the screen and still
reports 0 OK, where stock draws the correct straight line. Straight
DRAW itself is intact -- LINE-DRAW at 2477h and the integer Bresenham
loop at 24B7h-24F6h are outside the cleared region and were never the
problem.

Fix: an 18 B replacement entry in the CIRCLE region's 103 B slack
(2410h onwards) --

        rst 18h / cp 2Ch / jr nz,dr2      ; three-argument form?
        rst 20h / call 1C82h              ; evaluate the angle
        rst 28h / DEFB 02h, 38h           ; delete it (arc machinery gone)
  dr2:  call 1BEEh                        ; CHECK-END
        jp 2477h                          ; LINE-DRAW

plus a 2 B repoint of the table operand at 1AD4h (same size, no cost).
Net CIRCLE+DRAW recovery becomes 343 - 258 = 85 B rather than 103 B,
moving the M6 balance from about -6 B to about -24 B.

Open decision (resolved by this closure, T-19 above): this silently degrades three-argument
DRAW x,y,a to a straight line, which is the argument-dropping shim
already flagged for veto in docs/notes/SIZE_COMPARISON.md. The
alternative is to report C (Bad BASIC) on the three-argument form so
the degradation is loud rather than silent, at a cost of about 2 B
less. Neither restores arcs; the arc machinery is what CIRCLE spent.

Also note the kept LINE-DRAW errors rather than clips: 24E8h/24EAh
fall through to RST 8 / report B at 24F9h when a point leaves the
screen. DRAW therefore still has the flaw CIRCLE no longer has.

Deviation (2026-09-04): the filed estimate above (18 B replacement,
85 B net recovery, ~-24 B balance) was written before the fix was
coded. The actual replacement entry needed a comma-check branch
and an extra CHECK-END/EXPT-1NUM pair to keep two-argument DRAW
correct, and measures 24 B, not 18. Net CIRCLE+DRAW recovery is
79 B and the M6 balance moved to ~-30 B, both verified against the
real build in docs/notes/SIZE_COMPARISON.md and CHANGELOG.md. The
silent-degrade choice (vs. reporting C) was confirmed, not the
loud alternative floated above.

Cross-ref: CHANGELOG 0.0.1-dev.

## [0.0.1-dev] T-18 — Swap-ROM CIRCLE: clipping midpoint implementation over kept PLOT-SUB (v0.0.1-dev, 2026-09-03)

Theme: rompatch · closed 0.0.1-dev · 2026-09-03
Replace Vickers CIRCLE+arc-DRAW (232Dh-2476h, 329 B) with a midpoint (Bresenham) integer circle calling the kept PLOT-SUB: 8-way mirrored plotting, duplicate-pixel suppression (OVER 1 correctness), off-screen portions clip instead of erroring. Target <=250 B for the core. Differentially tested against a Python reference by exact plotted-point-list comparison under zen80 with the real 48K ROM's PLOT-SUB. Trigger: M6 budget work, directed decision 2026-09-03.

Cross-ref: CHANGELOG 0.0.1-dev.

## [0.0.1-dev] T-16 — fp_div integer-exact fast path (16-bit probe, exact quotient) (v0.0.1-dev, 2026-09-03)

Theme: perf · closed 0.0.1-dev · 2026-09-03
Integer-exact fast path in fp_div. Measured 2026-09-03: int/int division
is the one operation where all three implementations (Vickers, OpenSE,
zenpoint) run the full FP machinery — 7.7-8.2k T for 84/7. Plan: when
both operands are integer form (excluding a = -65536, whose magnitude
needs 17 bits), run a 16-bit unsigned restoring division (~1k T); if the
remainder is zero, pack the quotient directly as the FP-form result the
full path would produce — bit-identical by construction, since an exact
quotient rounds to itself and div always returns FP form. Nonzero
remainder falls through to the general path, costing the ~1k T probe on
that subclass (documented trade: BASIC integer code divides exactly
often — halving, scaling by factors). No oracle change; the existing
differential vectors arbitrate.

Trigger: integer-operand benchmark, swappable-ROM discussion 2026-09-03.

Cross-ref: CHANGELOG 0.0.1-dev.

## [0.0.1-dev] T-04 — Verify 128K ROM 1 and Next ROM entry-point deltas (v0.0.1-dev, 2026-09-03)

Theme: spec · closed 0.0.1-dev · 2026-09-03
48K table verified (docs/spec/entrypoints.md). 128K ROM 1 and Next variants still need address verification and delta table. Trigger: T-01 closure.

Cross-ref: CHANGELOG 0.0.1-dev.

## [0.0.1-dev] T-05 — Extract calculator opcode table and literal formats before M2 (v0.0.1-dev, 2026-09-03)

Theme: spec · closed 0.0.1-dev · 2026-09-03
RST 28 bytecode numbering, stk-data literal compression, jump ops, mem-0..5 semantics: table the facts in docs/spec before implementing the M2 engine. Trigger: entrypoints.md.

Cross-ref: CHANGELOG 0.0.1-dev.

## [0.0.1] T-01 — M0: verify ROM entry-point addresses against references (v0.0.1, 2026-09-02)

Theme: spec · closed 0.0.1 · 2026-09-02
The PLAN.md entry-point table is indicative (from memory). Verify every pinned address against published disassembly references before freezing. Trigger: plan review.

Cross-ref: CHANGELOG 0.0.1.

## [0.0.1] T-02 — Decide IEEE interchange policy for non-representable values (v0.0.1, 2026-09-02)

Theme: api · closed 0.0.1 · 2026-09-02
Inf/NaN and denormals on import, overflow on f64 import: error return vs saturation, and the ual-level error surface. Trigger: plan sec.8.

Cross-ref: CHANGELOG 0.0.1.

## Resolved
