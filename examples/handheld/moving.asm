; Draw at x=0, erase, then draw at x=1. No wall-clock dependency.
ld a,1
out (0x42),a
xor a
out (0x40),a
out (0x41),a
out (0x42),a
ld a,1
out (0x42),a
halt
