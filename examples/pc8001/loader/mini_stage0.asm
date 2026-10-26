include "layout.inc"
org 0xe300
; Minimal front-end. N-BASIC USR only, CLEAR 300,&HCFFF first.
; Preserve caller registers/stack for the unmodified E400 relay.
; Failure is a latched DI stop loop: reset and restart, never execute a partial relay.
    di
    push af
    push bc
    push de
    push hl
    ld a,(0xea66)
    and 0xcf
    or 0x20
    out (0x30),a
    xor a
    out (0x21),a
    out (0x21),a
    out (0x21),a
    ld a,0x40
    out (0x21),a
    ld a,0x4e
    out (0x21),a
    ld a,0x37
    out (0x21),a
    out (0x20),a ; READY=37h, one byte into a freshly reset TX register.
    ld hl,0xe400
    ld bc,333
    ld d,0
mini_receive:
    call mini_rx
    jr c,mini_failed
    ld (hl),a
    add a,d
    ld d,a
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,mini_receive
    call mini_rx
    jr c,mini_failed
    add a,d ; Sum(payload + trailing two's-complement checksum) must be zero.
    jr nz,mini_failed
    pop hl
    pop de
    pop bc
    pop af
    jp 0xe400
mini_failed:
    jr mini_failed
mini_rx:
    push bc
    ld bc,0 ; 65536 polls, reset for every byte; finite timeout, not wall clock.
mini_poll:
    in a,(0x21)
    and 0x3a ; RX Ready plus PE/OE/FE.
    jr nz,mini_status
    dec bc
    ld a,b
    or c
    jr nz,mini_poll
mini_bad:
    pop bc
    scf
    ret
mini_status:
    cp 2 ; Only RX Ready, no error bits. CP equality clears carry.
    jr nz,mini_bad
    in a,(0x20)
    pop bc
    ret
mini_end:
