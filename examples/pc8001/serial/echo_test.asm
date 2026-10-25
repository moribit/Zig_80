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
    ld b,17
echo_loop:
    call uart_rx
    jp c,uart_finish
    ld (hl),a
    call uart_tx
    jp c,uart_finish
    inc hl
    djnz echo_loop
    jp uart_finish
include "common.inc"
