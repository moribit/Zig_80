org 0xd000
    ld a,0x52
    ld (0xd710),a
    jp 0xd803 ; Explicit return vector restores loader SP/UART; no ROM call.
