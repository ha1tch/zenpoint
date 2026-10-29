# Changelog

## [Unreleased]

- Original Amstrad ROM images bundled under rom/base/ (48.rom, 128-0,
  128-1, plus2-0, plus2-1, plus3-0 to plus3-3: the Spectrum 48K/128K and
  Amstrad +2/+3 set the permission note covers), unmodified, from the
  Debian spectrum-roms package 20081224-5, with SHA256SUMS. The gate,
  the swap-ROM plan (rompatch/interim.json "base") and the circle and
  bench drivers now default to rom/base/48.rom and fall back to
  /usr/share/spectrum-roms/48.rom, so a checkout runs without the Debian
  package; VICKERS_ROM and ROMPATCH_BASE still override. Left out:
  Interface 1/2 (excluded by the permission), the Timex TC2048 ROM and
  the Spanish 128K pair (the permission wording does not settle them).
  The permission note, LICENSE and README now say these images are
  carried under the same permission. rompatch.py reports a missing base
  image with a pointer instead of a traceback. T-23 item 1 (PLAN
  section 2 distribution text) applies to these images too.

- Portability: the checkpoint now builds and passes the gate on a bare
  machine with only the documented requirements (checked from a copy at
  a different path with an empty Go module cache and no sibling
  checkouts: ./run_all.sh ALL GREEN in 135 s; tools/release.sh on a
  fresh git repo, badcode clean). Four things stopped it before. (1) The
  five Go test modules (tests/harness, circle, boot, bench, dbg) replaced
  zen80 (and, in dbg, zendis) with sibling checkouts (../../../zen80,
  ../../../zendis); they now pin the published zen80 v0.5.6 (the version
  the benchmarks were counted with) and zendis v0.4.0, with go.sum
  committed. (2) run_all.sh forced GOPROXY=off, assumed build/ existed,
  wrote scratch output to fixed /tmp/*.out names, and needed vector files
  whose seeds were recorded nowhere: it now checks go, python3, mpmath,
  zenas and the base 48K ROM up front with an actionable message,
  creates build/, uses a per-run mktemp directory, and generates missing
  vectors through the new tools/genvectors.sh (fixed seeds: all.bin 1
  and all2.bin 999 at N=3000, str.bin 7 and str2.bin 13 at N=2500,
  bench.bin 42). (3) genmsgtab.py, gencolours.py and rompatch.py now
  create their output directories; build/rompatch/ did not exist on a
  fresh checkout, so the swap-ROM step failed in run_all.sh and in
  release.sh alike. (4) README: Go floor corrected from 1.24 to 1.25
  (what zen80 v0.5.6 itself declares), mpmath and the base ROM added to
  the requirements, requirements.txt and a "Running the gate" section
  added. rompatch/AMSTRAD-ROM-PERMISSION.md synced to the newer rom/
  copy (fourth source, verified 2026-09-05): release.sh copies the
  rompatch/ file over the rom/ one, so the older text would have
  replaced it at the next release. Filed T-21 (closed), T-22, T-23.

- MPL-2.0.txt fully relocated into LICENSES/: the root copy left over
  from the previous move is removed, and README's License section now
  points to LICENSE instead of duplicating its wording (completes the
  0.1.3-era LICENSE/LICENSES/ reorganisation).

- Third-party notice added: rompatch/AMSTRAD-ROM-PERMISSION.md documents
  Cliff Lawson's 1999 Amstrad permission for redistributing Spectrum ROM
  images, since built ROMs (bundled under rom/ in each release) are a
  derivative of Amstrad's copyrighted code and not covered by zenpoint's
  own license. Cross-referenced from LICENSE and README; tools/release.sh
  now copies the notice into rom/ alongside the ROM binary in every
  release zip.

## [0.1.3] — 2026-09-04

Version set directly to 0.1.3 (not a bump from 0.0.1's patch or
minor component -- `repoman syncver set`), by decision, not
chronology: no code changed between the two tags. This release's
actual content:

- tools/release.sh (new): packages a release as one zip -- the
  source tree (git archive of a given ref, default HEAD) plus the
  version-stamped interim ROM built from it, under rom/ in the
  archive. Verifies the assembled tree with repoman badcode before
  zipping. Previous releases shipped the source and the ROM as two
  separate manual deliveries; this is the first release to bundle
  them.

- Process correction: badcode verification of a delivered binary
  had been supplemented with an ad hoc grep in one prior session
  turn. Corrected -- repoman badcode check is the verification tool,
  on the actual delivered artifact, not source-tree-only and not
  duplicated by hand.

## [0.0.1] — 2026-09-04

First release. Not yet published as a git tag before this point in
the project's history -- everything below predates any prior release,
so this section is the complete initial feature set, not a delta.

- tools/rompatch.py now also writes a version-stamped copy of the
  interim ROM (zenpoint-interim-vX.Y.Z.rom, from VERSION) alongside
  the stable, unversioned name tests/boot and the watchdog read --
  the canonical path is unchanged so nothing downstream needed
  updating.

- Fix (test fixture, not a functional regression): tests/e2e's ink
  count assumed dark-on-light (absolute luminance < 128). The
  interim ROM's cold-boot default is paper 1/ink 7 -- light-on-dark
  -- which this dormant guard was never re-run against until
  preparing this release, so the inverted assumption went
  undetected. Now samples the actual background pixel and counts
  what differs from it, working under either colour scheme. Re-run
  clean: 284/284 ink pixels both cases, matching the manual checks
  made earlier while landing CIRCLE.

- Added a dormant-guards table to docs/TRACKING.md (tests/e2e was
  never registered there, the exact gap Part 3 §8 of the working
  agreement warns about -- a guard that never runs guards nothing).

- Boot colours and banner version are now genuinely configurable,
  not hand-edited constants: colours come from a "colours" block in
  rompatch/interim.json (border/paper/ink/bright/flash, 0-7),
  compiled to the two single-byte patches by tools/gencolours.py
  (new); the banner version is read from the repo's own VERSION file
  by tools/genmsgtab.py, so it always matches the library version
  (kept in sync by repoman's syncver) rather than being a separate
  sequence -- the "independent of the library VERSION" line below is
  superseded. rompatch/src/attrinit.asm and bordercol.asm are removed
  (generated bytes, no assembler needed). run_all.sh runs
  gencolours.py as part of the interim-ROM build step.

- Fix (T-19, closed): the CIRCLE patch's 240 B also overwrote the
  DRAW command table entry at 2382h -- DRAW x,y silently drew garbage
  or hung. A 24 B replacement entry (rompatch/src/draw.asm) in the
  CIRCLE region's own slack restores two-argument DRAW exactly
  (verified pixel-identical to stock on the real emulator) and
  degrades three-argument DRAW x,y,a to a straight chord -- the angle
  is still parsed and evaluated, then discarded, so syntax and
  expression errors are unchanged; only the curvature is lost. See
  RESOLVED.md for the full T-19 record. Net CIRCLE+DRAW recovery is
  79 B, not the 103 B recorded when T-18 closed; M6 balance moves to
  ~-30 B.

- Filed T-20 (P3, non-blocking): a real integer-arc replacement for
  three-argument DRAW, the same strategy as T-18's CIRCLE applied to
  a harder problem (centre+radius from two endpoints and an angle,
  then an octant-bounded integer walk rather than uniform 8-way
  emission). The stock arc machinery (2394h-2476h, 227 B measured)
  is architecturally identical to the old CIRCLE polygon: a per-step
  rotation matrix run through the calculator instead of Z80 integer
  code.

- Interim swap-ROM boot line is now the dictated wording, exactly 32
  columns: "(c) 1982 Sinclair  zenpoint v0.1.3" (two spaces between
  the two halves; 7Fh is the charset's (c) glyph). Same 32 B as the
  previous banner, so the budget is unchanged.

- Interim swap-ROM cold-boot colours are now paper 1, ink 7, border 1,
  at zero byte cost: two new single-byte patches rewrite the LD A,n
  operands at 1265h (38h -> 0Fh, the byte RAM-DONE stores into ATTR-P,
  ATTR-T and BORDCR together) and 11CCh (07h -> 01h, the border painted
  before the RAM test). BORDCR carries the border through CLS, so no
  third patch is needed. rompatch/src/attrinit.asm, bordercol.asm.

- Interim swap-ROM boot banner now carries both copyright notices and
  the swap-ROM release number on one 32-column line:
  "(c)1982Sinclair (c)2026haitch v0.1.3" (the charset's (c) glyph,
  7Fh, twice). The Sinclair notice is restored -- the interim image is
  a patched Sinclair ROM, so it belongs there -- and the spaces are
  squeezed out of both notices because 32 columns is the hard limit;
  tools/genmsgtab.py refuses a longer banner rather than wrap the
  bottom line. The banner grows 12 -> 32 B, so it now costs 4 B against
  the stock 28 B string instead of saving 16. The swap-ROM release
  number now tracks the library VERSION directly (see the entry
  above) -- v0.1.3 here was this bullet's own interim wording.

- Corrected two figures in docs/notes/SIZE_COMPARISON.md that the
  build had already superseded: the ROM CIRCLE patch measures 240 B at
  2320h (a 34 B statement prologue over the 206 B core, not the ~10 B
  first assumed), so its net recovery against the 343 B stock band is
  103 B, not ~130. With the banner change the M6 balance is ~-6 B
  rather than ~+40 -- level, covered by the nine untouched report
  message trims (~35 B) still held in reserve.

- Verified: the interim swap-ROM's CIRCLE (T-18) works on a real
  Spectrum emulator (ZenZX headless built with the interim ROM embedded)
  through the genuine keyboard/editor path -- EXTEND MODE, SYMBOL-SHIFT+H
  for the token, parameters, ENTER -- as both a direct command and a
  stored program + RUN. Output is a proper circle differing from stock
  by construction (midpoint vs polygon: 260 shared / ~110 unique pixels
  each for CIRCLE 128,50,50). Earlier snapshot-driven checks had
  silently exercised STOCK CIRCLE: ZenZX snapshots restore the ROM
  region, overwriting any ROM override on load. tests/e2e/run.sh
  captures the honest emulator-driven check (optional; needs the
  embedded-ROM zenzx-headless, set ZENZX_ZP).

- Fix (T-18 CIRCLE ROM build): the command routine at 2320h was written
  as a bare plotter that assumed x, y and radius were all pre-stacked.
  The real ROM contract is a STATEMENT HANDLER: CLASS-09 scans and
  stacks only x and y, then enters 2320h with CH-ADD pointing at the
  ",radius" text still unparsed. The routine must parse the radius
  itself and gate on syntax-vs-run via CHECK-END (1BEEh). The old code
  therefore read the stack wrong at run time (a single stray dot in the
  wrong attribute) and plunged into the plot loop during syntax
  checking (hanging the editor while a CIRCLE line was merely typed).
  The preamble now mirrors the stock routine exactly (RST 18 / expect
  comma / EXPT-1NUM / CHECK-END / abs / FP-TO-A / STK-TO-BC). Reported
  from real-hardware testing under ZenZX; the earlier gate passed only
  because the test reproduced the wrong assumption. tests/boot now
  drives the routine through the real entry state — x, y on the calc
  stack, radius as text — and asserts both a correct run-mode plot and
  a silent syntax-check pass (reaches CHECK-END, plots nothing). Known
  interim limitation: straight-line DRAW (2382h) sits inside the
  reclaimed CIRCLE region and is not yet restored in this staging image.

- Interim swap-ROM build (rompatch/): a JSON-plan-driven patcher
  (tools/rompatch.py) produces a bootable 48K image with only the
  decided feature cuts applied — Vickers FP left byte-identical, so
  no calculator-engine or FP-adapter work is needed yet. The plan
  (rompatch/interim.json) declares cleared regions and patches; every
  patch is a .bin assembled or generated for its target address, and
  the tool verifies fit, region-containment and overlap before
  writing, emitting a watch file of cleared-but-unpatched ranges. The
  set: BEEP fixed-tone stub, tape/printer/IF1 command stubs (report J
  for I/O device, O for stream), the compressed message table with
  its two PO-MSG re-anchor patches, the new banner, the clipping
  CIRCLE at its command entry (2320h via a report-B-guarded FP-TO-A
  prologue), and a SCREEN$ report-C stub. tests/boot drives the image
  under zen80: cold boot to the banner, CIRCLE through the live ROM
  prologue (points vs the midpoint reference, clip case included),
  and the r>255 report-B path — all under a PC watchdog over the
  freed ranges. Wired into run_all.sh. Not the final swap ROM (that
  needs M2); a hardware-testable staging image.

- Correctness: the non-canonical small-integer form of -65536
  ([00 FF 00 00 00] — legal on hardware, cf. the famous INT -65536 ROM
  behaviour) was mishandled on both sides of the differential contract:
  negate_pk canonicalized its negation to zero, unpack read it as zero,
  int_mul's 16-bit magnitude could not hold it, INT/TRUNC returned the
  input without canonicalizing, and fp_sub's negate-then-add route broke
  the both-int-operands result-form contract. Fixed with a shared
  chk_m64k detector: unpack yields mantissa 80000000h/exponent 145,
  negate_pk emits FP-form +65536, fp_mul diverts to the general path,
  INT/TRUNC emit canonical 91 80 00 00 00, and fp_sub runs the 24-bit
  integer subtraction directly. The oracle's _negate_pk mirror had the
  identical zeroing bug (atn/asn/acs expectations computed from a zeroed
  input) — fixed the same way. Crafted -65536 vectors (all unary ops,
  binary ops against 8 partners in both operand orders) are now part of
  both regenerated 118k seeds; full gate green on both builds. Core
  6505 -> 6607 bytes.

- T-18: swap-ROM CIRCLE (src/circle.asm, 206 bytes) — midpoint integer
  circle over the kept ROM's PLOT-SUB, replacing the Vickers
  polygon-through-the-calculator implementation (329 B): rounder
  output, no FP at all, and off-screen portions clip instead of
  raising an error. Duplicate pixels suppressed (correct under
  OVER 1). Differentially verified: every PLOT-SUB call compared
  against the tools/gencircle.py reference point multiset across 292
  cases under zen80 with the real ROM (tests/circle, now part of the
  gate). Not part of the library build. Closed — see docs/RESOLVED.md
  T-18.

- Size: strio pass — string conversion 1,569 -> 1,411 bytes (-158) by
  structural dedup, byte-exact outputs unchanged (full gate green,
  both builds): shared acc-address helpers replacing a 13-site
  7-10-byte idiom, one P10 bit-walk scale engine serving both
  routines (the two copies differed only in frame slots), merged
  digit-emit loops, shared digit extraction, and a frame-clear loop.
  Speed cost is a few hundred T per conversion on operations costing
  tens of thousands. Core 6,607 -> 6,449 bytes.

- Correctness: the non-canonical small-integer form of -65536
  ([00 FF 00 00 00] — legal on hardware, cf. the famous INT -65536 ROM
  behaviour) was mishandled on both sides of the differential contract:
  negate_pk canonicalized its negation to zero, unpack read it as zero,
  int_mul's 16-bit magnitude could not hold it, INT/TRUNC returned the
  input without canonicalizing, and fp_sub's negate-then-add route broke
  the both-int-operands result-form contract. Fixed with a shared
  chk_m64k detector: unpack yields mantissa 80000000h/exponent 145,
  negate_pk emits FP-form +65536, fp_mul diverts to the general path,
  INT/TRUNC emit canonical 91 80 00 00 00, and fp_sub runs the 24-bit
  integer subtraction directly. The oracle's _negate_pk mirror had the
  identical zeroing bug (atn/asn/acs expectations computed from a zeroed
  input) — fixed the same way. Crafted -65536 vectors (all unary ops,
  binary ops against 8 partners in both operand orders) are now part of
  both regenerated 118k seeds; full gate green on both builds. Core
  6505 -> 6607 bytes.

- T-04 closed: 128K ROM 1 / +2 ROM 1 / Next entry-point deltas
  verified by byte-diff of the canonical images. The FP region is
  byte-identical to the 48K ROM on 128K and +2 (zero deltas; all
  entry points hold); the Next keeps arithmetic entries identical but
  hooks several helpers. Critical M6 finding: the 386Eh-3CFFh spare
  area is fully occupied on 128K, +2, and Next — the spare-space
  budget applies to the 48K build only (docs/spec/entrypoints.md;
  docs/RESOLVED.md T-04).
- T-05 closed: calculator engine ABI extracted and verified
  (docs/spec/calculator.md) — the full 62-entry dispatch table read
  directly from the 48K ROM at 32D7h, the four parameterised opcode
  classes, and the compressed literal format proven by decoding the
  ROM's own constants table (the +50h is applied to the explicit
  exponent byte too, wrapping to integer form at E=B0h). M2 unblocked;
  see docs/RESOLVED.md T-05.
- T-16: fp_div integer-exact fast path — both-int operands run a 16-bit
  probe division; an exact quotient packs directly as the identical
  FP-form result (2.6k T, ~3x faster than the ROMs on that class).
  Hopeless cases (|a|<|b|, odd/even) are filtered before the probe;
  inexact int divisions pay ~0.5k median on a pessimistic random set,
  and FP-operand divisions pay 23 T. Bit-identical across the full
  gate, both builds. T-15 (Next ROM patch) and T-17 (M2 div+INT
  fusion) filed in the register; closed — see docs/RESOLVED.md T-16.
- Spectrum Next build variant: src/zenpoint_next.asm selects a Z80N
  hardware-multiply Comba engine (sixteen MUL D,E, src/mulz80n.asm)
  behind IFDEF FASTMUL_Z80N. Same exact 64-bit product, bit-identical
  across the full differential gate (now run on both builds); mul
  5152 -> 2679 T on Next-class machines, transcendentals -20..30%.
  Quarter-square table multipliers were studied and rejected: against
  the register-resident bit-serial loop they buy nothing but payload.
- Performance: register-resident mul and div — multiplicand/divisor
  moved out of (IX+d) stack frames into registers, and div cut from 40
  to 34 developed quotient bits (the remainder-nonzero sticky makes the
  rest redundant). mul 7058 -> 5152 T, div 12311 -> 7014 T, both now
  ahead of the 48K ROM; every transcendental sped up for free (ln
  74.6k -> 57.5k, asn 163.5k -> 134.5k). Bit-identical results across
  the full differential gate. Core 6375 -> 6346 bytes.
- M3 complete: fp_atn, fp_asn, fp_acs — atn by sign/reciprocal/octant
  folds and a degree-7 kernel, no range gate; asn from the factored
  discriminant (1-|x|)(1+|x|) (Sterbenz-exact where asin conditioning
  is worst), acs = pi/2 - asn; |x| > 1 uniformly error 2 by pre-gate.
  Two 118k-vector seeds bit-exact. Measured: atn 1.94 / asn 2.29 ulp,
  acs at its pi/2-ulp absolute floor (7.8e-10). Entry slots
  8039h/803Ch/803Fh; core 6375 bytes. Sections 1-5 of the
  transcendentals spec are all differential-green: M3 closes.
- M3: fp_sin, fp_cos, fp_tan — one shared quarter-circle reduction
  (n = nearest quarter-circle, three-term Cody-Waite with two exact
  products), sin/cos octant selection and tan by division with error
  propagation; differential-green across two 103k-vector seeds on the
  first assembly. Measured 1.76 / 1.62 ulp worst; tan within 0.39 of
  its conditioning bound (docs/spec/transcendentals.md §4).
  Coefficients generated by tools/gentrig.py. Core 5696 bytes.
- Toolchain: zenas v0.9.0 adds the DDCB/FDCB indexed bit group and fixes
  0xxH-style hex literal parsing. String conversion converted to direct
  set/res/bit on frame bytes (23 sites): core 5174 -> 5115 bytes, and
  each converted flag update drops from 45 to 23 T-states. The restoring
  sqrt shift chain keeps its pointer-walk form (smaller and faster than
  the indexed encoding), and the vacating-multiplier product loop stays
  by design.
- M3: fp_ln and fp_exp — natural log (range split at sqrt(2)/2, atanh
  kernel, degree-4 fit) and exponential (Cody-Waite reduction, degree-8
  fit, magnitude pre-gate), algorithm-defined and differential-green
  against the oracle across two 85k-vector seeds; measured 1.29 / 0.98
  ulp worst vs mpmath (docs/spec/transcendentals.md §2–3). Coefficients
  generated by tools/gencoeff.py, never hand-typed. Core now 5174 bytes.
- M3: fp_sqrt — correctly rounded (RNE) square root via binary restoring
  integer method with exact-remainder rounding; no seed tables.
- Filed the extended-math wave (T-06..T-14): pow, atan2, hypot, fmod,
  round/ceil, fabs, cbrt baseline; hyperbolics and fma judgment-tier.
- M4 complete: decimal string conversion in Z80 (fp_str2fp, fp_fp2str),
  byte-exact against the oracle across 16k string vectors; Sinclair-like
  formatting, print/parse fixed point, documented parse accuracy.
- M1 complete: add, sub, cmp, mul, div, INT (floor), TRUNC, and the four
  IEEE-754 interchange routines (f64 lossless pair, f32 lossy pair) in
  Z80 assembly, differential-green against the oracle (73k seed-1 and
  97k fresh-seed vectors, bit-identical), including the 2^-128 resurrect
  boundary, Inf/NaN rejection, and denormal handling. Core: 2054 bytes.
- M0: repository skeleton, quad license (Apache-2.0 OR GPL-2.0-only OR
  GPL-3.0-only OR MPL-2.0), plan, tracking register.
- M0: format and improved-mode semantics specification (docs/spec/format.md).
- M0: Python oracle model with self-tests (tools/oracle.py,
  tests/test_oracle.py) — 100k+ vectors green.
- M0: 48K ROM entry-point table verified against the published disassembly
  routine map; spare area 386E-3CFF confirmed (docs/RESOLVED.md T-01;
  docs/spec/entrypoints.md).
- Decision: IEEE interchange policy for non-representable values — error
  return via carry flag, no saturation, silent underflow flush (see
  docs/RESOLVED.md T-02; recorded in spec sections 3 and 4).
