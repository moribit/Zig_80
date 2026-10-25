; Poll a deterministic 256-T-state timer until three ticks have elapsed.
xor a
out (0x33),a
ld a,1
out (0x34),a
out (0x30),a
wait:
in a,(0x31)
cp 3
jr c,wait
ld (0x8000),a
out (0x42),a
xor a
out (0x30),a
halt
