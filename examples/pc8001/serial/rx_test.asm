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
    ld de,expected
    ld b,expected_end-expected
rx_loop:
    call uart_rx
    jp c,uart_finish
    ld (hl),a
    ld c,a
    ld a,(de)
    cp c
    call nz,record_mismatch
    inc hl
    inc de
    djnz rx_loop
    jp uart_finish
expected:
    db "HELLO FROM PICO 2"
expected_end:
include "common.inc"
