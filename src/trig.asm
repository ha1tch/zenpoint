; zenpoint circular functions: fp_sin, fp_cos, fp_tan.
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
;
; Spec: docs/spec/transcendentals.md section 4. One shared core:
;   n = floor(x*(2/pi) + 0.5)      (must land in integer form, else err 2)
;   r = ((x - n*CP1) - n*CP2) - n*CP3   (three-term Cody-Waite)
;   w = r*r;  S = r*PS(w);  C = PC(w)
;   q = n mod 4 (+1 for cos); sin/cos pick +/-S/+/-C; tan divides.
;
; Frame (IY+): 0..4 acc/S, 5..9 nf/C, 10..14 r/quotient, 15..19 w,
; 20 mode (0 sin, 1 cos, 2 tan), 21 q, 22..23 saved IX, 24..25 x ptr.
; Teardown constant: 26. API: HL = src, IX = result, all regs clobbered.

fp_sin:
        call is_zero_pk
        jr z,trig__retz      ; sin(0) = 0
        ld a,0
        jr trig__common
fp_tan:
        call is_zero_pk
        jr z,trig__retz      ; tan(0) = 0
        ld a,2
        jr trig__common
fp_cos:
        call is_zero_pk
        jr z,trig__ret1      ; cos(0) = 1, small-integer form
        ld a,1
        jr trig__common
trig__retz:
        ld (ix+0),0
        ld (ix+1),0
        ld (ix+2),0
        ld (ix+3),0
        ld (ix+4),0
        or a
        ret
trig__ret1:
        ld (ix+0),0
        ld (ix+1),0
        ld (ix+2),1
        ld (ix+3),0
        ld (ix+4),0
        or a
        ret

trig__common:
        push hl              ; x ptr (frame+24)
        push ix              ; result ptr (frame+22)
        ld hl,-22
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp
        ld (iy+20),a         ; mode
        ; t = x * (2/pi) -> +0
        ld l,(iy+24)
        ld h,(iy+25)
        ld de,C2OPI
        push iy
        pop ix
        call fp_mul
        ; t += 0.5 in place
        push iy
        pop hl
        push hl
        pop ix
        ld de,CHALF
        call fp_add
        ; nf = floor(t) -> +5
        push iy
        pop hl
        push hl
        pop ix
        ld bc,5
        add ix,bc
        call fp_int
        ; reduction range gate: nf must be integer form
        ld a,(iy+5)
        or a
        jp nz,trig__err2
        ; q = (n_low [+1 for cos]) & 3
        ld a,(iy+20)
        cp 1
        ld a,(iy+7)          ; n low byte (LD keeps flags)
        jr nz,trig__qok
        inc a
trig__qok:
        and 3
        ld (iy+21),a
        ; acc = nf*CP1 -> +0
        push iy
        pop hl
        ld bc,5
        add hl,bc            ; nf
        ld de,CP1
        push iy
        pop ix
        call fp_mul
        ; r = x - acc -> +10
        ld l,(iy+24)
        ld h,(iy+25)
        push iy
        pop de               ; acc
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_sub
        ; acc = nf*CP2; r -= acc in place
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ld de,CP2
        push iy
        pop ix
        call fp_mul
        push iy
        pop hl
        ld bc,10
        add hl,bc            ; r
        push iy
        pop de
        push hl
        pop ix
        call fp_sub
        ; acc = nf*CP3; r -= acc in place
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ld de,CP3
        push iy
        pop ix
        call fp_mul
        push iy
        pop hl
        ld bc,10
        add hl,bc
        push iy
        pop de
        push hl
        pop ix
        call fp_sub
        ; w = r*r -> +15
        push iy
        pop hl
        ld bc,10
        add hl,bc
        push hl
        pop de
        push iy
        pop ix
        ld bc,15
        add ix,bc
        call fp_mul
        ; kernels: tan needs both; sin/cos need the one q&1 selects
        ld a,(iy+20)
        cp 2
        jr z,trig__both
        ld a,(iy+21)
        and 1
        jr nz,trig__conly
        call trig__skernel
        jr trig__pick
trig__conly:
        call trig__ckernel
        jr trig__pick
trig__both:
        call trig__skernel
        call trig__ckernel
        ; tan: q odd -> -(C/S), else S/C   -> +10
        ld a,(iy+21)
        and 1
        jr nz,trig__cot
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ex de,hl             ; DE = C at +5
        push iy
        pop hl               ; HL = S at +0
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_div
        jr c,trig__errprop
        jr trig__tcopy
trig__cot:
        push iy
        pop hl
        ld bc,5
        add hl,bc            ; C at +5
        push iy
        pop de               ; S at +0
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_div
        jr c,trig__errprop
        push iy
        pop hl
        ld bc,10
        add hl,bc
        call negate_pk
trig__tcopy:
        push iy
        pop hl
        ld bc,10
        add hl,bc
        jr trig__copy
trig__pick:
        ; src = q&1 ? C(+5) : S(+0); q&2 -> negate
        ld a,(iy+21)
        and 1
        push iy
        pop hl               ; PUSH/POP keep flags
        jr z,trig__p2
        ld bc,5
        add hl,bc
trig__p2:
        ld a,(iy+21)
        and 2
        jr z,trig__copy
        push hl
        call negate_pk
        pop hl
trig__copy:
        ld e,(iy+22)
        ld d,(iy+23)         ; caller result ptr
        ld bc,5
        ldir
        ld hl,26
        add hl,sp
        ld sp,hl
        or a
        ret
trig__err2:
        ld a,2
trig__errprop:               ; A carries the error code (2, or fp_div's)
        ld hl,26
        add hl,sp
        ld sp,hl
        scf
        ret

trig__skernel:
        ; S(+0) = r * PS(w)
        push iy
        pop hl
        ld bc,15
        add hl,bc
        ex de,hl             ; DE = w
        ld hl,SINPOLY_N
        push iy
        pop ix               ; poly acc = +0
        call fp_poly
        push iy
        pop hl
        ld bc,10
        add hl,bc            ; r
        push iy
        pop de               ; ps at +0
        push de
        pop ix               ; in place
        jp fp_mul
trig__ckernel:
        ; C(+5) = PC(w)
        push iy
        pop hl
        ld bc,15
        add hl,bc
        ex de,hl
        ld hl,COSPOLY_N
        push iy
        pop ix
        ld bc,5
        add ix,bc
        jp fp_poly

; ======================================================================
; fp_atn: arctangent, radians. HL = src, IX = result. No range gate.
; Folds: sign (exact), reciprocal (x>1: pi/2 - atn(1/x)), octant
; (x>tan(pi/8): pi/4 + atn((x-1)/(x+1))). Kernel z*PA(z^2).
; Frame (IY+): 0..4 x/z, 5..9 num/w, 10..14 den/K, 15 fold flags
; (bit0 sign, bit1 inv, bit2 oct), 16..17 saved IX, 18..19 x ptr.
; Teardown 20. Clobbers IY (top-level and fp_asn callers only).
; ======================================================================
fp_atn:
        call is_zero_pk
        jp z,trig__retz      ; atn(0) = 0
        push hl              ; x ptr (frame+18)
        push ix              ; result (frame+16)
        ld hl,-16
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp
        ; copy x -> +0
        ld l,(iy+18)
        ld h,(iy+19)
        push iy
        pop de
        ld bc,5
        ldir
        ld (iy+15),0
        ; sign fold
        ld a,(iy+1)
        and 80h
        jr z,atn__pos
        ld (iy+15),1
        push iy
        pop hl
        call negate_pk
atn__pos:
        ; reciprocal fold: x > 1 ?
        push iy
        pop hl
        ld de,CONE
        call fp_cmp
        cp 1
        jr nz,atn__noinv
        ld a,(iy+15)
        or 2
        ld (iy+15),a
        ld hl,CONE
        push iy
        pop de
        push de
        pop ix
        call fp_div          ; x = 1/x in place (fp_div reads all before writing)
atn__noinv:
        ; octant fold: x > tan(pi/8) ?
        push iy
        pop hl
        ld de,CT8
        call fp_cmp
        cp 1
        jr nz,atn__nooct
        ld a,(iy+15)
        or 4
        ld (iy+15),a
        ; num = x - 1 -> +5
        push iy
        pop hl
        ld de,CONE
        push iy
        pop ix
        ld bc,5
        add ix,bc
        call fp_sub
        ; den = x + 1 -> +10
        push iy
        pop hl
        ld de,CONE
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_add
        ; z = num / den -> +0
        push iy
        pop ix
        push iy
        pop hl
        ld bc,10
        add hl,bc
        ex de,hl             ; DE = den
        push iy
        pop hl
        ld bc,5
        add hl,bc            ; HL = num
        call fp_div
atn__nooct:
        ; w = z*z -> +5
        push iy
        pop hl
        push hl
        pop de
        push iy
        pop ix
        ld bc,5
        add ix,bc
        call fp_mul
        ; acc = PA(w) -> +10
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ex de,hl             ; DE = w
        ld hl,ATNPOLY_N
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_poly
        ; K = z * acc -> +10 in place
        push iy
        pop hl
        ld bc,10
        add hl,bc
        push hl
        pop de
        push hl
        pop ix
        push iy
        pop hl               ; z at +0
        call fp_mul
        ; unwind: +pi/4 if oct
        ld a,(iy+15)
        and 4
        jr z,atn__no4
        push iy
        pop ix
        ld bc,10
        add ix,bc
        push ix
        pop de
        ld hl,CPI4
        call fp_add
atn__no4:
        ; pi/2 - K if inv
        ld a,(iy+15)
        and 2
        jr z,atn__no2
        push iy
        pop ix
        ld bc,10
        add ix,bc
        push ix
        pop de
        ld hl,CPI2
        call fp_sub
atn__no2:
        ; negate if sign
        ld a,(iy+15)
        and 1
        jr z,atn__nos
        push iy
        pop hl
        ld bc,10
        add hl,bc
        call negate_pk
atn__nos:
        push iy
        pop hl
        ld bc,10
        add hl,bc
        ld e,(iy+16)
        ld d,(iy+17)
        ld bc,5
        ldir
        ld hl,20
        add hl,sp
        ld sp,hl
        or a
        ret

; ======================================================================
; fp_asn / fp_acs: arcsine / arccosine via atn. HL = src, IX = result.
; asn = atn(|x|/sqrt((1-|x|)(1+|x|))) with the sign reapplied exactly;
; |x| = 1 -> +/- pi/2; |x| > 1 -> err 2 (pre-gate, uniform code).
; acs = pi/2 - asn, from the identical asn value.
; Frame (IY+): 0..4 ax, 5..9 u/d/s/q/val, 10..14 v, 15 mode (0 asn,
; 1 acs), 16..17 saved IX, 18..19 x ptr. Teardown 20.
; ======================================================================
fp_asn:
        ld a,0
        jr asn__common
fp_acs:
        ld a,1
asn__common:
        push hl              ; x ptr (frame+18)
        push ix              ; result (frame+16)
        ld hl,-16
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp
        ld (iy+15),a         ; mode
        ; ax = |x| at +0; |x| > 1 -> err 2 before any arithmetic
        ld l,(iy+18)
        ld h,(iy+19)
        push iy
        pop de
        ld bc,5
        ldir
        ld a,(iy+1)
        and 80h
        jr z,asn__axok
        push iy
        pop hl
        call negate_pk
asn__axok:
        push iy
        pop hl
        ld de,CONE
        call fp_cmp
        cp 1
        jp z,asn__err2
        ; u = 1 - ax -> +5: Sterbenz-exact for ax in [0.5,1], which is
        ; exactly where 1 - ax*ax would cancel catastrophically
        ld hl,CONE
        push iy
        pop de
        push iy
        pop ix
        ld bc,5
        add ix,bc
        call fp_sub
        ; v = 1 + ax -> +10
        ld hl,CONE
        push iy
        pop de
        push iy
        pop ix
        ld bc,10
        add ix,bc
        call fp_add
        ; d = u*v -> +5 in place
        push iy
        pop hl
        ld bc,10
        add hl,bc
        ex de,hl             ; DE = v
        push iy
        pop hl
        ld bc,5
        add hl,bc            ; HL = u
        push hl
        pop ix
        call fp_mul
        ; s = sqrt(d) at +5; fp_sqrt uses IY internally: save it
        push iy
        pop hl
        ld bc,5
        add hl,bc
        push hl
        pop ix
        push iy
        call fp_sqrt
        pop iy
        jp c,asn__err        ; unreachable after the gate; guard kept
        ; s == 0 -> |x| = 1 -> val = pi/2
        push iy
        pop hl
        ld bc,5
        add hl,bc
        call is_zero_pk
        jr nz,asn__general
        ld hl,CPI2
        push iy
        pop ix
        ld bc,5
        add ix,bc
        push ix
        pop de
        ld bc,5
        ldir
        jr asn__sign
asn__general:
        ; q = ax / s -> +5 (fp_div reads everything before writing)
        push iy
        pop hl               ; ax at +0
        push iy
        pop ix
        ld bc,5
        add ix,bc
        push ix
        pop de               ; DE = s, IX = +5 dest
        call fp_div
        ; val = atn(q) -> +5 in place (fp_atn clobbers IY: save it)
        push iy
        pop hl
        ld bc,5
        add hl,bc
        push hl
        pop ix
        push iy
        call fp_atn
        pop iy
asn__sign:
        ; asn(-x) = -asn(x), exact flip
        ld l,(iy+18)
        ld h,(iy+19)
        inc hl
        ld a,(hl)
        and 80h
        jr z,asn__have
        push iy
        pop hl
        ld bc,5
        add hl,bc
        call negate_pk
asn__have:
        ld a,(iy+15)
        or a
        jr nz,asn__acs
        ; asn: copy +5 -> caller result
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ld e,(iy+16)
        ld d,(iy+17)
        ld bc,5
        ldir
        jr asn__done
asn__acs:
        ; acs: pi/2 - val -> caller result
        push iy
        pop hl
        ld bc,5
        add hl,bc
        ex de,hl             ; DE = val
        ld l,(iy+16)
        ld h,(iy+17)
        push hl
        pop ix
        ld hl,CPI2
        call fp_sub
asn__done:
        ld hl,20
        add hl,sp
        ld sp,hl
        or a
        ret
asn__err2:
        ld a,2
asn__err:
        ld hl,20
        add hl,sp
        ld sp,hl
        scf
        ret
