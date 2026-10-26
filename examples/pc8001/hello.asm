; Loader ABI: DI and private loader stack. No guessed ROM entry points.
; uart_init uses EA66's port-30 shadow, whose bit 0 selects 80 (1) / 40 (0).
; Width 40 displays even character cells only. Preserve skipped cells,
; attributes, the port shadow and UART selection; do not force a video mode.
org 0xd000
    ld hl,message
    ld de,0xf300
    ld b,message_end-message
    ld a,(0xea66)
    and 1
    ld c,a
write_character:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    bit 0,c
    jr nz,next_character
    inc de
next_character:
    djnz write_character
    ld a,c ; Report the display mode in the loader return notification: 0=40, 1=80.
    ret
message:
    db "HELLO FROM ZIG_80"
message_end:
