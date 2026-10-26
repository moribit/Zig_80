; Scratch D700-D710 belongs to this development application, below loader D800.
org 0xd000
    ld hl,0xd700
    ld b,16
    xor a
write_check:
    ld (hl),a
    cp (hl)
    jr nz,failed
    inc hl
    inc a
    djnz write_check
    xor a
    ld (0xd710),a
    ret
failed:
    ld a,1
    ld (0xd710),a
    ret
