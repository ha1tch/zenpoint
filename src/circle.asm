; zenpoint swap-ROM CIRCLE (T-18) -- NOT part of the library build.
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; Copyright (c) 2026 haitch <h@ual.li>
;
; Midpoint (Bresenham) integer circle over the kept ROM's PLOT-SUB.
; Replaces the Vickers polygon CIRCLE: rounder output, enormously
; faster, and off-screen portions CLIP instead of raising an error.
; Duplicate pixels are suppressed (dx==0 / dy==0 / x==y folds), so the
; routine is correct under OVER 1.
;
; Entry: C = cx (0..255), B = cy (0..255), A = r (0..255).
; Runs in BASIC context: IY = sysvars (5C3Ah), interrupts as found.
; Scratch: nine bytes of the calculator memory area (MEMBOT 5C92h),
; which the ROM's own CIRCLE/DRAW also used. Clobbers AF/BC/DE/HL.
; The M6 build prepends the argument prologue (STK-TO-BC + FP-TO-A)
; and places this at the reclaimed 232Dh region; the test build ORGs
; it at 8000h and drives it directly.
;
; Differential contract: tools/gencircle.py generates the exact point
; multiset per (cx,cy,r); tests/circle compares every PLOT-SUB call.

PLOT_SUB EQU 22E5h           ; LD (COORDS),BC / ... (B = y, C = x)
MB       EQU 88              ; IY+88 = 5C92h (MEMBOT)
; frame: +0 cx, +1 cy, +2 x, +3 y, +4/5 d (signed 16), +6 dx, +7 dy,
;        +8 current row py

        IFDEF ROMPATCH
; swap-ROM build (rompatch/src/circle_rom.asm defines ROMPATCH): the
; CIRCLE command routine at 2320h. This is a STATEMENT HANDLER, not a
; bare plotter -- it must match the stock ROM's contract exactly:
;   * CLASS-09 (the coordinate class) has already scanned and stacked
;     x and y; CH-ADD points at the ',' before the radius.
;   * We parse the radius ourselves (RST 18 / RST 20 / EXPT-1NUM) and
;     gate on syntax-vs-run via CHECK-END, so nothing plots while the
;     line is only being syntax-checked (that gap hung the editor).
;   * Only when running do x, y, radius sit on the calc stack for us
;     to pop and draw.
        ORG 2320h
        rst 18h              ; A = char at CH-ADD, expect ','
        cp 2Ch
        jp nz,1C8Ah          ; NONSENSE IN BASIC if the comma is missing
        rst 20h              ; step past the comma
        call 1C82h           ; EXPT-1NUM: evaluate radius -> calc stack
        call 1BEEh           ; CHECK-END: during syntax checking this
                             ; returns to the statement loop, skipping
                             ; everything below (no plotting while editing)
        rst 28h
        DEFB 2Ah             ; abs: radius = |radius|
        DEFB 38h             ; end-calc
        call 2DD5h           ; FP-TO-A: A = radius (0..255), CF if bigger
        jr c,zpc__rb
        push af
        call 2307h           ; STK-TO-BC: B = y, C = x (range-checked)
        pop af
        call zp_circle
        jp 0D4Dh             ; TEMPS, then RET to the statement loop
zpc__rb:
        rst 8
        DEFB 0Ah             ; report B: radius outside the 8-bit engine
        ELSE
        ORG 8000h            ; test build: driven directly by tests/circle
        ENDIF

zp_circle:
        ld (iy+MB+0),c
        ld (iy+MB+1),b
        or a
        jr nz,zpc__r1
        ; r = 0: the single point (cx, cy), clip-checked by plot4
        ld (iy+MB+6),0
        ld (iy+MB+7),0
        jp zpc__plot4
zpc__r1:
        ld (iy+MB+2),a       ; x = r
        ld (iy+MB+3),0       ; y = 0
        ld e,a               ; d = 1 - r
        ld d,0
        ld hl,1
        or a
        sbc hl,de
        ld (iy+MB+4),l
        ld (iy+MB+5),h
zpc__loop:
        ld a,(iy+MB+3)
        cp (iy+MB+2)         ; y vs x
        jr z,zpc__go         ; y == x: last octant step
        jr nc,zpc__done      ; y > x: finished
zpc__go:
        call zpc__plot8
        inc (iy+MB+3)        ; y += 1
        ld l,(iy+MB+4)
        ld h,(iy+MB+5)
        bit 7,h
        jr z,zpc__dge
        ; d < 0: d += 2*y + 1
        ld e,(iy+MB+3)
        ld d,0
        sla e
        rl d                 ; DE = 2y
        inc e                ; 2y is even: no carry
        add hl,de
        jr zpc__dst
zpc__dge:
        ; d >= 0: x -= 1; d += 2*(y - x) + 1
        dec (iy+MB+2)
        ld a,(iy+MB+3)
        sub (iy+MB+2)        ; y - x, CF = sign
        ld e,a
        sbc a,a              ; 00h or FFh: sign extension
        ld d,a
        sla e
        rl d                 ; DE = 2*(y-x), signed
        inc e                ; even: no carry into D
        add hl,de
zpc__dst:
        ld (iy+MB+4),l
        ld (iy+MB+5),h
        jr zpc__loop
zpc__done:
        ret

; plot the (up to) eight mirrored points for the current (x, y)
zpc__plot8:
        ld a,(iy+MB+2)
        ld (iy+MB+6),a       ; dx = x
        ld a,(iy+MB+3)
        ld (iy+MB+7),a       ; dy = y
        call zpc__plot4
        ld a,(iy+MB+2)
        cp (iy+MB+3)
        ret z                ; x == y: mirrored quad is identical
        ld (iy+MB+7),a       ; dy = x
        ld a,(iy+MB+3)
        ld (iy+MB+6),a       ; dx = y
        ; fall through
; plot rows cy+dy and (if dy != 0) cy-dy, each with cx+dx and
; (if dx != 0) cx-dx; every point clip-checked, never erroring
zpc__plot4:
        ld a,(iy+MB+1)       ; py = cy + dy
        add a,(iy+MB+7)
        jr c,zpc__row2       ; > 255: row off-screen
        cp 176
        jr nc,zpc__row2      ; > 175: row off-screen
        call zpc__row
zpc__row2:
        ld a,(iy+MB+7)
        or a
        ret z                ; dy == 0: no distinct mirrored row
        ld a,(iy+MB+1)       ; py = cy - dy
        sub (iy+MB+7)
        ret c                ; < 0: row off-screen
        cp 176
        ret nc               ; cy may exceed 175: still validate
        ; fall through
zpc__row:                    ; A = valid py; plot cx+dx, then cx-dx
        ld (iy+MB+8),a
        ld a,(iy+MB+0)       ; px = cx + dx
        add a,(iy+MB+6)
        jr c,zpc__rowl       ; > 255: clip right point
        ld c,a
        ld b,(iy+MB+8)
        call PLOT_SUB
zpc__rowl:
        ld a,(iy+MB+6)
        or a
        ret z                ; dx == 0: no distinct left point
        ld a,(iy+MB+0)       ; px = cx - dx
        sub (iy+MB+6)
        ret c                ; < 0: clip
        ld c,a
        ld b,(iy+MB+8)
        jp PLOT_SUB
