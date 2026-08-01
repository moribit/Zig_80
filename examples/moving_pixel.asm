org 0x0000
VRAM equ 0xC000
INPUT equ 0xC400
start:
    ld hl, VRAM + 1
    ld a, (INPUT)
    cp 4
    jr z, left
    inc hl
    jp draw
left:
    dec hl
draw:
    ld (hl), 1
    halt
