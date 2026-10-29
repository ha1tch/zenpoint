# zenpoint specification — calculator engine ABI (T-05, M2 prerequisite)

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-03

Extraction method: the opcode dispatch table was read directly out of
the canonical 48K ROM binary (Debian spectrum-roms 48.rom) at its
address 32D7h, located empirically by scanning for a run of
little-endian addresses containing the known arithmetic entries; every
entry below is the address the ROM actually dispatches to. Opcode
names cross-check against OpenSE BASIC 3.2.1's macro set (facts, not
code). The literal format was verified by decoding the ROM's own
five-constant table at 32C5h with the rule below and recovering
exactly 0, 1, 1/2, pi/2, 10.

## 1. Entry and framing

RST 28h enters CALCULATE (335Bh). The bytecode stream follows the RST
inline; the engine reads literals via the return address. B register
(BREG, 5C67h) is the djnz counter; MEM (5C68h) points to the 30-byte
calculator memory area (six 5-byte slots, default MEMBOT 5C92h);
values live on the calculator stack between STKBOT and STKEND.
End-calc is opcode 38h; execution resumes after it.

## 2. Direct opcodes (dispatch table 32D7h, verified)

| op | ROM addr | name (classic / OpenSE macro) |
|----|---------|-------------------------------|
| 00 | 368F | jump-true (fjpt n) — displacement byte follows |
| 01 | 343C | exchange (fxch) |
| 02 | 33A1 | delete (fdel) |
| 03 | 300F | subtract (fsub) |
| 04 | 30CA | multiply (fmul) |
| 05 | 31AF | division (fdiv) |
| 06 | 3851 | to-power (ftop) |
| 07 | 351B | or (fbor) |
| 08 | 3524 | no-&-no (fband) |
| 09–0E | 353B | comparison family (fcp .le/.ge/.ne/.gt/.lt/.eq) — one entry, selector from the opcode |
| 0F | 3014 | addition (fadd) |
| 10 | 352D | str-&-no (fbands) |
| 11–16 | 353B | string comparison family (fcps) — same comparison engine |
| 17 | 359C | strs-add (fcat) |
| 18 | 35DE | val$ (fvals) |
| 19 | 34BC | usr-$ (fusrs) |
| 1A | 3645 | read-in (fread) |
| 1B | 346E | negate (fneg) |
| 1C | 3669 | code (fasc) |
| 1D | 35DE | val (fval) — same entry as val$, selector from opcode |
| 1E | 3674 | len (flen) |
| 1F | 37B5 | sin (fsin) |
| 20 | 37AA | cos (fcos) |
| 21 | 37DA | tan (ftan) |
| 22 | 3833 | asn (fasin) |
| 23 | 3843 | acs (facos) |
| 24 | 37E2 | atn (fatan) |
| 25 | 3713 | ln (flogn) |
| 26 | 36C4 | exp (fexp) |
| 27 | 36AF | int (fint) |
| 28 | 384A | sqr (fsqrt) |
| 29 | 3492 | sgn (fsgn) |
| 2A | 346A | abs (fabs) |
| 2B | 34AC | peek (fpeek) |
| 2C | 34A5 | in (fin) |
| 2D | 34B3 | usr-no (fusr) |
| 2E | 361F | str$ (fstrs) |
| 2F | 35C9 | chr$ (fchrs) |
| 30 | 3501 | not (fnot) |
| 31 | 33C0 | duplicate/move (fmove) |
| 32 | 36A0 | n-mod-m (fmod) |
| 33 | 3686 | jump (fjp n) — displacement byte follows |
| 34 | 33C6 | stk-data (fstk) — compressed literal follows (section 3) |
| 35 | 367A | dec-jr-nz (fdjnz n) — BREG counter, displacement follows |
| 36 | 3506 | less-0 (fcp .lz) |
| 37 | 34F9 | greater-0 (fcp .gz) |
| 38 | 369B | end-calc (fce) |
| 39 | 3783 | get-argt (fget) — trig argument reduction |
| 3A | 3214 | truncate (ftrn) |
| 3B | 33A2 | fp-calc-2 (fsgl) — single-op re-entry |
| 3C | 2D4F | e-to-fp (fetof) |
| 3D | 3297 | re-stack (frstk) |

Jump displacements (00, 33, 35): one signed byte, relative to the
address of the displacement byte itself plus 1 (OpenSE spells the
encoding `n - $ - 1`).

## 3. Parameterised opcode classes (op >= 3Eh)

The top three bits select the class; the low five bits are the
parameter:

| bits | class | parameter |
|------|-------|-----------|
| 100xxxxx (86, 88, 8C used) | series generator | number of Chebyshev coefficients; each coefficient follows as a compressed literal |
| 101xxxxx (A0–A4 used) | stk-const | index into the constants table 32C5h: 0, 1, 1/2, pi/2, 10 |
| 110xxxxx (C0–C5 used) | st-mem | store to calculator memory slot 0–5 |
| 111xxxxx (E0–E5 used) | get-mem | fetch calculator memory slot 0–5 |

## 4. Compressed literal format (stk-data and the constants table) — verified

First byte P:
- nb = (P >> 6) + 1 literal mantissa bytes follow (1–4).
- x = P AND 3Fh. If x != 0: exponent byte e = x + 50h. If x == 0: one
  explicit byte E follows, and e = (E + 50h) mod 256 — the +50h is
  applied in BOTH cases, and the wrap is meaningful: E = B0h yields
  e = 0, i.e. small-integer form.
- The 5-byte value is [e] + the nb literal bytes + zero fill. The
  sign convention is the standard one (first mantissa byte bit 7).

Verification: the ROM constants table 32C5h reads, under exactly this
rule, as 0 (`00 B0 00`), 1 (`40 B0 00 01`), 1/2 (`30 00`), pi/2
(`F1 49 0F DA A2` → 81 49 0F DA A2, the format's truncated pi/2), and
10 (`40 B0 00 0A`) — the stream consumes all 18 bytes with no
remainder, so both the boundaries and the semantics are confirmed.

## 5. M2 implications

- zenpoint's engine must implement the direct table, the four
  parameterised classes, the literal decoder above, and the framing
  (return-address literal fetch, BREG, MEM slots, end-calc resume).
- String opcodes (10–1E odd ducks, 17–19, 2E–2F) touch interpreter
  state beyond the calculator; the M2 scope decision (full engine vs
  numeric-only with string ops delegated) is open and belongs to M2
  planning, not this extraction.
- T-17 (div+INT fusion) hooks the engine's opcode fetch: a 05h
  followed by 27h on integer operands may execute as one integer
  division; results are unchanged by construction.
- The Next ROM (T-15) adds NextBASIC hooks inside the engine band
  (193 of 830 bytes changed); an M2 engine intended for the T-15
  patch must preserve those hook points.

## 6. M2 size audit (engine band partition, 2026-09-03)

The band 3297h–36AEh (1,048 B) plus get-argt (3783h, 39 B) was
partitioned by routine using the verified dispatch addresses and
canonical internal anchors, each piece classified by what M2 must do
with it. Spot checks by disassembly: delete (33A1h) is a single RET;
the series generator is 33 B because it is mostly embedded calculator
bytecode plus two re-entry calls, reusable verbatim.

| Class | Vickers B | M2 est. | Note |
|---|---:|---:|---|
| Plumbing: CALCULATE loop, fp-calc-2, literal decoder, stk/get/st-mem, exchange, move, jumps, dec-jr-nz, end-calc, stk-pntrs | 294 | ~270 | must be rewritten at near size |
| Data: dispatch table + constants | 142 | ~130 | stk-const can point into zenpoint's existing constant tables |
| Small numeric ops: cmp family (one body, 12 opcodes), logic, sgn/abs, test-zero, n-mod-m | 203 | ~140 | shrink over fp_cmp and zenpoint helpers |
| Series generator + get-argt | 72 | ~70 | bytecode-compatible, near-verbatim |
| Redundant with zenpoint: re-stack, negate | 82 | ~20 | int forms native; negate_pk exists |
| Hardware ops: in, peek, usr-no | 23 | 23 | as-is |
| Arithmetic/transcendental adapters (calculator stack discipline -> zenpoint entries) | — | ~45 | one shared binary + one unary adapter |
| String ops: usr-$, str-&-no, strs-add, chr$, val/val$, str$, read-in, code, len | 271 | ~180 | over kept-ROM workspace/SCANNING helpers + zenpoint strio |
| **Full engine total** | **1,087** | **~880** | |

Numeric-only variant: ~675 new bytes, but the 294 B of string and
hardware ops stay in place (capacity −294), netting ~90 B WORSE than
the full engine. The full engine is the better variant on both bytes
and capability; numeric-only remains only as a staging step.

Consequence: the earlier ~650 engine estimate was ~200 optimistic.
Measured floor ~880 ± 50.
