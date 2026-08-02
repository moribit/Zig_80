org 0x0000

start:
    ld a,5

loop:
    dec a
    jr nz,loop
    halt
