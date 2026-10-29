; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; BEEP fixed-tone stub: consume both arguments, play 880 Hz for 300 ms
; through the kept BEEPER (03B5h). Pitch/duration are ignored; the
; pitch-range error can no longer occur.
        ORG 03F8h
        rst 28h
        DEFB 02h, 02h, 38h   ; delete, delete, end-calc
        ld hl,467            ; 437500 / 880 - 30.125
        ld de,264            ; 880 * 0.3
        jp 03B5h             ; BEEPER (kept: keystroke pip / error rasp)
