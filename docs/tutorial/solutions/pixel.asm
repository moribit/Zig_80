org 0x0000
VRAM equ 0xC000

start:
    ld hl,VRAM + 128 + 10
    ld (hl),0x02
    halt
