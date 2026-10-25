org 0xd000
POLL_LIMIT equ 0xffff
POLL_ROUNDS equ 16
entry:
    push af
    push bc
    push de
    push hl
    call uart_init
    ld hl,RX_BUFFER
    ld b,0
    ld c,0
pattern_loop:
    call uart_rx
    jp c,uart_finish
    cp c
    call nz,record_mismatch
    ld (hl),a
    call uart_tx
    jp c,uart_finish
    inc hl
    inc c
    djnz pattern_loop
    jp uart_finish
include "common.inc"
