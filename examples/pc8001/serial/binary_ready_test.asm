; Host must ARM idle before invoking USR. Same checked binary test as pattern_test,
; with BP readiness notification so the host never sends before UART init.
org 0xd000
POLL_LIMIT equ 0xffff
POLL_ROUNDS equ 16
    push af
    push bc
    push de
    push hl
    call uart_init
    ld a,0x42
    call uart_tx
    jp c,uart_finish
    ld a,0x50
    call uart_tx
    jp c,uart_finish
    ld b,0
    ld c,0
    ld hl,RX_BUFFER
binary_loop:
    call uart_rx
    jp c,uart_finish
    ld (hl),a
    inc hl
    cp c
    call nz,record_mismatch
    call uart_tx
    jp c,uart_finish
    inc c
    djnz binary_loop
    ld a,(REPORT)
    or a
    jp nz,uart_finish
    ld a,0x4f
    call uart_tx
    jp c,uart_finish
    ld a,0x4b
    call uart_tx
    jp uart_finish
include "common.inc"
