# Size comparison: zenpoint vs the OpenSE BASIC 3.2.1 FP region

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-03

Measurement only. OpenSE BASIC 3.2.1 (CC BY-SA 3.0 / GPL-2 dual notice,
obtained from itch.io) was assembled from its own source with Pasmo and
measured from the resulting symbol table; no code from it is used or
distributed here. Its ROM keeps the classic Vickers 48K address layout
(stk_store 2AB2h, dec_to_fp 2C9Bh, print_fp 2DE3h, calculate 3362h), so
these figures double as a like-for-like yardstick for the original ROM's
FP footprint, which cannot be quoted exactly because the Vickers
routines interleave with the rest of the interpreter.

## zenpoint 0.0.1 — 6375 bytes total

| Component | Bytes |
|---|---|
| entry jump table (22 slots) | 66 |
| arithmetic core: add/sub/cmp/mul/div/INT/TRUNC + shared tails | 1399 |
| IEEE-754 interchange (f64 lossless + f32 lossy pairs) | 622 |
| string conversion (str2fp / fp2str) | 1411 (1569 before the strio size pass) |
| sqrt (correctly rounded) | 503 |
| ln / exp (+ shared Horner/scale2) | 827 |
| sin/cos/tan + atn/asn/acs | 1109 |
| generated constant/coefficient tables | 280 |

## OpenSE BASIC 3.2.1 — FP-related bands of the 16K ROM

| Band (classic layout) | Bytes | Note |
|---|---|---|
| stack store/fetch helpers | 78 + 17 | stk_fetch sits in the LET region |
| string→FP (dec_to_fp) | 141 | |
| stack_a / int_to_fp / fp_to_bc / fp_to_a glue | 187 | |
| FP→string (print_fp) | 561 | |
| arithmetic core (fadd … restack + constants) | 846 | |
| calculator engine + dispatch + memories + string ops | 823 | mixed band: includes non-FP string operations and the series generator |
| transcendentals (ln/exp/trig/atan/asn/acs/sqrt/pow) | 458 | |
| **FP-proper total (excluding the engine band)** | **2288** | |
| with the engine band | 3111 | |

## Reading the numbers honestly

Comparable scope: zenpoint minus the IEEE block (no ROM counterpart)
is 5753 bytes against roughly 2288–3111 — about 2 to 2.5 times larger.
Three structural reasons, none of them accidental:

1. **The ROM's transcendentals are calculator bytecode.** Its 458-byte
   transcendental band is mostly RPN literals executed by the engine
   (plus the series generator hiding in the engine band); zenpoint's
   2719 bytes of native code and tables buy measured ≤2.3 ulp accuracy
   against mpmath, where the classic series-based routines deliver
   roughly 7–8 correct digits with known weak spots. This is the
   documented accuracy-for-size trade, not overhead.
2. **Rounding.** The ROM arithmetic truncates or half-adjusts;
   zenpoint's core (1399 + 66 vs ~941 bytes) carries guard/jam-sticky
   state and RNE rounding on every operation, plus re-entrant stack
   frames instead of fixed memory slots.
3. **String conversion** (1411 vs ~889) does correct parsing and
   printing natively with documented error bounds; print_fp leans on
   the calculator engine for part of its work, so some of its true
   cost is amortized into the engine band.

## Consequence for M6 (ROM fitting)

Budget model, to prevent a misreading: the M6 target is a full ROM
swap in which zenpoint OVERWRITES the Vickers FP code in place — the
~3,111 bytes of measured bands are the primary room, and the spare
tail takes only the excess. The kept (non-FP) interpreter code calls
into the FP region at the documented entry addresses, so the band
room is fragmented: a dozen or so spans with fixed boundaries,
interleaved with ~400 bytes of non-FP code. Because the whole image
is authored, interleaved non-FP routines may be relocated and their
call sites patched — this buys contiguity for packing, never net
bytes.

### Spare-room survey (filler-run scan of every canonical image)

Room co-resident with the FP caller — usable without paging tricks:

| Target | Free room | Where |
|---|---|---|
| 48K | 1,170 B | 386Eh (the only 16+ byte unused run in the image) |
| 48K charset (3D00h–3FFFh) | +0 B | NOT capacity: the font data must exist in the image for anything to copy it at boot, so moving it (to RAM or elsewhere in ROM) shuffles 768 B around a fixed 16K image and creates nothing. Compressing it in ROM and expanding to RAM at boot nets only ~250–380 B for real complexity. Decision: the charset stays put — as pure data it is also the ideal occupant of the divMMC-trapped 3D00h–3DFFh page |
| 128K ROM 1 / +2 ROM 1 | 105 B | 3C97h–3CFFh free tail of the old spare window (enough for a trampoline, not code; corrects the earlier "fully occupied" reading, which measured 1157/1170 by a different rule — the zero-tail is 105 B on both) |
| Next page 3 | 0 B | last used byte is 3CFFh; no filler runs anywhere in the page |
| TC2048 | 1,164 B | 3874h (the 48K spare, slightly shifted) |

Room in other banks — reachable only through paging veneers, since
the calculator runs with the BASIC ROM paged in:

| Machine | Free room elsewhere | Where |
|---|---|---|
| 128K / +2 ROM 0 | 32–122 B | scraps; effectively nothing |
| +3 / +2A ROM 0 | 1,618 B | 37AEh |
| +3 / +2A ROM 1 | ~1,850 B | 3712h/3A29h/3D09h runs |
| +3 / +2A ROM 2 | 4,419 B | 2CBDh — the largest free region on any classic machine |
| +3 / +2A ROM 3 | 906 B | three runs where the 48K spare was partially reused |

The +3/+2A is therefore the one classic target with real room
(~7.4K across banks, 906 B in the FP-resident ROM itself), at the
price of cross-ROM veneers; everything else lives or dies on the
48K's 1,170 bytes plus whatever kept-interpreter code a build
variant sheds.

### Size-reduction ledger (minimal speed compromise)

Current core 6,607 bytes. For a ROM-patch build:

| Lever | Bytes | Cost |
|---|---|---|
| Omit IEEE interchange block (no ROM counterpart) | −622 | none; build-time IFDEF |
| Omit the entry jump table (patch dispatches at ROM addresses) | −66 | none |
| String-conversion size pass — DONE: 1,569 → 1,411 by structural dedup (shared acc helpers, one P10 scale engine, merged emit/extract loops) | −158 realized | byte-exact outputs verified across the full gate; remaining fat is algorithmic, further cuts fight the contract |
| Constant/table dedup across transcendental tables | −20..50 | none |
| **Reachable subtotal** | **~5,500 + M2 engine (est. +500..800)** | |

Against 4,281 B of room the gap is
~1.7–2K and only closes by claiming non-FP ROM regions (sacrificing
features from the patched ROM) or by demoting some transcendentals to
M2 calculator bytecode — a large, localized speed loss that
contradicts the point of the library. Both are M6 design decisions,
and both hinge on M2's engine size, the largest unknown in the
budget. Filed as a planning note, not a commitment.

### Reclaimable interpreter code (swap-ROM builds that shed features)

Decision on the table: a build variant may drop peripherals that did
not survive their era. Boundaries verified against the canonical
image (COPY at 0EACh, PRINT-OUT at 09F4h, SA-BYTES at 04C2h);
OpenSE 3.2.1 corroborates — its source carries no cassette low-level
at all.

Tier 1 — dead peripherals, cleanly bounded (~1,635 B):

| Region | Range | Bytes | Note |
|---|---|---|---|
| Cassette subsystem | 04C2h–09F3h | 1,330 | SAVE/LOAD/VERIFY/MERGE are one interleaved block; all go together |
| ZX Printer (COPY, COPY-BUFF, CLEAR-PRB) | 0EACh–0F2Bh | 128 | LPRINT/LLIST are channel steering, nearly free |
| IF1 stream vestiges (OPEN#, CLOSE#, CAT/FORMAT/MOVE/ERASE stubs) | 16E5h–1795h | ~177 | exist only to be shadowed by Interface 1 |

Tier 2 — judgement calls remaining: the nine untouched report
messages (~35).

Directed cut (decided 2026-09-03): CIRCLE replaced, not dropped —
the Vickers polygon-through-the-calculator implementation
(232Dh–2476h, 329 B, slow and visibly polygonal) gives way to a
midpoint (Bresenham) integer circle: 8-way mirrored plotting through
the kept PLOT-SUB (attributes, INK, OVER, INVERSE for free),
arguments via the kept STK-TO-BC/FP-TO-A helpers. IMPLEMENTED
(T-18, src/circle.asm): 206 B measured, differentially verified
against tools/gencircle.py per PLOT-SUB call across 292 cases in
the gate; the ROM build at 2320h adds a 34 B statement prologue
(measured: it parses the radius itself and gates on CHECK-END, so
the ~10 B first assumed was far short), for 240 B in place of the
stock band's 343 B.
Behaviour deltas, both improvements: pixels are rounder (not
pixel-identical to Vickers), and off-screen portions CLIP instead of
erroring — the old ROM refuses any circle that does not fit the
canvas entirely. Three-argument DRAW x,y,a (whose arc machinery
shares the reclaimed region) falls back to the kept straight DRAW
via an ~8 B argument-dropping shim — working assumption, flagged
for veto. Net recovery 103 B measured against CIRCLE alone -- but
CIRCLE's 240 B patch also overwrote the DRAW command table entry at
2382h (T-19, filed and closed 2026-09-04: DRAW silently drew garbage
or hung). The real fix needed its own 24 B replacement entry in the
same region's slack, restoring two-argument DRAW exactly and
degrading three-argument DRAW x,y,a to a straight chord (angle still
parsed and evaluated, then discarded -- syntax and expression errors
unchanged, only the curvature is lost). T-20, filed as a non-blocking
follow-on, is a real integer-arc replacement. Net CIRCLE+DRAW
recovery is therefore 343 - (240 + 24) = 79 B, not 103.

Directed cut (decided 2026-09-03): BEEP fixed-tone stub — the
command body (03F8h–046Bh, 116 B) is replaced by a 13-byte stub
(RST 28h / delete, delete, end-calc / ld hl,467 / ld de,264 /
jp BEEPER) that consumes both arguments and always plays 880 Hz for
300 ms; the semitone table (046Eh–04A9h, 60 B, twelve FP
frequencies used only by BEEP — missed in the earlier tier-2
count) is freed. BEEPER (03B5h, 67 B) stays: the keystroke pip and
error rasp run through it. BEEP statements still parse and run;
pitch/duration are ignored and the pitch-range error can no longer
occur. Recovered: 163 B.

Directed cuts (decided 2026-09-03): SCREEN$ — the S-SCRN$-S
subroutine is 2535h–257Fh, 75 B measured by disassembly (it ends
with JP 2AB2h; S-ATTR-S starts at 2580h — an earlier ~122 estimate
was wrong); the scanner dispatch stub is repointed at report C.
Report-message compression — the table at 1392h–1538h is 423 B of
bit-7-terminated strings walked by terminator count, so a message
shrinks in place without moving anything at or after 1555h. Final
wordings (decided 2026-09-03):

| Code | Old | New | Saves |
|---|---|---|---:|
| 8, F, R | End of file · Invalid file name · Tape loading error | 1-byte placeholders (unreachable: features dropped) | 43 |
| J | Invalid I/O device | Bad I/O device (channel P repoints here) | 4 |
| O | Invalid stream | Bad stream | 4 |
| M | RAMTOP no good | Bad RAMTOP | 4 |
| 1 | NEXT without FOR | Bad NEXT | 8 |
| 7 | RETURN without GOSUB | Bad RETURN | 10 |
| I | FOR without NEXT | Bad FOR | 9 |
| P | FN without DEF | Bad FN | 8 |
| Q | Parameter error | Bad Param | 6 |
| 5 | Out of screen | Bad coords | 3 |
| 9 | STOP statement | Stopped | 7 |
| H | STOP in INPUT | Stopped | 6 |
| 6 | Number too big | Num overflow | 2 |
| C | Nonsense in BASIC | Bad BASIC | 8 |
| D | BREAK - CONT repeats | BREAK | 15 |
| L | BREAK into program | BREAK | 13 |

Unchanged: 0 OK, 2 Variable not found, 3 Subscript wrong, 4 Out of
memory, A Invalid argument, B Integer out of range, E Out of DATA,
G No room for line, K Invalid colour, N Statement lost. The two
duplicate pairs (9/H, D/L) are still stored twice — the walk is by
terminator count, so entries cannot be shared. Messages subtotal
150 B. Banner: the © 1982 Sinclair Research Ltd string (28 B,
1539h) is replaced — required anyway in a swap ROM — by a single
32-column line carrying both notices and the swap-ROM release
number, "(c) 1982 Sinclair  zenpoint v0.1.3", on the charset's (c)
glyph 7Fh: 32 B exactly, 4 B MORE than stock — the bottom line holds
32 columns and tools/genmsgtab.py refuses a longer banner rather than
wrap it. Total directed recovery 221 B (SCREEN$ 75 + messages 150 −
banner 4), as in-place holes at 2535h and across 1392h–1554h —
genuine capacity for small routines or stubs.

Default colours (decided 2026-09-04) cost nothing: the LD A,n operand
at 1265h (38h → 0Fh — RAM-DONE stores that one byte into ATTR-P,
ATTR-T and BORDCR alike) and the one at 11CCh (07h → 01h, the border
painted before the RAM test) give paper 1, ink 7, border 1 on a cold
boot. One byte over one byte in each case, so nothing is spent and
nothing is reclaimed; BORDCR carries the border through CLS, so no
third patch is needed.

divMMC/esxDOS constraint on ALL reclaimed space: automap fires when
PC reaches 0008h/0038h/0066h/04C6h/0562h and on the whole
3D00h–3DFFh page. 04C6h and 0562h sit inside the reclaimed tape
region — keep them as data or benign stubs; 3D00h–3DFFh must hold
data only, and the charset, staying exactly where it is, already
satisfies that. Upside: on divMMC hardware the traps
fire before ROM code runs, so LOAD/SAVE keep working via esxDOS even
with the tape code gone; only genuine audio-cassette use is lost.

Budget consequence (corrected 2026-09-03; an earlier revision
double-counted the charset as reclaimable): tier-1 capacity is
FP bands 3,111 + spare 1,170 + tape 1,330 + printer 128 + IF1 stubs
177 = 5,916 B; the directed cuts raise it to 6,137 B. The strio
size pass (realized: −158, string conversion now 1,411 B) brings
the component need to 5,529 B. The M2 engine audit
(docs/spec/calculator.md §6) replaces the old ~650 estimate with a
measured floor of ~880 ± 50 for the full engine (the winning
variant; numeric-only nets ~90 B worse), so the full-fat need is
~6,409 B. The BEEP fixed-tone stub adds 163 (capacity 6,300) and the CIRCLE+
DRAW replacement a measured net 79 (capacity 6,379), against that
~6,409 need: the balance is ~-30, covered by the nine untouched
report trims (~35) held in reserve. Three measurements moved this
figure from an earlier ~+40: the ROM CIRCLE costs 240 B not ~200,
the banner costs 4 B instead of saving 16, and CIRCLE's patch also
broke DRAW's command-table entry, costing a further 24 B to fix
(T-19). Every kept feature works, both verified on the real emulator
through the genuine keyboard/editor path; CIRCLE improves; DRAW x,y
is unchanged; DRAW x,y,a loses its curvature until T-20. The IEEE
block (622) remains out -- it needs far more than the headroom
provides.
