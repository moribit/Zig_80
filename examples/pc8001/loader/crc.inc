; CRC16-CCITT-FALSE: DE accumulator, A input, BC preserved.
crc_byte:
    push bc
    xor d
    ld d,a
    ld b,8
crc_bit:
    sla e
    rl d
    jr nc,crc_next
    ld a,e
    xor 0x21
    ld e,a
    ld a,d
    xor 0x10
    ld d,a
crc_next:
    djnz crc_bit
    pop bc
    ret
