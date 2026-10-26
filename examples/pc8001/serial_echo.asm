; App owns UART from EXEC ACK completion until RET. Echo exactly 17 bytes.
; Host must send a separate raw 17-byte app payload in the SAME leased session.
; Returning restores UART mode and transfers ownership back to the loader.
org 0xd000
    ld b,17
next_byte:
    ld de,0
rx_wait:
    in a,(0x21)
    and 0x38
    jr nz,done
    in a,(0x21)
    and 2
    jr nz,rx_ready
    dec de
    ld a,d
    or e
    jr nz,rx_wait
    jr done
rx_ready:
    in a,(0x20)
    ld c,a
    ld de,0
tx_wait:
    in a,(0x21)
    and 1
    jr nz,tx_ready
    dec de
    ld a,d
    or e
    jr nz,tx_wait
    jr done
tx_ready:
    ld a,c
    out (0x20),a
    djnz next_byte
    ld de,0
drain:
    in a,(0x21)
    and 4
    jr nz,done
    dec de
    ld a,d
    or e
    jr nz,drain
done:
    ret
