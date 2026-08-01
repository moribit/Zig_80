org 0x0000
VRAM equ 0xC000
start:
    ld hl, VRAM
    ld (hl), 0x01
    halt
