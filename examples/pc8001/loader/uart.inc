; No heap/interrupts/ROM calls. All waits are bounded by 65536 status polls.
; A/C: received byte or carry=failure. BC/DE/HL preserved.
uart_init:
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
    ld a,(0xea66)
    and 0xcf
    or 0x20
    out (0x30),a
    ret
include "uart_io.inc"
