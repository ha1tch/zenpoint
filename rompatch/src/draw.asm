; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; T-19: DRAW command entry, replacing the one CIRCLE's 240 B patch
; overwrote at 2382h. Two-argument DRAW x,y is unaffected -- LINE-DRAW
; at 2477h (and its integer Bresenham loop at 24B7h) is kept, untouched
; code, still the fastest path in the ROM. Three-argument DRAW x,y,a is
; a decided, flagged degradation: the angle expression is still parsed
; and evaluated (so syntax checking and variable/expression errors
; behave exactly as before), then silently discarded -- DRAW draws the
; straight chord instead of the arc. Real arcs are T-20, filed as a
; follow-on, not blocking here.
;
; Placed in the CIRCLE region's own slack (2410h-2476h, 103 B), since
; 2382h itself is now CIRCLE code. The command table entry at 1AD4h is
; repointed here by the sibling drawtable.asm patch.
        ORG 2410h
        rst 18h               ; A = char at CH-ADD
        cp 2Ch                ; ','?
        jr z, dr_arc
        call 1BEEh            ; CHECK-END: two-arg form, x,y already stacked
        jp 2477h              ; LINE-DRAW
dr_arc:
        rst 20h                ; step past the comma
        call 1C82h             ; EXPT-1NUM: evaluate the angle expression
        call 1BEEh             ; CHECK-END
        rst 28h
        DEFB 02h              ; delete -- drop the now-unused angle value
        DEFB 38h              ; end-calc
        jp 2477h              ; LINE-DRAW: draws the chord (x,y still stacked)
