; zenpoint Z80N multiply engine (Spectrum Next builds only).
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
;
; 32x32 -> exact 64-bit product via sixteen hardware MUL D,E, Comba
; (column-wise) accumulation: running column sum in C:HL, product
; bytes emitted low-to-high. The product is the same exact 64-bit
; integer the bit-serial engine computes, so every rounding bit and
; the whole differential contract are unchanged.
;
; Entry (from the fp_mul prologue, selected by FASTMUL_Z80N):
;   main DEHL = Ma, alt DEHL = Mb, alt C = product sign,
;   stack: [esum][result ptr].
; Exit: jp fp_mul__norm with product hi32 in main DEHL, lo32 in alt
;   DEHL, main C = sign, stack unchanged.
        OPT ZXNEXT

fp_mul__z80n:
        ; frame (ascending): P0..P7 (ix+0..7), Mb b0..b3 (ix+8..11),
        ; Ma b0..b3 (ix+12..15)
        push de
        push hl              ; Ma
        exx
        push de
        push hl              ; Mb
        exx
        ld hl,-8
        add hl,sp
        ld sp,hl             ; product bytes (written, never read early)
        ld ix,0
        add ix,sp
        ; ---- column 0: a0*b0 ----
        ld d,(ix+12)
        ld e,(ix+8)
        mul d,e
        ex de,hl
        ld c,0
        ld (ix+0),l
        ld l,h
        ld h,0
        ; ---- column 1: a0*b1 + a1*b0 ----
        ld d,(ix+12)
        ld e,(ix+9)
        mul d,e
        add hl,de
        jr nc,fp_mz__c1a
        inc c
fp_mz__c1a:
        ld d,(ix+13)
        ld e,(ix+8)
        mul d,e
        add hl,de
        jr nc,fp_mz__c1b
        inc c
fp_mz__c1b:
        ld (ix+1),l
        ld l,h
        ld h,c
        ld c,0
        ; ---- column 2: a0*b2 + a1*b1 + a2*b0 ----
        ld d,(ix+12)
        ld e,(ix+10)
        mul d,e
        add hl,de
        jr nc,fp_mz__c2a
        inc c
fp_mz__c2a:
        ld d,(ix+13)
        ld e,(ix+9)
        mul d,e
        add hl,de
        jr nc,fp_mz__c2b
        inc c
fp_mz__c2b:
        ld d,(ix+14)
        ld e,(ix+8)
        mul d,e
        add hl,de
        jr nc,fp_mz__c2c
        inc c
fp_mz__c2c:
        ld (ix+2),l
        ld l,h
        ld h,c
        ld c,0
        ; ---- column 3: a0*b3 + a1*b2 + a2*b1 + a3*b0 ----
        ld d,(ix+12)
        ld e,(ix+11)
        mul d,e
        add hl,de
        jr nc,fp_mz__c3a
        inc c
fp_mz__c3a:
        ld d,(ix+13)
        ld e,(ix+10)
        mul d,e
        add hl,de
        jr nc,fp_mz__c3b
        inc c
fp_mz__c3b:
        ld d,(ix+14)
        ld e,(ix+9)
        mul d,e
        add hl,de
        jr nc,fp_mz__c3c
        inc c
fp_mz__c3c:
        ld d,(ix+15)
        ld e,(ix+8)
        mul d,e
        add hl,de
        jr nc,fp_mz__c3d
        inc c
fp_mz__c3d:
        ld (ix+3),l
        ld l,h
        ld h,c
        ld c,0
        ; ---- column 4: a1*b3 + a2*b2 + a3*b1 ----
        ld d,(ix+13)
        ld e,(ix+11)
        mul d,e
        add hl,de
        jr nc,fp_mz__c4a
        inc c
fp_mz__c4a:
        ld d,(ix+14)
        ld e,(ix+10)
        mul d,e
        add hl,de
        jr nc,fp_mz__c4b
        inc c
fp_mz__c4b:
        ld d,(ix+15)
        ld e,(ix+9)
        mul d,e
        add hl,de
        jr nc,fp_mz__c4c
        inc c
fp_mz__c4c:
        ld (ix+4),l
        ld l,h
        ld h,c
        ld c,0
        ; ---- column 5: a2*b3 + a3*b2 ----
        ld d,(ix+14)
        ld e,(ix+11)
        mul d,e
        add hl,de
        jr nc,fp_mz__c5a
        inc c
fp_mz__c5a:
        ld d,(ix+15)
        ld e,(ix+10)
        mul d,e
        add hl,de
        jr nc,fp_mz__c5b
        inc c
fp_mz__c5b:
        ld (ix+5),l
        ld l,h
        ld h,c
        ; (no ld c,0: column 6 cannot overflow 16 bits, C is dead)
        ; ---- column 6: a3*b3 ----
        ld d,(ix+15)
        ld e,(ix+11)
        mul d,e
        add hl,de            ; carry impossible: product < 2^64
        ld (ix+6),l
        ld (ix+7),h
        ; ---- reload: lo32 -> alt DEHL, hi32 -> main DEHL ----
        exx                  ; alt (C = sign, preserved: Comba ran in main)
        ld a,c               ; sign
        ld l,(ix+0)
        ld h,(ix+1)
        ld e,(ix+2)
        ld d,(ix+3)
        exx                  ; main
        ld c,a               ; main C = sign
        ld l,(ix+4)
        ld h,(ix+5)
        ld e,(ix+6)
        ld d,(ix+7)
        ; drop the 16-byte frame without touching HL
        ld ix,16
        add ix,sp
        ld sp,ix
        jp fp_mul__norm
