# zenpoint — verified ROM entry-point table (48K ROM)

SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
Updated: 2026-09-02
Status: VERIFIED against the published 48K ROM disassembly routine map
(skoolkid.github.io/rom, checked 2026-09-02). These addresses are facts of the
interface; the table supersedes the indicative table in PLAN.md section 3.
128K ROM 1 and Next verification: pending (T-04).

## Pinned public entry points

| Address | Routine | Notes |
|---|---|---|
| 2C9B | DEC-TO-FP | decimal string to 5-byte value |
| 2D28 | STACK-A | stack A register as small integer |
| 2D2B | STACK-BC | stack BC as small integer |
| 2D3B | INT-TO-FP | |
| 2DA2 | FP-TO-BC | |
| 2DD5 | FP-TO-A | |
| 2DE3 | PRINT-FP | print a floating-point number |
| 300F | SUBTRACTION | |
| 3014 | ADDITION | |
| 30CA | MULTIPLICATION | |
| 31AF | DIVISION | |
| 3214 | TRUNCATE | integer truncation toward zero |
| 3297 | RE-STACK | small-int form to FP form |
| 335B | CALCULATE | RST 28 calculator entry |
| 3449 | SERIES GENERATOR | |
| 36C4 | EXPONENTIAL | |
| 3713 | NATURAL LOGARITHM | |
| 37AA | COSINE | |
| 37B5 | SINE | |
| 37DA | TAN | |
| 37E2 | ARCTAN | |
| 3833 | ARCSIN | |
| 3843 | ARCCOS | |
| 384A | SQUARE ROOT | |
| 3851 | EXPONENTIATION | to-power |

## Spare ROM area (overflow trampoline space)

Verified: 386E–3CFF, 0492h = 1170 bytes, all FFh in the original ROM. The
character set follows at 3D00. This is the relief valve for routines that
outgrow their pinned region; allocation map to be maintained per patch base.

## Still to verify (registered)

- The full RST 28 calculator opcode table numbering and literal formats
  (facts, to be extracted and tabled before M2).
- Region sizes between consecutive pinned entries (byte budgets for M6).
- 128K ROM 1 deltas and Next ROM layout (T-04).


## 128K ROM 1, +2 ROM 1, and Spectrum Next deltas (T-04, verified 2026-09-03)

Byte-diff of the canonical images (Debian spectrum-roms 128-1.rom and
plus2-1.rom; Next page 3 extracted from tbblue enNextZX.rom):

- **128K ROM 1 and +2 ROM 1: the entire FP/calculator region
  2AB1h–3862h is byte-identical to the 48K ROM — zero deltas.** Every
  entry point in the 48K table above holds unchanged on both. Their
  ~1,200 changed bytes live in the editor/keyboard/paging areas and in
  the spare region (below).
- **The 386Eh–3CFFh spare area is NOT free outside the original 48K
  machine.** Measured occupancy (non-FFh bytes of 1,170): 48K 0,
  128K ROM 1 1,157, +2 ROM 1 1,157, Next page 3 1,121, with no usable
  tail on any of them. Any M6 patch for 128K-class or Next targets
  must either relocate what those ROMs keep there or find its space
  elsewhere; the spare-area budget applies to the 48K build only.
- **Next page 3** keeps all the primary arithmetic entries (SUBTRACT
  3014h family, MULTIPLY, DIVISION, CALCULATE, PRINT-FP, RESTACK)
  byte-identical, but carries NextBASIC hooks in the first bytes at
  stk_store, stk_fetch, dec_to_fp, int_to_fp, TRUNCATE, and inside the
  constants/dispatch tables — consistent with the engine-band findings
  recorded for T-15. Entry ADDRESSES are stable; the code beneath some
  of them is not, so a Next patch must preserve those hooks.
