; zenpoint fp_sqrt: correctly rounded square root (spec transcendentals.md).
; SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-only OR GPL-3.0-only OR MPL-2.0
; Copyright (c) 2026 haitch <h@ual.li>
;
; Binary restoring integer square root over the 64-bit radicand; exact
; remainder gives RNE without guard machinery. Root lives in the
; alternate DEHL; the radicand N (8 bytes) and remainder (5 bytes) are
; one contiguous 13-byte frame field so each bring-down is a single
; rl-chain pass. Frame via IY:
;   +0..7 N, +8..12 rem, +13 er; pushed M at +14..17, saved IX at +18.

fp_sqrt:
        ; sign check on the packed form (both forms: byte1 bit7 / FFh)
        inc hl
        ld a,(hl)
        dec hl
        and 80h
        jr z,fp_sqrt__notneg
        ld a,2               ; ERR_INVALID
        scf
        ret
fp_sqrt__notneg:
        call is_zero_pk
        jp z,ret_zero
        call unpack          ; B=e, C=sign(0), DEHL=M (consumes HL)
        push ix              ; caller result ptr
        push de              ; M hi
        push hl              ; M lo
        ld hl,-14
        add hl,sp
        ld sp,hl
        ld iy,0
        add iy,sp
        ; er = ((e+1) >> 1) + 64
        ld a,b
        add a,1              ; CF = bit 8 of e+1
        rra                  ; (e+1) >> 1 with the carry shifted in
        add a,64
        ld (iy+13),a
        ; N = M << 32: [0,0,0,0, L,H,E,D]
        xor a
        ld (iy+0),a
        ld (iy+1),a
        ld (iy+2),a
        ld (iy+3),a
        ld a,(iy+14)
        ld (iy+4),a
        ld a,(iy+15)
        ld (iy+5),a
        ld a,(iy+16)
        ld (iy+6),a
        ld a,(iy+17)
        ld (iy+7),a
        ; odd exponent: N >>= 1
        ld a,b
        and 1
        jr z,fp_sqrt__even
        push iy
        pop hl
        ld de,7
        add hl,de
        srl (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
        dec hl
        rr (hl)
fp_sqrt__even:
        ; rem = 0
        xor a
        ld (iy+8),a
        ld (iy+9),a
        ld (iy+10),a
        ld (iy+11),a
        ld (iy+12),a
        ; root (alt DEHL) = 0
        exx
        ld hl,0
        ld d,h
        ld e,l
        exx
        ld b,32
fp_sqrt__loop:
        call sq_shift13
        call sq_shift13
        call sq_trial_sub
        jr c,fp_sqrt__reject
        ; accepted: root = (root << 1) | 1
        exx
        add hl,hl
        rl e
        rl d
        inc l                ; bit0 was 0
        exx
        jr fp_sqrt__next
fp_sqrt__reject:
        call sq_trial_add    ; restore remainder
        exx
        add hl,hl
        rl e
        rl d
        exx
fp_sqrt__next:
        djnz fp_sqrt__loop
        ; round up iff rem > root
        ld a,(iy+12)
        or a
        jr nz,fp_sqrt__up    ; rem has bit 32+: certainly > root
        exx                  ; root visible
        ld a,(iy+11)
        cp d
        jr c,fp_sqrt__down_x
        jr nz,fp_sqrt__up_x
        ld a,(iy+10)
        cp e
        jr c,fp_sqrt__down_x
        jr nz,fp_sqrt__up_x
        ld a,(iy+9)
        cp h
        jr c,fp_sqrt__down_x
        jr nz,fp_sqrt__up_x
        ld a,(iy+8)
        cp l
        jr c,fp_sqrt__down_x
        jr z,fp_sqrt__down_x ; rem == root: below the tie point
fp_sqrt__up_x:
        exx
        jr fp_sqrt__up
fp_sqrt__down_x:
        exx
        jr fp_sqrt__pack
fp_sqrt__up:
        exx
        inc l
        jr nz,fp_sqrt__upok
        inc h
        jr nz,fp_sqrt__upok
        inc e
        jr nz,fp_sqrt__upok
        inc d
        jr nz,fp_sqrt__upok
        ld d,80h             ; carried to 2^32
        inc (iy+13)
fp_sqrt__upok:
        exx
fp_sqrt__pack:
        ; move root to main, restore result ptr, teardown, pack
        exx                  ; alt: root
        push de
        push hl
        exx                  ; main
        pop hl
        pop de               ; DEHL = root
        ld c,(iy+18)
        ld b,(iy+19)
        push bc
        pop ix               ; caller result ptr
        ld b,(iy+13)         ; exponent
        ld c,0               ; sign positive
        exx
        ld hl,20             ; frame 14 + M 4 + saved IX 2
        add hl,sp
        ld sp,hl
        exx
        xor a                ; guard 0 (also CF=0)
        jp round_pack

; one left shift of the contiguous 13-byte N||rem field
sq_shift13:
        push iy
        pop hl
        sla (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        inc hl
        rl (hl)
        ret

; subtract T = (root << 2) | 1 from rem (5 bytes at IY+8), in place.
; CF = borrow (reject). Preserves B. Root is in the alternate DEHL.
sq_trial_sub:
        push iy
        pop hl
        ld de,8
        add hl,de            ; HL = rem
        ; byte 0: (L' << 2) | 1
        exx
        ld a,l
        exx
        add a,a
        add a,a
        or 1
        ld c,a
        ld a,(hl)
        sub c
        ld (hl),a
        inc hl
        ; byte 1: (H' << 2) | (L' >> 6)
        push af
        exx
        ld a,l
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,h
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        sbc a,c
        ld (hl),a
        inc hl
        ; byte 2: (E' << 2) | (H' >> 6)
        push af
        exx
        ld a,h
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,e
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        sbc a,c
        ld (hl),a
        inc hl
        ; byte 3: (D' << 2) | (E' >> 6)
        push af
        exx
        ld a,e
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,d
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        sbc a,c
        ld (hl),a
        inc hl
        ; byte 4: D' >> 6
        push af
        exx
        ld a,d
        exx
        rlca
        rlca
        and 03h
        ld c,a
        pop af
        ld a,(hl)
        sbc a,c
        ld (hl),a
        ret

; add T back (restore). Same byte recipe with an add/adc chain.
sq_trial_add:
        push iy
        pop hl
        ld de,8
        add hl,de
        exx
        ld a,l
        exx
        add a,a
        add a,a
        or 1
        ld c,a
        ld a,(hl)
        add a,c
        ld (hl),a
        inc hl
        push af
        exx
        ld a,l
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,h
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        adc a,c
        ld (hl),a
        inc hl
        push af
        exx
        ld a,h
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,e
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        adc a,c
        ld (hl),a
        inc hl
        push af
        exx
        ld a,e
        exx
        rlca
        rlca
        and 03h
        ld c,a
        exx
        ld a,d
        exx
        add a,a
        add a,a
        or c
        ld c,a
        pop af
        ld a,(hl)
        adc a,c
        ld (hl),a
        inc hl
        push af
        exx
        ld a,d
        exx
        rlca
        rlca
        and 03h
        ld c,a
        pop af
        ld a,(hl)
        adc a,c
        ld (hl),a
        ret
