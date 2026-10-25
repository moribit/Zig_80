; Script events apply before instruction zero. A maps to bit 4.
in a,(0x10)
and 0x10
rrca
rrca
rrca
rrca
ld (0x8000),a
out (0x42),a
halt
