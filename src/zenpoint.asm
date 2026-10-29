; zenpoint - Z80 floating point, Sinclair 5-byte format, clean-room original.
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; Copyright (c) 2026 haitch <h@ual.li>
;
; M1 v0: add, sub, cmp. Improved-mode semantics per docs/spec/format.md:
; correct rounding (RNE) via an 8-bit guard byte with jam-sticky
; (technique learned from feilipu's math32 documentation; implementation
; original), small-integer fast paths (technique from the original format
; design; implementation original).
;
; Library API v0 (draft, pending T-03):
;   HL = ptr to operand a (5 bytes), DE = ptr to operand b (5 bytes),
;   IX = ptr to result buffer (5 bytes).
;   Out: CF=0 success; CF=1 error with A = code (1 overflow, 3 div-by-zero).
;   fp_cmp: A = 0 (a=b), 1 (a>b), 0FFh (a<b); no buffer written; CF=0.
;   All registers clobbered. Re-entrant: no static state, stack only.
;
; Internal unpacked accumulator: B = exponent (0 => zero), C bit7 = sign,
; D:E:H:L = 32-bit mantissa, MSB in D, bit 31 set for nonzero values.

        ORG 8000h

; ---- entry table ----
        JP fp_add            ; 8000h
        JP fp_sub            ; 8003h
        JP fp_cmp            ; 8006h
        JP fp_mul            ; 8009h
        JP fp_div            ; 800Ch
        JP fp_to_f64         ; 800Fh
        JP fp_from_f64       ; 8012h
        JP fp_to_f32         ; 8015h
        JP fp_from_f32       ; 8018h
        JP fp_int            ; 801Bh
        JP fp_trunc          ; 801Eh
        JP fp_str2fp         ; 8021h
        JP fp_fp2str         ; 8024h
        JP fp_sqrt           ; 8027h
        JP fp_ln             ; 802Ah
        JP fp_exp            ; 802Dh
        JP fp_sin            ; 8030h
        JP fp_cos            ; 8033h
        JP fp_tan            ; 8036h
        JP fp_atn            ; 8039h
        JP fp_asn            ; 803Ch
        JP fp_acs            ; 803Fh

ERR_OVERFLOW    EQU 1

; ======================================================================
; fp_sub: a - b. Copies b to a stack buffer, negates it, runs fp_add.
; ======================================================================
fp_sub:
        ; b = -65536 (non-canonical int form) with a also int form: the
        ; negate-then-add route would turn b into FP form and produce an
        ; FP-form result, breaking the both-int-operands contract. Do the
        ; 24-bit integer subtraction directly: a + 65536 leaves the low
        ; 16 bits of a untouched and adds 1 to the sign-extension byte.
        ld a,(hl)
        or a
        jr nz,fp_sub__gen
        ld a,(de)
        or a
        jr nz,fp_sub__gen
        ex de,hl
        call chk_m64k        ; Z iff b is int-form -65536
        ex de,hl
        jr nz,fp_sub__gen
        inc hl
        ld a,(hl)            ; sign_a (00h or FFh)
        inc hl
        ld c,(hl)
        inc hl
        ld h,(hl)
        ld l,c               ; HL = a stored u16 (two's complement)
        inc a                ; high byte of a + 010000h
        jp z,int_add__store  ; a was negative: result 0..65535, int form
        jp int_add__to_fp    ; a >= 0: result 65536..131071, FP form
fp_sub__gen:
        push de              ; [b]
        push hl              ; [a][b]
        ld hl,-6
        add hl,sp
        ld sp,hl             ; 6-byte buffer at SP; HL = buffer
        ex de,hl             ; HL = b ptr (DE untouched by pushes), DE = buf
        ld bc,5
        ldir                 ; copy b -> buffer
        ld hl,-5
        add hl,de            ; HL = buffer start
        call negate_pk       ; negate the copy in place (moves HL)
        ld hl,0
        add hl,sp
        ex de,hl             ; DE = buffer start (= SP), recomputed
        ld hl,6
        add hl,sp
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a               ; HL = a ptr (stack: [buf6][a][b][ret])
        call fp_add
        pop bc               ; unwind 10 bytes; POP preserves flags and A
        pop bc
        pop bc
        pop bc
        pop bc
        ret

; negate a packed 5-byte value in place. HL = ptr. Preserves DE, IX.
negate_pk:
        ld a,(hl)
        or a
        jr z,negate_pk__int
        inc hl
        ld a,(hl)
        xor 80h              ; FP form: flip sign bit
        ld (hl),a
        ret
negate_pk__int:                        ; [0, s, lo, hi, 0]
        inc hl               ; -> sign
        inc hl               ; -> lo
        ld a,(hl)
        inc hl               ; -> hi
        ld b,(hl)
        ld c,a               ; C = lo, B = hi
        xor a
        sub c
        ld c,a               ; lo' = 0 - lo
        ld a,0
        sbc a,b
        ld b,a               ; hi' = 0 - hi - borrow
        ld (hl),b
        dec hl
        ld (hl),c
        dec hl               ; -> sign byte
        ld a,b
        or c
        jr z,negate_pk__zero
        ld a,(hl)
        cpl                  ; 00h <-> FFh
        ld (hl),a
        ret
negate_pk__zero:
        ld a,(hl)            ; original sign byte is still at (HL)
        or a
        jr z,negate_pk__z0
        ; input was the non-canonical int form of -65536 ([0,FFh,0,0,0]):
        ; its negation, +65536, does not fit int form -> FP form
        ld (hl),0            ; m1 = 00h: positive, mantissa 80000000h
        dec hl
        ld (hl),91h          ; exponent 145 (2^16)
        ret
negate_pk__z0:
        ld (hl),0            ; -0 canonicalizes to 0
        ret

; ======================================================================
; fp_add: a + b -> (IX)
; ======================================================================
fp_add:
        ; zero pre-checks (packed): zero is [0,0,0,0,0]
        call is_zero_pk      ; tests (HL); preserves HL,DE
        jr nz,fp_add__a_nonzero
        ex de,hl             ; a is zero: result = b
        jp copy_to_result
fp_add__a_nonzero:
        ex de,hl
        call is_zero_pk      ; tests b (now in HL)
        ex de,hl             ; restore HL=a, DE=b
        jr nz,fp_add__b_nonzero
        jp copy_to_result    ; b is zero: result = a
fp_add__b_nonzero:
        ; both-int fast path?
        ld a,(de)
        or a
        jr nz,fp_add__general
        ld a,(hl)
        or a
        jp z,int_add
fp_add__general:
        ; unpack b into alternate set, a into main set
        push hl
        ex de,hl
        call unpack          ; b -> B,C,DEHL
        exx                  ; b now in alternate set
        pop hl
        call unpack          ; a -> main set
        ; align: make ACTIVE set the operand with the smaller exponent
        ld a,b               ; ea
        exx                  ; alternate active (b)
        sub b                ; A = ea - eb
        jr nc,fp_add__smaller_active ; ea>=eb: b (active) is smaller, d=A
        neg
        exx                  ; a is smaller; make it active. d=A
fp_add__smaller_active:
        ; A = d (>=0). Active = smaller-exponent operand.
        or a
        jr nz,fp_add__need_shift
        ; d == 0: if effective subtraction, ensure larger mantissa >= smaller
        ld a,c               ; smaller sign
        exx
        xor c                ; bit7 = eff_sub
        exx                  ; back to smaller
        jp p,fp_add__no_preswap     ; effective addition: order irrelevant
        ; trial-compare: (larger - smaller) mantissa; CF => larger < smaller
        exx                  ; larger
        push bc              ; save larger exponent/sign
        exx                  ; smaller
        push de              ; smaller hi
        push hl              ; smaller lo
        exx                  ; "larger" active
        pop bc               ; smaller lo (B=Hs, C=Ls)
        or a
        ld a,l
        sub c
        ld a,h
        sbc a,b
        pop bc               ; smaller hi (B=Ds, C=Es)
        ld a,e
        sbc a,c
        ld a,d
        sbc a,b
        pop bc               ; restore larger exponent/sign (flags kept)
        exx                  ; back to "smaller"
        jr nc,fp_add__no_preswap
        exx                  ; roles swap: old larger is now the active set
fp_add__no_preswap:
        ld b,0               ; guard = 0
        jr fp_add__aligned
fp_add__need_shift:
        ld b,0               ; guard byte (B of smaller set is free now)
        cp 40
        jr c,fp_add__shift_loop
        ; d >= 40: smaller contributes only stickiness
        ld d,0
        ld e,0
        ld h,0
        ld l,0
        ld b,1               ; guard=0 with jam bit set
        jr fp_add__aligned
fp_add__shift_loop:
        srl d
        rr e
        rr h
        rr l
        rr b                 ; into guard
        jr nc,fp_add__no_jam
        set 0,b              ; jam-sticky: lost bit ORs into guard bit 0
fp_add__no_jam:
        dec a
        jr nz,fp_add__shift_loop
fp_add__aligned:
        ; effective operation: sign_small XOR sign_large
        ld a,c
        exx                  ; larger active
        xor c
        jp m,fp_add__eff_sub
        ; ---- effective addition ----
        push bc              ; save larger exponent/sign (larger is active)
        exx                  ; smaller
        ld a,b               ; A = guard
        push de
        push hl
        exx                  ; larger
        pop bc               ; smaller lo
        add hl,bc
        pop bc               ; smaller hi
        ex de,hl
        adc hl,bc
        ex de,hl
        pop bc               ; restore larger exponent/sign (flags kept)
        jr nc,round_pack
        ; mantissa carry: 33 bits -> shift right one, exponent++
        rr d
        rr e
        rr h
        rr l
        rra                  ; guard; bit out -> jam
        jr nc,fp_add__no_jam2
        or 1
fp_add__no_jam2:
        inc b
        jp z,overflow_err    ; exponent was 255
        jr round_pack
fp_add__eff_sub:
        ; ---- effective subtraction: larger - smaller (never borrows) ----
        push bc              ; save larger exponent/sign (larger is active)
        exx                  ; smaller
        ld a,b               ; A = guard of smaller
        push de
        push hl
        exx                  ; larger
        neg                  ; A = 0 - guard; CF = borrow into low word
        pop bc               ; smaller lo
        sbc hl,bc
        pop bc               ; smaller hi
        ex de,hl
        sbc hl,bc
        ex de,hl
        pop bc               ; restore larger exponent/sign (flags kept)
        ; fall through to normalize
normalize:
        ; zero test: mantissa and guard all zero -> result is zero
        push af
        ld a,d
        or e
        or h
        or l
        jr nz,normalize__not_zero
        pop af
        or a
        jr z,ret_zero        ; guard zero too
        jr normalize__norm_loop        ; mantissa 0, guard bits remain: keep shifting
normalize__not_zero:
        pop af
normalize__norm_loop:
        bit 7,d
        jr nz,round_pack
        add a,a              ; guard << 1
        rl l
        rl h
        rl e
        rl d
        dec b
        jr z,ret_zero        ; exponent hit 0: underflow flush
        jr normalize__norm_loop

; round (RNE on guard byte in A) and pack B,C,DEHL -> (IX)
round_pack:
        cp 80h
        jr c,pack
        jr nz,round_pack__round_up
        bit 0,l              ; tie: round to even (up only if mantissa odd)
        jr z,pack
round_pack__round_up:
        inc l
        jr nz,pack
        inc h
        jr nz,pack
        inc e
        jr nz,pack
        inc d
        jr nz,pack
        ; mantissa wrapped: 2^32 -> M=2^31, exponent++
        ld d,80h
        inc b
        jp z,overflow_err
pack:
        ld (ix+0),b
        ld a,c
        and 80h
        ld c,a
        ld a,d
        and 7Fh
        or c
        ld (ix+1),a
        ld (ix+2),e
        ld (ix+3),h
        ld (ix+4),l
        or a                 ; CF = 0
        ret

ret_zero:
        xor a                ; CF = 0
        ld (ix+0),a
        ld (ix+1),a
        ld (ix+2),a
        ld (ix+3),a
        ld (ix+4),a
        ret

overflow_err:
        ld a,ERR_OVERFLOW
        scf
        ret

; copy 5 bytes (HL) -> (IX), CF=0. Clobbers A,HL.
copy_to_result:
        ld a,(hl)
        ld (ix+0),a
        inc hl
        ld a,(hl)
        ld (ix+1),a
        inc hl
        ld a,(hl)
        ld (ix+2),a
        inc hl
        ld a,(hl)
        ld (ix+3),a
        inc hl
        ld a,(hl)
        ld (ix+4),a
        or a
        ret

; Z set if (HL) is the canonical zero. Preserves HL, DE. Clobbers A.
is_zero_pk:
        push hl
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        inc hl
        or (hl)
        pop hl
        ret

; chk_m64k: Z set iff (HL) is the non-canonical small-integer form of
; -65536, [00,FFh,00,00,00] (the caller has established int form).
; Preserves HL, DE, BC, IX.
chk_m64k:
        push hl
        inc hl
        ld a,(hl)
        inc a                ; FFh -> 00h
        jr nz,chk_m64k__out  ; sign is not FFh: NZ already set
        inc hl
        ld a,(hl)
        inc hl
        or (hl)              ; Z iff stored u16 == 0
chk_m64k__out:
        pop hl
        ret

; ======================================================================
; unpack: (HL) -> B=exp (0 => zero), C=sign (bit7), DEHL=mantissa.
; Small-integer form is normalized to FP internally. Preserves IX.
; ======================================================================
unpack:
        ld a,(hl)
        or a
        jr z,unpack__int_form
        ld b,a               ; exponent
        inc hl
        ld a,(hl)            ; m1
        ld c,a
        ld d,a
        set 7,d              ; restore implicit leading bit
        ld a,c
        and 80h
        ld c,a               ; sign only
        inc hl
        ld e,(hl)            ; m2
        inc hl
        ld a,(hl)            ; m3
        inc hl
        ld l,(hl)            ; m4
        ld h,a
        ret
unpack__int_form:
        inc hl
        ld b,(hl)            ; sign byte
        inc hl
        ld a,(hl)            ; lo
        inc hl
        ld h,(hl)            ; hi
        ld l,a               ; HL = stored 16-bit value
        ld a,b
        or a
        jr z,unpack__positive
        ; negative: magnitude = 0 - value
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        or l                 ; magnitude 0 from a nonzero input: -65536
        jr nz,unpack__neg16
        ld b,91h             ; exponent 145: value = 2^16
        ld c,80h             ; negative
        ld d,80h             ; mantissa 80000000h (HL is already 0)
        ld e,0
        ret
unpack__neg16:
        ld c,80h
        jr unpack__norm16
unpack__positive:
        ld c,0
unpack__norm16:
        ld d,h
        ld e,l               ; mantissa = magnitude << 16
        ld hl,0
        ld b,144             ; magnitude * 2^16 * 2^(144-160) = magnitude
        ld a,d
        or e
        jr nz,unpack__norm_loop
        ld b,0               ; zero
        ld c,0
        ret
unpack__norm_loop:
        bit 7,d
        ret nz
        add hl,hl
        rl e
        rl d
        dec b
        jr unpack__norm_loop

; ======================================================================
; int_add: both operands small-integer form. HL=a, DE=b, IX=result.
; 24-bit two's complement add; falls back to FP encode when out of range.
; ======================================================================
int_add:
        inc hl
        ld a,(hl)
        ld b,a               ; sign_a
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a               ; HL = a value (16)
        ex de,hl             ; HL = b ptr, DE = a value
        inc hl
        ld a,(hl)
        ld c,a               ; sign_b
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a               ; HL = b value
        add hl,de            ; low 16 sum
        ld a,b
        adc a,c              ; A = sign-extension byte of the 24-bit sum
        or a
        jr z,int_add__store          ; 0..65535, positive
        cp 0FFh
        jr nz,int_add__to_fp         ; 01h or FEh: magnitude > 65535
        ld c,a
        ld a,h
        or l
        ld a,c               ; restore sign byte (LD keeps flags)
        jr z,int_add__to_fp  ; exactly -65536: out of range
int_add__store:
        ld (ix+0),0
        ld (ix+1),a
        ld (ix+2),l
        ld (ix+3),h
        ld (ix+4),0
        or a                 ; CF=0 (A is 00h or FFh; OR clears carry)
        ret
int_add__to_fp:
        ; 24-bit two's complement in A:HL; |sum| <= 131070
        bit 7,a
        jr z,int_add__pos
        ld b,a
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld a,0
        sbc a,b              ; A = magnitude bits 16-23
        ld c,80h
        jr int_add__encode
int_add__pos:
        ld c,0
int_add__encode:
        ; mantissa = magnitude << 8: D=A, E=H, H=L, L=0; exponent 152
        ld d,a
        ld e,h
        ld a,l
        ld h,a
        ld l,0
        ld b,152
        xor a                ; guard = 0
        jp normalize

; ======================================================================
; fp_cmp: compare a (HL) and b (DE). A=0 equal, 1 a>b, FFh a<b. CF=0.
; ======================================================================
fp_cmp:
        push hl
        ex de,hl
        call unpack          ; b
        exx                  ; b -> alternate
        pop hl
        call unpack          ; a -> main
        ld a,c               ; sign_a
        exx                  ; alt (b) active
        xor c
        jp m,fp_cmp__diff_sign
        ; same sign: compare exponents first (values are normalized)
        exx                  ; main
        ld a,b               ; ea
        exx                  ; alt
        cp b                 ; ea vs eb: CF => ea<eb => |a|<|b|
        jr z,fp_cmp__cmp_mantissa
        jr fp_cmp__apply_sign       ; NZ here; CF decides magnitude order
fp_cmp__cmp_mantissa:
        ; trial subtract a - b (32-bit), low to high; CF => |a|<|b|
        push de              ; b hi
        push hl              ; b lo
        exx                  ; main (a) active
        pop bc               ; b lo (B=Hb, C=Lb)
        or a
        ld a,l
        sbc a,c
        ld c,a               ; diff byte 0
        ld a,h
        sbc a,b
        ld b,a               ; diff byte 1
        pop hl               ; b hi (H=Db, L=Eb); HL of a already consumed
        ld a,e
        sbc a,l
        ld l,a               ; diff byte 2
        ld a,d
        sbc a,h              ; diff byte 3 in A; CF final
        jr c,fp_cmp__a_mag_less
        or l
        or b
        or c
        jr z,fp_cmp__equal
        or a                 ; NC, NZ: |a| > |b|
        exx                  ; sign lives in C of either set (same sign);
                             ; use alt's C
        jr fp_cmp__apply_sign
fp_cmp__a_mag_less:
        scf
        exx                  ; alt for sign
        jr fp_cmp__apply_sign
fp_cmp__equal:
        xor a
        ret
fp_cmp__apply_sign:
        ; CF = |a|<|b|. C bit7 (current set) = common sign.
        jr c,fp_cmp__mag_less
        bit 7,c
        jr nz,fp_cmp__lt            ; negative: larger magnitude is smaller value
        jr fp_cmp__gt
fp_cmp__mag_less:
        bit 7,c
        jr nz,fp_cmp__gt
fp_cmp__lt:
        ld a,0FFh
        or a                 ; CF=0
        ret
fp_cmp__gt:
        ld a,1
        or a
        ret
fp_cmp__diff_sign:
        ; recover sign_a = (sign_a^sign_b) ^ sign_b
        xor c
        bit 7,a
        jr nz,fp_cmp__lt            ; a negative, b positive
        jr fp_cmp__gt

; ======================================================================
; fp_mul: a * b -> (IX). Shift-add 32x32->64 core (v0; unrolled and
; z80n mul variants come later per PLAN section 4).
; ======================================================================
fp_mul:
        call is_zero_pk      ; a zero?
        jp z,ret_zero
        ex de,hl
        call is_zero_pk      ; b zero?
        ex de,hl
        jp z,ret_zero
        ld a,(de)
        or a
        jr nz,fp_mul__gen
        ld a,(hl)
        or a
        jr nz,fp_mul__gen
        ; both int form; divert the non-canonical -65536 ([0,FFh,0,0,0])
        ; to the general path: int_mul's 16-bit magnitude cannot hold it
        call chk_m64k        ; Z iff a is int-form -65536
        jr z,fp_mul__gen
        ex de,hl
        call chk_m64k        ; Z iff b is int-form -65536
        ex de,hl
        jp nz,int_mul
fp_mul__gen:
        push hl
        ex de,hl
        call unpack          ; b
        exx                  ; b -> alternate
        pop hl
        call unpack          ; a -> main
        ; product sign into alt C
        ld a,c               ; sa
        exx                  ; alt
        xor c
        and 80h
        ld c,a               ; alt C = product sign
        ; esum = ea + eb, 9 bits as CF:A, saved on stack
        ld a,b               ; eb
        exx                  ; main
        add a,b              ; + ea
        push af              ; [esum lo + CF]
        push ix              ; [result ptr]
        IFDEF FASTMUL_Z80N
        jp fp_mul__z80n      ; hardware MUL engine (mulz80n.asm)
        ENDIF
        ; Multiplicand Mb goes register-resident: lo16 in alt BC, hi16
        ; in IXH:IXL -- no 19T indexed reads inside the loop. Multiplier
        ; Ma stays in main DEHL as the product's high half: shifting P
        ; left ejects Ma's MSB as the carry (vacating-multiplier trick).
        exx                  ; alt (b)
        ld a,c               ; product sign (A survives the moves)
        ld b,h
        ld c,l               ; alt BC = Mb b1:b0
        ld ixl,e             ; IXL = Mb b2
        ld ixh,d             ; IXH = Mb b3
        ld d,0
        ld e,0
        ld h,0
        ld l,0               ; P-low = 0
        exx                  ; main
        ld c,a               ; main C = sign
        ld b,32
fp_mul__mloop:
        ; P <<= 1 (64-bit); carry out of the top = multiplier bit
        exx
        add hl,hl
        rl e
        rl d
        exx
        adc hl,hl
        rl e
        rl d
        jr nc,fp_mul__noadd
        ; P-low += Mb (register-resident); carry rides into P-high
        exx
        add hl,bc
        ld a,e
        adc a,ixl
        ld e,a
        ld a,d
        adc a,ixh
        ld d,a
        exx
        jr nc,fp_mul__noadd
        inc l                ; ripple the carry into P-high,
        jr nz,fp_mul__noadd  ; stopping at the first non-wrap
        inc h
        jr nz,fp_mul__noadd
        inc e
        jr nz,fp_mul__noadd
        inc d
fp_mul__noadd:
        djnz fp_mul__mloop
        ; normalize: product in [2^62, 2^64); one left shift at most
fp_mul__norm:
        bit 7,d
        jr nz,fp_mul__k128
        exx
        add hl,hl
        rl e
        rl d
        exx
        adc hl,hl
        rl e
        rl d
        ld a,129
        jr fp_mul__fin
fp_mul__k128:
        ld a,128
fp_mul__fin:
        exx                  ; alt (P-low)
        ld b,a               ; k
        ; guard byte = alt D; jam if any lower bit set
        ld a,e
        or h
        or l
        jr z,fp_mul__nojam
        set 0,d
fp_mul__nojam:
        ld c,d               ; alt C = guard
        ; teardown: restore result ptr and esum (no memory frame)
        pop ix
        pop af               ; A = esum lo, CF = esum bit 8
        ld l,a
        ld h,0
        jr nc,fp_mul__nh
        inc h
fp_mul__nh:
        ld e,b               ; k
        ld d,0
        or a
        sbc hl,de            ; HL = final exponent (signed 16-bit)
        bit 7,h
        jp nz,ret_zero       ; negative: underflow flush
        ld a,h
        or a
        jp nz,overflow_err   ; >= 256
        ld a,l
        or a
        jp z,ret_zero        ; exponent 0: underflow flush
        ; handoff: main B = exponent, A = guard; C (sign) and DEHL intact
        ld a,l
        exx                  ; main
        ld b,a
        exx                  ; alt
        ld a,c
        exx                  ; main
        jp round_pack

; ======================================================================
; int_mul: both operands small-integer form. 16x16->32 shift-add.
; Result: int form when |product| <= 65535, else FP via normalize.
; ======================================================================
int_mul:
        inc hl
        ld b,(hl)            ; sa
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a               ; HL = a stored u16
        ld a,b
        or a
        jr z,int_mul__apos
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a               ; mag_a
int_mul__apos:
        ld c,b               ; C = sa
        ex de,hl             ; HL = b ptr, DE = mag_a
        inc hl
        ld b,(hl)            ; sb
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a               ; HL = b stored u16
        ld a,b
        or a
        jr z,int_mul__bpos
        xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a               ; mag_b
int_mul__bpos:
        ld a,c
        xor b                ; product sign byte (00h or FFh)
        ld c,a
        ; frame: [Lb,Hb,sign,junk]. Multiplier mag_a stays in DE as the
        ; product's high half (vacating-multiplier trick); P-low = HL.
        push ix              ; save result ptr
        push bc              ; ix+2 = sign (C), ix+3 = junk
        push hl              ; ix+0..1 = mag_b
        ld ix,0
        add ix,sp
        ld b,16              ; counter
        ld hl,0              ; P-low; P-high = DE = mag_a
int_mul__iloop:
        add hl,hl            ; P <<= 1; carry out of D = multiplier bit
        rl e
        rl d
        jr nc,int_mul__ino
        ld a,l
        add a,(ix+0)
        ld l,a
        ld a,h
        adc a,(ix+1)
        ld h,a
        jr nc,int_mul__ino
        inc e
        jr nz,int_mul__ino
        inc d
int_mul__ino:
        djnz int_mul__iloop
        ; product DEHL (DE high); sign byte at ix+2
        ld a,(ix+2)
        pop bc               ; discard frame (POP keeps A and flags)
        pop bc
        pop ix               ; restore result ptr
        ld c,a               ; C = sign byte
        ld a,d
        or e
        jr nz,int_mul__big
        ; int form; canonicalize zero's sign
        ld a,h
        or l
        jr nz,int_mul__nz
        ld c,0
int_mul__nz:
        ld a,c
        or a
        jr z,int_mul__wr
        xor a                ; negative: store two's complement
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld a,0FFh
int_mul__wr:
        ld (ix+0),0
        ld (ix+1),a
        ld (ix+2),l
        ld (ix+3),h
        ld (ix+4),0
        or a                 ; CF = 0
        ret
int_mul__big:
        ; FP: mantissa = product (D MSB), exponent 160, sign from C
        ld a,c
        and 80h
        ld c,a
        ld b,160
        xor a                ; guard = 0
        jp normalize

; ======================================================================
; fp_div: a / b -> (IX). Restoring long division, 1 integer + 40
; fraction bits; guard byte from fraction bits, sticky from the final
; remainder (jam). Always returns FP form (spec 2.5).
; ======================================================================
fp_div:
        ex de,hl
        call is_zero_pk      ; b zero?
        ex de,hl
        jr nz,fp_div__bok
        ld a,3               ; ERR_DIVZERO
        scf
        ret
fp_div__bok:
        call is_zero_pk      ; a zero?
        jp z,ret_zero
        ; both integer form? try the exact fast path (T-16)
        ld a,(hl)
        or a
        jr nz,fp_div__gen
        ld a,(de)
        or a
        jp z,fp_div__int
fp_div__gen:
        push hl
        ex de,hl
        call unpack          ; b
        exx                  ; b -> alternate
        pop hl
        call unpack          ; a -> main (Ma in DEHL)
        push ix              ; [result ptr] -- IX becomes data
        ; sign -> IXL, counter will use IXH
        ld a,c               ; sa
        exx                  ; alt
        xor c
        and 80h
        ld ixl,a
        ; ediff = ea - eb, saved on stack
        exx                  ; main
        ld a,b               ; ea
        exx                  ; alt
        sub b                ; A = ea - eb, CF = borrow (negative)
        push af              ; [ediff]
        ; register layout for the loop:
        ;   R-lo16 main HL, R-hi16 alt HL (starts as Ma)
        ;   divisor lo16 main BC, hi16 alt BC (no indexed reads)
        ;   quotient collector alt DE (low) : main DE (high)
        ;   sign IXL, counter IXH
        ld b,d
        ld c,e               ; alt BC = Mb hi16
        push hl              ; [Mb lo16]
        ld d,0
        ld e,0               ; collector low = 0
        exx                  ; main
        pop bc               ; main BC = Mb lo16
        push de              ; [Ma hi16]
        ld d,0
        ld e,0               ; collector high = 0
        exx                  ; alt
        pop hl               ; alt HL = R-hi16 = Ma hi
        exx                  ; main (HL = Ma lo = R-lo)
        ld ixh,32            ; fraction-bit counter
        ; pre-step: q_int = (Ma >= Mb); R -= Mb when set
        or a
        sbc hl,bc
        exx                  ; alt
        sbc hl,bc
        jr nc,fp_div__q1
        exx                  ; main: restore, Ma < Mb
        add hl,bc
        exx                  ; alt
        adc hl,bc
        or a                 ; CF=0: q_int = 0
        jr fp_div__qsave
fp_div__q1:
        scf                  ; q_int = 1
fp_div__qsave:
        push af              ; [q_int]
        exx                  ; main
fp_div__dloop:
        ; R <<= 1; carry out means R >= 2^32 >= Mb: forced subtract
        add hl,hl            ; R-lo
        exx                  ; alt
        adc hl,hl            ; R-hi, CF = 33rd bit
        jr c,fp_div__forced
        ; speculative subtract (CF = 0 here), restore on borrow
        exx                  ; main
        sbc hl,bc
        exx                  ; alt
        sbc hl,bc
        jr c,fp_div__rz
        scf                  ; bit = 1
        jr fp_div__ins
fp_div__rz:
        exx                  ; main: restore
        add hl,bc
        exx                  ; alt
        adc hl,bc
        or a                 ; bit = 0
        jr fp_div__ins
fp_div__forced:
        exx                  ; main
        or a
        sbc hl,bc
        exx                  ; alt
        sbc hl,bc            ; mod-2^32 subtract always lands
        scf                  ; bit = 1
fp_div__ins:
        ; collector <<= 1 | bit  (alt DE low, main DE high)
        rl e
        rl d
        exx                  ; main
        rl e
        rl d
        dec ixh
        jp nz,fp_div__dloop
        ; two guard bits (b33, b34) -> IXH (now 0) bits 1:0
        call fp_div__gbit
        ld a,ixh
        rla
        ld ixh,a
        exx                  ; main
        call fp_div__gbit
        ld a,ixh
        rla                  ; A = 000000:b33:b34
        rlca
        rlca
        rlca
        rlca
        rlca
        rlca                 ; b33 -> bit7, b34 -> bit6
        ld ixh,a             ; guard byte
        ; sticky: remainder after 34 bits nonzero jams the guard
        ld a,h               ; [alt] R-hi
        or l
        exx                  ; main
        or h
        or l
        jr z,fp_div__nrj
        ld a,ixh
        or 1
        ld ixh,a
fp_div__nrj:
        ; case shift by q_int (mantissa: main DE high, alt DE low)
        pop af               ; CF = q_int
        jr nc,fp_div__k0
        srl d                ; q_int = 1: 1.b1..b31, shift right
        rr e
        exx                  ; alt
        rr d
        rr e
        ld a,ixh             ; eject b32 into guard bit7
        rra
        jr nc,fp_div__nsj    ; the ejected bit0 was the sticky jam:
        set 0,a              ; it must never be lost
fp_div__nsj:
        ld ixh,a
        exx                  ; main
        set 7,d              ; the integer 1
        ld a,129
        jr fp_div__kk
fp_div__k0:
        ld a,128
fp_div__kk:
        ; k -> alt B; glue mantissa low into main HL
        exx                  ; alt
        ld b,a
        push de
        exx                  ; main
        pop hl               ; main DEHL = full mantissa
        ; re-home sign and guard so IX can take the result ptr again
        ld a,ixl
        ld c,a               ; main C = sign
        ld a,ixh
        exx                  ; alt
        ld c,a               ; alt C = guard
        pop af               ; A = ediff lo, CF = borrow (negative)
        pop ix               ; result ptr
        ld l,a
        ld h,0
        jr nc,fp_div__nneg
        dec h                ; sign-extend
fp_div__nneg:
        ld e,b               ; k (128 or 129)
        ld d,0
        add hl,de            ; HL = final exponent
        bit 7,h
        jp nz,ret_zero       ; underflow flush
        ld a,h
        or a
        jp nz,overflow_err
        ld a,l
        or a
        jp z,ret_zero
        ld a,l
        exx                  ; main
        ld b,a
        exx                  ; alt
        ld a,c               ; guard
        exx                  ; main
        jp round_pack

; one division step, bit -> CF. Enter in main, returns in alt.
fp_div__gbit:
        add hl,hl
        exx
        adc hl,hl
        jr c,fp_div__gf
        exx
        sbc hl,bc
        exx
        sbc hl,bc
        jr c,fp_div__gz
        scf
        ret
fp_div__gz:
        exx
        add hl,bc
        exx
        adc hl,bc
        or a
        ret
fp_div__gf:
        exx
        or a
        sbc hl,bc
        exx
        sbc hl,bc
        scf
        ret

; ======================================================================
; fp_div__int (T-16): both operands nonzero small-integer form. 16-bit
; unsigned restoring division; an exact quotient packs directly as the
; FP-form result the general path would produce (bit-identical: exact
; values round to themselves and div always returns FP form). Nonzero
; remainder, or a = -65536 (17-bit magnitude), falls back at the cost
; of the probe. Entry: HL = a, DE = b, IX = result.
; ======================================================================
fp_div__int:
        push hl
        push de              ; operand ptrs for the fallback
        inc hl
        inc de
        ld a,(de)
        xor (hl)             ; result sign byte = sa ^ sb
        push af              ; [sign]
        ; |a| -> BC
        ld a,(hl)            ; sa
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        or a
        jr z,fp_div__ia
        ld a,b
        or c
        jp z,fp_div__ifb     ; a = -65536: magnitude needs 17 bits
        xor a
        sub c
        ld c,a
        ld a,0
        sbc a,b
        ld b,a
fp_div__ia:
        ; |b| -> DE
        ld a,(de)            ; sb
        ex de,hl
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        or a
        jr z,fp_div__ib
        ld a,d
        or e
        jp z,fp_div__ifb     ; b = -65536: |b| > |a|, never exact
        xor a
        sub e
        ld e,a
        ld a,0
        sbc a,d
        ld d,a
fp_div__ib:
        ; hopeless-case filters, cheaper than the division probe:
        ; |a| < |b| can never divide exactly (a != 0), nor can an odd
        ; dividend with an even divisor
        ld h,b
        ld l,c
        or a
        sbc hl,de
        jp c,fp_div__ifb     ; |a| < |b|
        bit 0,e
        jr nz,fp_div__ib2    ; odd divisor: no conclusion
        bit 0,c
        jp nz,fp_div__ifb    ; odd a, even b: never exact
fp_div__ib2:
        ; BC / DE unsigned: quotient -> BC, remainder -> HL
        ld hl,0
        ld a,16
fp_div__idl:
        sla c
        rl b
        adc hl,hl
        jr c,fp_div__ifo
        sbc hl,de            ; CF = 0 here
        jr nc,fp_div__i1
        add hl,de
        jr fp_div__i0
fp_div__ifo:
        or a
        sbc hl,de            ; 17-bit remainder: subtract always lands
fp_div__i1:
        inc c                ; quotient bit (bit0 vacated by sla c)
fp_div__i0:
        dec a
        jr nz,fp_div__idl
        ld a,h
        or l
        jr nz,fp_div__ifb    ; inexact: general path decides
        ; exact: pack quotient BC (>= 1) as FP form
        pop af               ; sign byte
        pop de
        pop de               ; drop saved ptrs (A untouched)
        ld e,a               ; E = sign
        ld d,0               ; D = shift count k
fp_div__inl:
        bit 7,b
        jr nz,fp_div__ipk
        sla c
        rl b
        inc d
        jr fp_div__inl
fp_div__ipk:
        ld a,144             ; exponent = 128 + (16 - k)
        sub d
        ld (ix+0),a
        ld a,b
        and 7Fh
        bit 7,e
        jr z,fp_div__ips
        or 80h
fp_div__ips:
        ld (ix+1),a
        ld (ix+2),c
        ld (ix+3),0
        ld (ix+4),0
        or a
        ret
fp_div__ifb:
        pop af               ; drop sign
        pop de               ; restore b ptr
        pop hl               ; restore a ptr
        jp fp_div__gen


; ======================================================================
; fp_int (floor) / fp_trunc (toward zero). HL = src, IX = result.
; Small-integer form out when the result fits; FP form otherwise.
; ======================================================================
fp_trunc:
        xor a
        jr fp_int__common
fp_int:
        ld a,1
fp_int__common:
        exx
        ld c,a               ; alt C = mode (1 = INT/floor, 0 = TRUNC)
        exx
        call is_zero_pk
        jp z,ret_zero
        ld a,(hl)
        or a
        jr nz,fp_int__fpin
        ; int form is already integral, but the non-canonical -65536
        ; ([0,FFh,0,0,0]) must leave canonically as FP form
        call chk_m64k
        jp nz,copy_to_result
        ld (ix+0),91h        ; -65536 = -1.0 * 2^(145-128)... exponent 145
        ld (ix+1),80h        ; sign bit set, mantissa 80000000h
        ld (ix+2),0
        ld (ix+3),0
        ld (ix+4),0
        or a
        ret
fp_int__fpin:
        cp 160
        jp nc,copy_to_result ; e >= 160: no fraction bits exist
        cp 129
        jr nc,fp_int__mixed
        ; e in 1..128: |x| < 1. TRUNC -> 0; INT -> 0 (pos) or -1 (neg)
        inc hl
        ld a,(hl)
        and 80h
        jp z,ret_zero        ; positive
        exx
        ld a,c
        exx
        or a
        jp z,ret_zero        ; TRUNC
        ld (ix+0),0          ; INT of a negative fraction = -1
        ld (ix+1),0FFh
        ld (ix+2),0FFh
        ld (ix+3),0FFh
        ld (ix+4),0
        or a
        ret
fp_int__mixed:
        call unpack          ; B = e (129..159), C = sign, DEHL = M
        ld a,160
        sub b                ; A = shift count (1..31)
        ld b,0               ; B = sticky
fp_int__shl:
        srl d
        rr e
        rr h
        rr l
        jr nc,fp_int__ns
        ld b,1
fp_int__ns:
        dec a
        jr nz,fp_int__shl
        ; N = DEHL (>= 1), sticky B, sign C
        bit 7,c
        jr z,fp_int__enc     ; positive: floor == trunc == N
        exx
        ld a,c
        exx
        or a
        jr z,fp_int__enc     ; TRUNC
        ld a,b
        or a
        jr z,fp_int__enc     ; integral already: no adjustment
        inc l                ; INT(negative, fractional): N += 1
        jr nz,fp_int__enc
        inc h
        jr nz,fp_int__enc
        inc e
        jr nz,fp_int__enc
        inc d
fp_int__enc:
        ld a,d
        or e
        jr nz,fp_int__fp
        ; fits 16 bits: reuse int_mul's int-form writer (C = 00/FF, HL = mag)
        bit 7,c
        jr z,fp_int__pos
        ld c,0FFh
        jp int_mul__nz
fp_int__pos:
        ld c,0
        jp int_mul__nz
fp_int__fp:
        ld b,160
        xor a
        jp normalize

; ======================================================================
; fp_to_f64: 5-byte (HL) -> binary64 LE (IX+0..7). Always exact (spec 3.1).
; ======================================================================
fp_to_f64:
        call is_zero_pk
        jr nz,fp_to_f64__nz
        xor a
        ld (ix+0),a
        ld (ix+1),a
        ld (ix+2),a
        ld (ix+3),a
        ld (ix+4),a
        ld (ix+5),a
        ld (ix+6),a
        ld (ix+7),a
        ret
fp_to_f64__nz:
        call unpack          ; B = e, C = sign, DEHL = M
        ; Eb = e + 894 (11 bits): alt E = Eb & 0F, alt L = Eb >> 4
        ld a,b
        exx
        ld l,a
        ld h,0
        ld de,894
        add hl,de
        ld a,l
        and 0Fh
        ld e,a
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                 ; L' = Eb >> 4
        exx
        ; w7 = sign | Eb>>4
        ld a,c
        and 80h
        exx
        or l
        ld (ix+7),a
        exx
        ; w6 = (Eb & 0F) << 4 | (R >> 3), with R = D & 7F
        ld a,d
        and 7Fh
        ld d,a               ; D = R
        srl a
        srl a
        srl a
        exx
        ld d,a
        ld a,e
        add a,a
        add a,a
        add a,a
        add a,a
        or d
        ld (ix+6),a
        exx
        ; w5..w2: sliding (x & 7) << 5 | (y >> 3)
        ld a,d
        and 07h
        rrca
        rrca
        rrca
        ld d,a
        ld a,e
        srl a
        srl a
        srl a
        or d
        ld (ix+5),a
        ld a,e
        and 07h
        rrca
        rrca
        rrca
        ld d,a
        ld a,h
        srl a
        srl a
        srl a
        or d
        ld (ix+4),a
        ld a,h
        and 07h
        rrca
        rrca
        rrca
        ld d,a
        ld a,l
        srl a
        srl a
        srl a
        or d
        ld (ix+3),a
        ld a,l
        and 07h
        rrca
        rrca
        rrca
        ld (ix+2),a
        xor a
        ld (ix+1),a
        ld (ix+0),a
        ret

; ======================================================================
; fp_from_f64: binary64 LE (HL+0..7) -> 5-byte (IX). RNE; Inf/NaN err 2;
; overflow err 1; underflow flush with the 2^-128 resurrect boundary.
; ======================================================================
fp_from_f64:
        ; guard byte: round = w2 bit4, jam = w0|w1|(w2 & 0F)
        ld a,(hl)
        inc hl
        or (hl)
        inc hl
        ld b,a
        ld c,(hl)            ; C = w2
        ld a,c
        and 0Fh
        or b
        jr z,fp_from_f64__nos
        ld a,1
fp_from_f64__nos:
        ld b,a
        ld a,c
        and 10h
        jr z,fp_from_f64__nor
        ld a,80h
fp_from_f64__nor:
        or b
        exx
        ld b,a               ; alt B = guard
        exx
        ; mantissa: sliding (cur & 1F) << 3 | (prev >> 5); prev=C, cur=E
        inc hl
        ld e,(hl)            ; w3
        ld a,e
        and 1Fh
        rlca
        rlca
        rlca
        ld d,a
        ld a,c
        rlca
        rlca
        rlca
        and 07h
        or d
        exx
        ld l,a               ; Lm
        exx
        ld c,e
        inc hl
        ld e,(hl)            ; w4
        ld a,e
        and 1Fh
        rlca
        rlca
        rlca
        ld d,a
        ld a,c
        rlca
        rlca
        rlca
        and 07h
        or d
        exx
        ld h,a               ; Hm
        exx
        ld c,e
        inc hl
        ld e,(hl)            ; w5
        ld a,e
        and 1Fh
        rlca
        rlca
        rlca
        ld d,a
        ld a,c
        rlca
        rlca
        rlca
        and 07h
        or d
        exx
        ld e,a               ; Em
        exx
        ld c,e
        inc hl
        ld e,(hl)            ; w6
        ld a,e
        and 0Fh
        rlca
        rlca
        rlca
        ld d,a
        ld a,c
        rlca
        rlca
        rlca
        and 07h
        or d
        or 80h
        exx
        ld d,a               ; Dm (implicit bit set)
        exx
        inc hl
        ld a,(hl)            ; w7
        ld d,a
        and 80h
        exx
        ld c,a               ; alt C = sign
        exx
        ; Eb = (w7 & 7F) << 4 | (w6 >> 4) -> main HL
        ld a,e
        rrca
        rrca
        rrca
        rrca
        and 0Fh
        ld c,a               ; w6 >> 4
        ld a,d
        and 7Fh
        ld b,a
        rrca
        rrca
        rrca
        rrca
        and 07h
        ld h,a
        ld a,b
        add a,a
        add a,a
        add a,a
        add a,a
        or c
        ld l,a               ; HL = Eb
        ; Inf/NaN
        ld a,h
        cp 07h
        jr nz,fp_from_f64__fin
        ld a,l
        inc a
        jr nz,fp_from_f64__fin
        ld a,2
        scf
        ret
fp_from_f64__fin:
        ld a,h
        or l
        jp z,ret_zero        ; Eb = 0: zero/denormal, far below range
        ld de,894
        or a
        sbc hl,de            ; HL = e5
        bit 7,h
        jp nz,ret_zero       ; negative: underflow flush
        ld a,h
        or a
        jp nz,overflow_err   ; >= 256
        ld a,l
        or a
        jr z,fp_from_f64__resq
        ; normal handoff
        exx                  ; alt (mantissa)
        push de
        push hl
        exx                  ; main
        pop hl
        pop de
        ld b,a               ; exponent
        exx
        ld a,c               ; sign
        exx
        ld c,a
        exx
        ld a,b               ; guard
        exx
        jp round_pack
fp_from_f64__resq:
        ; e5 = 0: resurrects to 2^-128 iff mantissa all-ones and round set
        exx
        ld a,d
        and e
        and h
        and l
        inc a
        jr nz,fp_from_f64__rz
        ld a,b               ; guard
        cp 80h
        jr c,fp_from_f64__rz
        ld a,c               ; sign
        exx
        ld (ix+0),1
        ld (ix+1),a
        ld (ix+2),0
        ld (ix+3),0
        ld (ix+4),0
        or a
        ret
fp_from_f64__rz:
        exx
        jp ret_zero

; ======================================================================
; fp_to_f32: 5-byte (HL) -> binary32 LE (IX+0..3). RNE; never errors
; (the 5-byte max is 1.99..*2^126, half of binary32's max).
; ======================================================================
fp_to_f32:
        call is_zero_pk
        jr nz,fp_to_f32__nz
        xor a
        ld (ix+0),a
        ld (ix+1),a
        ld (ix+2),a
        ld (ix+3),a
        ret
fp_to_f32__nz:
        call unpack
        ld a,b
        cp 3
        jr c,fp_to_f32__den
        sub 2
        ld b,a               ; Eb8 = e - 2 (1..253)
        ; RNE: drop L (guard byte), tie on H bit 0
        ld a,l
        cp 80h
        jr c,fp_to_f32__w
        jr nz,fp_to_f32__up
        bit 0,h
        jr z,fp_to_f32__w
fp_to_f32__up:
        inc h
        jr nz,fp_to_f32__w
        inc e
        jr nz,fp_to_f32__w
        inc d
        jr nz,fp_to_f32__w
        ld d,80h             ; mantissa hit 2.0: f = 0, exponent + 1
        inc b                ; max 254; never 255
fp_to_f32__w:
        ld a,b
        and 01h
        rrca                 ; (Eb8 & 1) -> bit 7
        ld l,a
        ld a,b
        srl a                ; Eb8 >> 1
        ld b,a
        ld a,c
        and 80h
        or b
        ld (ix+3),a
        ld a,d
        and 7Fh
        or l
        ld (ix+2),a
        ld (ix+1),e
        ld (ix+0),h
        or a
        ret
fp_to_f32__den:
        ; e in {1,2}: denormal out. Shift right k = 11 - e with guard+jam.
        ld b,0
        neg
        add a,11             ; k (9 or 10)
fp_to_f32__dsh:
        srl d
        rr e
        rr h
        rr l
        rr b
        jr nc,fp_to_f32__dnj
        set 0,b
fp_to_f32__dnj:
        dec a
        jr nz,fp_to_f32__dsh
        ; D24 = E:H:L, guard B; RNE (carry into bit 23 = smallest normal)
        ld a,b
        cp 80h
        jr c,fp_to_f32__dw
        jr nz,fp_to_f32__dup
        bit 0,l
        jr z,fp_to_f32__dw
fp_to_f32__dup:
        inc l
        jr nz,fp_to_f32__dw
        inc h
        jr nz,fp_to_f32__dw
        inc e
fp_to_f32__dw:
        ld a,c
        and 80h
        ld (ix+3),a
        ld (ix+2),e
        ld (ix+1),h
        ld (ix+0),l
        or a
        ret

; ======================================================================
; fp_from_f32: binary32 LE (HL+0..3) -> 5-byte (IX). Exact for normals
; below 2^127; Inf/NaN err 2; >= 2^127 err 1; tiny denormals flush.
; ======================================================================
fp_from_f32:
        ld e,(hl)            ; w0
        inc hl
        ld d,(hl)            ; w1
        inc hl
        ld c,(hl)            ; w2
        inc hl
        ld a,(hl)            ; w3
        ld b,a
        and 80h
        ld l,a               ; L = sign
        ld a,b
        and 7Fh
        add a,a
        bit 7,c
        jr z,fp_from_f32__e0
        or 01h
fp_from_f32__e0:
        ; A = Eb
        cp 0FFh
        jr nz,fp_from_f32__ni
        ld a,2
        scf
        ret
fp_from_f32__ni:
        or a
        jr nz,fp_from_f32__norm
        ; denormal: M = f << 8, exponent 3, normalize (flushes < 2^-128)
        ld h,e               ; H = w0
        ld e,d               ; E = w1
        ld a,c
        and 7Fh
        ld d,a               ; D = w2 & 7F (no implicit bit)
        ld a,l
        ld c,a               ; C = sign
        ld l,0
        ld a,d
        or e
        or h
        jp z,ret_zero        ; f = 0 (covers -0.0)
        ld b,3
        xor a
        jp normalize
fp_from_f32__norm:
        cp 254
        jp z,overflow_err    ; e5 would be 256: |x| >= 2^127
        add a,2
        ld b,a               ; e5 = Eb + 2 (3..255)
        ld h,e               ; H = w0
        ld e,d               ; E = w1
        ld a,c
        and 7Fh
        or 80h
        ld d,a
        ld a,l
        ld c,a               ; C = sign
        ld l,0
        xor a                ; exact
        jp round_pack



        INCLUDE "strio.asm"
        INCLUDE "sqrt.asm"
        IFDEF FASTMUL_Z80N
        INCLUDE "mulz80n.asm"
        ENDIF
        INCLUDE "transc.asm"
        INCLUDE "trig.asm"
        INCLUDE "lnexpconst.asm"
        INCLUDE "trigconst.asm"
        INCLUDE "p10const.asm"
