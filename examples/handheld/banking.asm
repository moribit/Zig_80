; Window 4000 maps ROM bank 1; switch to bank 2 and restore.
ld a,2
out (0x20),a
ld a,(0x4000)
ld (0xc000),a
ld a,1
out (0x20),a
; Independently switch the 8000 RAM window.
ld a,0x11
ld (0x8000),a
ld a,2
out (0x21),a
ld a,0x22
ld (0x8000),a
xor a
out (0x21),a
ld a,(0x8000)
ld (0xc001),a
halt
