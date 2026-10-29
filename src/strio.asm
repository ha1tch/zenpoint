; zenpoint string I/O: fp_str2fp and fp_fp2str (spec docs/spec/strings.md).
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; Copyright (c) 2026 haitch <h@ual.li>
;
; Algorithm-defined conversions built on the package's own RNE cores;
; the Python oracle (tools/strconv.py) implements the identical recipe.
; IY is used as the frame pointer throughout (no other routine touches it).

ERR_INVALID     EQU 2

; ---- shared frame helpers: the 5-byte acc lives at IY+10 in BOTH
; frames. Clobber BC; strio_acc_ix returns HL = IX = acc.
strio_acc_ix:
        call strio_acc_hl
        push hl
        pop ix
        ret
strio_acc_hl:
        push iy
        pop hl
        ld bc,10
        add hl,bc
        ret

; scale acc by powers of ten: walks the bits of m at (IY+7), applying
; acc = acc * / P10[k] per set bit; direction byte at (IY+19)
; (0 = multiply, 1 = divide). Table cursor uses (IY+15/16). All three
; slots are free in both frames while scaling runs. On error from
; fp_mul/fp_div returns CF=1 with A = code; else CF=0.
strio_scale:
        ld bc,P10_0
        ld (iy+15),c
        ld (iy+16),b
strio_scale__loop:
        ld a,(iy+7)
        or a
        ret z                ; done, CF=0
        rra
        ld (iy+7),a          ; m >>= 1, CF = bit
        jr nc,strio_scale__next
        call strio_acc_ix    ; HL = IX = acc (result in place)
        ld e,(iy+15)
        ld d,(iy+16)         ; DE = P10[k]
        bit 0,(iy+19)
        jr nz,strio_scale__div
        call fp_mul
        jr strio_scale__chk
strio_scale__div:
        call fp_div
strio_scale__chk:
        ret c                ; propagate error
strio_scale__next:
        ld l,(iy+15)
        ld h,(iy+16)
        ld bc,5
        add hl,bc
        ld (iy+15),l
        ld (iy+16),h
        jr strio_scale__loop

; ======================================================================
; fp_str2fp: parse decimal ASCII at (HL) -> 5-byte at (IX).
; Out: CF=0, A = chars consumed; CF=1, A = error (1 overflow, 2 invalid).
; Frame (IY+): 0..3 I, 4..5 dexp, 6 flags(0 sticky,1 neg,2 seen,3 sig),
;              7 eneg/m, 8..9 orig ptr, 10..14 acc, 15..16 + 19 used by
;              strio_scale, 17..18 stashed cursor. Saved IX at IY+20.
; ======================================================================
fp_str2fp:
        ex de,hl             ; DE = string
        push ix              ; saved result ptr (lands at frame+20)
        ld hl,-20
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp            ; IY = frame
        push iy
        pop hl
        ld b,8
        xor a
s2f__zf:
        ld (hl),a
        inc hl
        djnz s2f__zf
        ld (iy+8),e          ; original pointer (for consumed count)
        ld (iy+9),d
        ; ---- sign ----
        ld a,(de)
        cp 2Bh               ; '+'
        jr z,s2f__sk
        cp 2Dh               ; '-'
        jr nz,s2f__nosign
        set 1,(iy+6)
s2f__sk:
        inc de
s2f__nosign:
        ; ---- integer part ----
s2f__iloop:
        ld a,(de)
        sub 30h
        cp 10
        jr nc,s2f__int_done
        ld c,a
        set 2,(iy+6)
        ld a,c
        or a
        jr nz,s2f__i_nz
        bit 3,(iy+6)
        ld a,0               ; digit is 0; LD keeps flags
        jr z,s2f__i_next     ; leading zero
s2f__i_nz:
        ld c,a
        set 3,(iy+6)
        ld a,c
        call s2f_accdig      ; CF=1 accepted
        jr c,s2f__i_next
        call s2f_dexp_inc    ; dropped integer digit
        or a
        jr z,s2f__i_next
        set 0,(iy+6)          ; sticky
s2f__i_next:
        inc de
        jr s2f__iloop
s2f__int_done:
        ; ---- fraction ----
        ld a,(de)
        cp 2Eh               ; '.'
        jr nz,s2f__no_frac
        inc de
s2f__floop:
        ld a,(de)
        sub 30h
        cp 10
        jr nc,s2f__no_frac
        ld c,a
        set 2,(iy+6)
        ld a,c
        or a
        jr nz,s2f__f_nz
        bit 3,(iy+6)
        ld a,0               ; digit is 0; LD keeps flags
        jr nz,s2f__f_acc
        call s2f_dexp_dec    ; leading zero after the point
        jr s2f__f_next
s2f__f_nz:
        ld c,a
        set 3,(iy+6)
        ld a,c
s2f__f_acc:
        call s2f_accdig
        jr nc,s2f__f_drop
        call s2f_dexp_dec    ; accepted fraction digit
        jr s2f__f_next
s2f__f_drop:
        or a
        jr z,s2f__f_next
        set 0,(iy+6)
s2f__f_next:
        inc de
        jr s2f__floop
s2f__no_frac:
        bit 2,(iy+6)
        jp z,s2f__err_invalid
        ; ---- optional exponent ----
        ld a,(de)
        cp 45h               ; 'E'
        jr z,s2f__e_try
        cp 65h               ; 'e'
        jr nz,s2f__finish
s2f__e_try:
        ld h,d
        ld l,e
        inc hl
        ld (iy+7),0
        ld a,(hl)
        cp 2Bh
        jr z,s2f__es
        cp 2Dh
        jr nz,s2f__ed0
        ld (iy+7),1
s2f__es:
        inc hl
        ld a,(hl)
s2f__ed0:
        sub 30h
        cp 10
        jr nc,s2f__finish    ; dangling E: leave unconsumed
        ld b,a               ; ev
s2f__eloop:
        inc hl
        ld a,(hl)
        sub 30h
        cp 10
        jr nc,s2f__edone
        ld c,a
        ld a,b
        cp 10
        jr nc,s2f__eclamp    ; would exceed two digits
        add a,a
        add a,a
        add a,b
        add a,a
        add a,c              ; ev*10 + d
        ld b,a
        jr s2f__eloop
s2f__eclamp:
        ld b,99
        jr s2f__eloop
s2f__edone:
        ld d,h               ; consume through the exponent
        ld e,l
        bit 0,(iy+7)
        ld a,b               ; LD keeps flags
        jr z,s2f__epos
        neg
s2f__epos:
        ; dexp += sign-extended A
        ld c,a
        ld b,0
        bit 7,c
        jr z,s2f__ep2
        ld b,0FFh
s2f__ep2:
        ld l,(iy+4)
        ld h,(iy+5)
        add hl,bc
        ld (iy+4),l
        ld (iy+5),h
s2f__finish:
        ld (iy+17),e         ; stash consumed cursor for the length calc
        ld (iy+18),d
        ; sticky jam
        bit 0,(iy+6)
        jr z,s2f__nojam
        set 0,(iy+0)
s2f__nojam:
        ; I == 0 -> zero result
        ld a,(iy+0)
        or (iy+1)
        or (iy+2)
        or (iy+3)
        jp z,s2f__ret_zero
        ; dexp range checks
        ld l,(iy+4)
        ld h,(iy+5)
        bit 7,h
        jr z,s2f__dpos
        ld bc,49
        add hl,bc
        bit 7,h
        jp nz,s2f__ret_zero  ; dexp < -49
        jr s2f__dexp_ok
s2f__dpos:
        ld a,h
        or a
        jp nz,s2f__err_over
        ld a,l
        cp 40
        jp nc,s2f__err_over  ; dexp > 39
s2f__dexp_ok:
        ; int fast path: dexp == 0 and I <= 65535
        ld a,(iy+4)
        or (iy+5)
        jr nz,s2f__fp_path
        ld a,(iy+2)
        or (iy+3)
        jr nz,s2f__fp_path
        ; write small-integer form directly
        ld c,(iy+0)
        ld b,(iy+1)
        bit 1,(iy+6)         ; neg?
        jr z,s2f__int_pos
        ; store two's complement, sign byte FF
        xor a
        sub c
        ld c,a
        ld a,0
        sbc a,b
        ld b,a
        ld a,0FFh
        jr s2f__int_wr
s2f__int_pos:
        xor a
s2f__int_wr:
        push af              ; sign byte
        call s2f_result_ptr  ; HL = caller result ptr
        pop af
        ld (hl),0
        inc hl
        ld (hl),a
        inc hl
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        ld (hl),0
        jp s2f__done_ok
s2f__fp_path:
        ; seed acc = exact FP of I
        call strio_acc_ix    ; IX = acc
        ld l,(iy+0)
        ld h,(iy+1)
        ld e,(iy+2)
        ld d,(iy+3)          ; DEHL = I (D hi)
        ld b,160
        ld c,0
        xor a                ; guard
        call normalize       ; acc = FP(I)
        ; scaling: m = |dexp|, direction from sign
        ld a,(iy+4)          ; dexp fits a signed byte by now (-49..39)
        ld c,0
        bit 7,a
        jr z,s2f__mset
        neg
        inc c                ; negative dexp -> divide
s2f__mset:
        ld (iy+7),a          ; m
        ld (iy+19),c         ; direction
        call strio_scale
        jp c,s2f__err_prop   ; propagate overflow
s2f__scaled:
        ; sign
        bit 1,(iy+6)
        jr z,s2f__copy_out
        call strio_acc_hl
        call negate_pk       ; handles FP form and zero
s2f__copy_out:
        call s2f_result_ptr  ; HL = caller result
        ex de,hl             ; DE = result
        call strio_acc_hl    ; HL = acc
        ld bc,5
        ldir
s2f__done_ok:
        ; A = consumed = DE(current) - orig; then teardown, CF=0
        ; NOTE: DE was the live cursor; still intact? copy paths used DE.
        ; The cursor was stored nowhere after parse -- recompute is
        ; impossible, so it is stashed at +17/18 right after parsing.
        ld a,(iy+17)
        sub (iy+8)
        ; teardown: frame 20 + saved IX 2
        ld hl,22
        add hl,sp
        ld sp,hl
        or a                 ; CF=0 (A = length; flags from SUB are fine,
                             ; but clear CF explicitly)
        ret
s2f__ret_zero:
        call s2f_result_ptr
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        inc hl
        ld (hl),a
        jr s2f__done_ok
s2f__err_invalid:
        ld a,ERR_INVALID
        jr s2f__err_out
s2f__err_over:
        ld a,ERR_OVERFLOW
        jr s2f__err_out
s2f__err_prop:
        ; A already holds the code from fp_mul/fp_div
s2f__err_out:
        ld hl,22
        add hl,sp
        ld sp,hl
        scf
        ret

; HL := caller's result pointer (saved IX at frame+20)
s2f_result_ptr:
        ld l,(iy+20)
        ld h,(iy+21)
        ret

; accumulate digit A into I if I <= 429496728 (19999998h). CF=1 accepted.
; Preserves A (the digit) and DE.
s2f_accdig:
        push de
        push af
        ld a,(iy+3)
        cp 19h
        jr c,s2f_accdig__ok
        jr nz,s2f_accdig__rej
        ld a,(iy+2)
        cp 99h
        jr c,s2f_accdig__ok
        jr nz,s2f_accdig__rej
        ld a,(iy+1)
        cp 99h
        jr c,s2f_accdig__ok
        jr nz,s2f_accdig__rej
        ld a,(iy+0)
        cp 99h
        jr nc,s2f_accdig__rej
s2f_accdig__ok:
        ld l,(iy+0)
        ld h,(iy+1)
        ld e,(iy+2)
        ld d,(iy+3)
        add hl,hl
        rl e
        rl d                 ; I*2
        push de
        push hl
        add hl,hl
        rl e
        rl d
        add hl,hl
        rl e
        rl d                 ; I*8
        pop bc
        add hl,bc
        pop bc
        ex de,hl
        adc hl,bc
        ex de,hl             ; I*10
        pop af
        push af
        add a,l
        ld l,a
        jr nc,s2f_accdig__st
        inc h
        jr nz,s2f_accdig__st
        inc e
        jr nz,s2f_accdig__st
        inc d
s2f_accdig__st:
        ld (iy+0),l
        ld (iy+1),h
        ld (iy+2),e
        ld (iy+3),d
        pop af
        pop de
        scf
        ret
s2f_accdig__rej:
        pop af
        pop de
        or a
        ret

s2f_dexp_inc:
        inc (iy+4)
        ret nz
        inc (iy+5)
        ret
s2f_dexp_dec:
        push af
        ld a,(iy+4)
        sub 1
        ld (iy+4),a
        jr nc,s2f_dexp_dec__x
        dec (iy+5)
s2f_dexp_dec__x:
        pop af
        ret

; ======================================================================
; fp_fp2str: format 5-byte at (HL) into buffer at (DE), NUL-terminated.
; Out: CF=0, A = length (excluding NUL).
; Frame (IY+): 0..1 e10, 2 flags(0 neg), 3 n, 4 scratch, 5 est,
;              6..9 N8, 10..14 acc, 16..23 digits (LSB-extracted first,
;              so d1 = MSD lives at +23). Out ptr at +24, src at +26.
;              Slots 7, 15..16, 19 are borrowed by strio_scale before
;              N8/digits are written.
; ======================================================================
fp_fp2str:
        push hl              ; src (lands at frame+26)
        push de              ; out (frame+24)
        ld hl,-24
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp
        ; copy source into acc
        call strio_acc_hl
        ex de,hl             ; DE = acc
        ld l,(iy+26)
        ld h,(iy+27)         ; HL = src
        ld bc,5
        ldir
        xor a
        ld (iy+2),a
        ; zero?
        call strio_acc_hl
        call is_zero_pk
        jr nz,f2s__nz
        ; "0"
        ld l,(iy+24)
        ld h,(iy+25)
        ld (hl),30h
        inc hl
        ld (hl),0
        ld a,1
        jp f2s__done
f2s__nz:
        ld a,(iy+10)         ; exponent byte
        or a
        jp z,f2s__intform
        ; FP: sign, magnitude
        ld a,(iy+11)
        bit 7,a
        jr z,f2s__pos
        ld c,a
        set 0,(iy+2)          ; neg
        ld a,c
        res 7,a
        ld (iy+11),a
f2s__pos:
        ; est = (e >= 129) ? ((e-129)*77)>>8 : -(((129-e)*77+255)>>8)
        ld a,(iy+10)
        sub 129
        jr nc,f2s__est_p
        neg                  ; A = 129 - e
        call f2s_mul77       ; HL = A*77
        ld a,l
        or a
        ld a,h
        jr z,f2s__est_n1
        inc a                ; ceil
f2s__est_n1:
        ld (iy+7),a          ; m = |est|
        ld (iy+19),0         ; est negative: multiply up
        neg
        jr f2s__est_done
f2s__est_p:
        call f2s_mul77
        ld a,h               ; est = product >> 8
        ld (iy+7),a
        ld (iy+19),1         ; est positive: divide down
f2s__est_done:
        ; e10 = 7 + est (A = signed est)
        ld c,a
        ld b,0
        bit 7,c
        jr z,f2s__e10s
        ld b,0FFh
f2s__e10s:
        ld hl,7
        add hl,bc
        ld (iy+0),l
        ld (iy+1),h
        ; coarse scaling by bits of |est|
        call strio_scale
f2s__fine:
        ; while acc >= 1e8: acc /= 10, e10++
        call strio_acc_hl
        ld de,C1E8
        call fp_cmp
        bit 7,a              ; A=FF -> less
        jr nz,f2s__fine2
        call strio_acc_ix
        ld de,P10_0
        call fp_div
        inc (iy+0)
        jr nz,f2s__fine
        inc (iy+1)
        jr f2s__fine
f2s__fine2:
        ; while acc < 1e7: acc *= 10, e10--
        call strio_acc_hl
        ld de,C1E7
        call fp_cmp
        bit 7,a
        jr z,f2s__round      ; acc >= 1e7
        call strio_acc_ix
        ld de,P10_0
        call fp_mul
        ld a,(iy+0)
        sub 1
        ld (iy+0),a
        jr nc,f2s__fine2
        dec (iy+1)
        jr f2s__fine2
f2s__round:
        ; acc = floor(acc + 0.5)
        call strio_acc_ix
        ld de,CHALF
        call fp_add
        call strio_acc_ix
        call fp_int
        ; extract N8 integer from acc (FP form, e in 152..155; > 65535)
        ld l,(iy+14)
        ld h,(iy+13)
        ld e,(iy+12)
        ld a,(iy+11)
        or 80h
        ld d,a               ; DEHL = mantissa
        ld a,160
        sub (iy+10)          ; shift count (5..8)
f2s__nsh:
        srl d
        rr e
        rr h
        rr l
        dec a
        jr nz,f2s__nsh
        ; N8 == 1e8 (05F5E100h)? then N8 = 1e7, e10++
        ld a,d
        cp 05h
        jr nz,f2s__digits
        ld a,e
        cp 0F5h
        jr nz,f2s__digits
        ld a,h
        cp 0E1h
        jr nz,f2s__digits
        ld a,l
        or a
        jr nz,f2s__digits
        ld d,0
        ld e,98h
        ld h,96h
        ld l,80h             ; 00989680h = 1e7
        inc (iy+0)
        jr nz,f2s__digits
        inc (iy+1)
f2s__digits:
        ; extract 8 digits LSB-first into +16..+23
        ld b,8
        call f2s_extract
        ; strip trailing zeros: n = 8; digits d_i at IY+(24-i)
        ld b,8
        ld c,16
f2s__strip:
        ld a,b
        cp 1
        jr z,f2s__layout
        push iy
        pop hl
        ld a,c
        call f2s_addr        ; HL = IY + A
        ld a,(hl)
        or a
        jr nz,f2s__layout
        dec b
        inc c
        jr f2s__strip
f2s__layout:
        ld (iy+3),b          ; n
        ld l,(iy+24)
        ld h,(iy+25)
        ex de,hl             ; DE = out cursor
        bit 0,(iy+2)
        jr z,f2s__l0
        ld a,2Dh             ; '-'
        ld (de),a
        inc de
f2s__l0:
        ; E = e10 (signed 16 fits signed 8 here: -39..38)
        ld a,(iy+0)
        ; branch: 0 <= E <= 12 fixed; -5 <= E < 0 small; else E-form
        bit 7,a
        jr nz,f2s__neg_e
        cp 13
        jr c,f2s__fixed
        jr f2s__eform
f2s__neg_e:
        cp 0FBh              ; -5
        jr nc,f2s__small
        jr f2s__eform
; ---------------- fixed notation, E >= 0 ----------------
f2s__fixed:
        ld b,a               ; E
        ld c,(iy+3)          ; n
        ; if E >= n-1: all digits then E-n+1 zeros
        ld a,c
        dec a
        cp b
        jr z,f2s__fix_all
        jr c,f2s__fix_all    ; n-1 <= E
        ; E < n-1: d1..d(E+1) '.' rest
        ld a,b
        inc a
        call f2s_emit_digits ; emit A digits from MSD; updates cursor
        ld a,2Eh
        ld (de),a
        inc de
        ld a,(iy+3)
        sub b
        dec a                ; remaining = n - (E+1)
        call f2s_emit_more
        jr f2s__terminate
f2s__fix_all:
        ld a,c
        call f2s_emit_digits
        ld a,b
        sub c
        inc a                ; E - n + 1 zeros
        jr z,f2s__terminate
        ld b,a
f2s__fz:
        ld a,30h
        ld (de),a
        inc de
        djnz f2s__fz
        jr f2s__terminate
; ---------------- 0.00ddd, -5 <= E < 0 ----------------
f2s__small:
        neg                  ; A = -E (1..5)
        ld b,a
        ld a,30h
        ld (de),a
        inc de
        ld a,2Eh
        ld (de),a
        inc de
        dec b
        jr z,f2s__sm2
f2s__smz:
        ld a,30h
        ld (de),a
        inc de
        djnz f2s__smz
f2s__sm2:
        ld a,(iy+3)
        call f2s_emit_digits
        jr f2s__terminate
; ---------------- E-form ----------------
f2s__eform:
        ld a,1
        call f2s_emit_digits ; d1
        ld a,(iy+3)
        dec a
        jr z,f2s__ee
        push af
        ld a,2Eh
        ld (de),a
        inc de
        pop af
        call f2s_emit_more
f2s__ee:
        ld a,45h             ; 'E'
        ld (de),a
        inc de
        ld a,(iy+0)
        bit 7,a
        jr z,f2s__ep
        push af
        ld a,2Dh
        ld (de),a
        inc de
        pop af
        neg
f2s__ep:
        ; two-digit decimal of A (1..39)
        ld b,0
f2s__etens:
        cp 10
        jr c,f2s__eemit
        sub 10
        inc b
        jr f2s__etens
f2s__eemit:
        ld c,a
        ld a,b
        or a
        jr z,f2s__eones
        add a,30h
        ld (de),a
        inc de
f2s__eones:
        ld a,c
        add a,30h
        ld (de),a
        inc de
f2s__terminate:
        xor a
        ld (de),a            ; NUL
        ; length = DE - orig out
        ld a,e
        sub (iy+24)
        jp f2s__done
; ---------------- small-integer form ----------------
f2s__intform:
        ld c,(iy+12)         ; lo
        ld b,(iy+13)         ; hi
        ld a,(iy+11)         ; sign byte
        or a
        jr z,f2s__ipos
        set 0,(iy+2)          ; remember negative
        xor a
        sub c
        ld c,a
        ld a,0
        sbc a,b
        ld b,a               ; magnitude
f2s__ipos:
        ; extract 5 digits of BC via div10 on 32-bit 0:0:B:C
        ; (DE is free here; the out cursor is fetched after extraction)
        ld h,b
        ld l,c
        ld d,0
        ld e,0
        ld b,5
        call f2s_extract
        ; now take the out cursor and emit the sign
        ld l,(iy+24)
        ld h,(iy+25)
        ex de,hl             ; DE = out cursor
        bit 0,(iy+2)
        jr z,f2s__inosign
        ld a,2Dh
        ld (de),a
        inc de
f2s__inosign:
        ; emit from MSD (+20 down), skipping leading zeros
        ld b,5
        ld c,20
f2s__iskip:
        ld a,b
        cp 1
        jr z,f2s__iemit
        push iy
        pop hl
        ld a,c
        call f2s_addr
        ld a,(hl)
        or a
        jr nz,f2s__iemit
        dec b
        dec c
        jr f2s__iskip
f2s__iemit:
        ; emit B digits from index C downward
        push iy
        pop hl
        ld a,c
        call f2s_addr
f2s__iel:
        ld a,(hl)
        add a,30h
        ld (de),a
        inc de
        dec hl
        djnz f2s__iel
        jr f2s__terminate
f2s__done:
        ld hl,28
        add hl,sp
        ld sp,hl
        or a
        ret

; HL = IY + A (A = 0..127)
f2s_addr:
        push bc
        push iy
        pop hl
        ld c,a
        ld b,0
        add hl,bc
        pop bc
        ret

; store digit A at IY+C (C runtime): via f2s_addr
f2s_store:
        push hl
        push af
        ld a,c
        call f2s_addr
        pop af
        ld (hl),a
        pop hl
        ret

; extract B digits of DEHL LSB-first into IY+16.. (div10 + store)
f2s_extract:
        ld c,16
f2s_extract__l:
        push bc
        call f2s_div10
        pop bc
        call f2s_store
        inc c
        djnz f2s_extract__l
        ret

; DEHL /= 10 (32-bit), A = remainder. Clobbers B.
f2s_div10:
        xor a
        ld b,32
f2s_div10__l:
        add hl,hl
        rl e
        rl d
        rla
        cp 10
        jr c,f2s_div10__s
        sub 10
        inc l
f2s_div10__s:
        djnz f2s_div10__l
        ret

; HL = A * 77 (A <= 128). Clobbers BC.
f2s_mul77:
        ld c,a
        ld b,0
        ld h,b
        ld l,c
        add hl,hl            ; 2
        add hl,hl            ; 4
        add hl,hl
        add hl,bc            ; 9
        add hl,hl
        add hl,bc            ; 19
        add hl,hl            ; 38
        add hl,hl
        add hl,bc            ; 77
        ret

; emit A digits starting at the MSD (IY+23) going down; DE = out cursor.
; IY+4 is the "next MSD index" cursor; f2s_emit_more continues with A
; more digits from where the previous emission stopped.
f2s_emit_digits:
        ld (iy+4),23         ; start from MSD; fall through
f2s_emit_more:
        or a
        ret z
        push bc
        ld b,a
f2s_emit_more__l:
        push bc
        ld a,(iy+4)
        call f2s_addr
        ld a,(hl)
        add a,30h
        ld (de),a
        inc de
        dec (iy+4)
        pop bc
        djnz f2s_emit_more__l
        pop bc
        ret
