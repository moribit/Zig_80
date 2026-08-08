include "constants.inc"
org 0
start:
    ld hl,VRAM
include "draw.inc"
incbin "sprite.bin"
    halt
