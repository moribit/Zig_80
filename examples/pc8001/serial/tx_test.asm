org 0xd000
POLL_LIMIT equ 0xffff
POLL_ROUNDS equ 16
entry:
    push af
    push bc
    push de
    push hl
    call uart_init
    ld hl,message
    ld b,message_end-message
tx_loop:
    ld a,(hl)
    call uart_tx
    jp c,uart_finish
    inc hl
    djnz tx_loop
    jp uart_finish
message:
    db "HELLO FROM PC-8001",13,10
message_end:
include "common.inc"
