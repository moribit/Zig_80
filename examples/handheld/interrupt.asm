; IM1 timer ISR at 0038. Padding is explicit: ORG does not pad flat output.
jp start
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0,0,0,0
db 0,0,0,0,0
isr:
push af
inc (hl)
ld a,0x81
out (0x30),a
pop af
ei
reti
start:
ld sp,0xffff
ld hl,0x8000
im 1
xor a
out (0x33),a
ld a,2
out (0x34),a
ld a,1
out (0x30),a
ei
wait:
ld a,(0x8000)
cp 3
jr c,wait
di
xor a
out (0x30),a
ld a,(0x8000)
out (0x42),a
halt
