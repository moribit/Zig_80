; No heap/interrupts/ROM calls. All waits are bounded by 65536 status polls.
; A/C: received byte or carry=failure. BC/DE/HL preserved.
uart_init:
    xor a
    out (0x21),a
    out (0x21),a
    out (0x21),a
    ld a,0x40
    out (0x21),a
    ld a,0x4e
    out (0x21),a
    ld a,0x37
    out (0x21),a
    ld a,(0xea66)
    and 0xcf
    or 0x20
    out (0x30),a
    ret
uart_rx:
    push bc
    ld bc,POLL_LIMIT
uart_rx_poll:
    in a,(0x21)
    ld (LAST_STATUS),a
    and 0x38
    jr nz,uart_rx_error
    in a,(0x21)
    and 2
    jr nz,uart_rx_ready
    dec bc
    ld a,b
    or c
    jr nz,uart_rx_poll
    ld a,1
    jr uart_rx_failed
uart_rx_error:
    ld a,2
uart_rx_failed:
    ld (LAST_FAULT),a
    pop bc
    scf
    ret
uart_rx_ready:
    in a,(0x20)
    pop bc
    or a
    ret
uart_tx:
    push de
    push af
    ld e,1
    call uart_wait_tx
    jr c,uart_tx_failed
    pop af
    out (0x20),a
    pop de
    or a
    ret
uart_tx_failed:
    pop af
    pop de
    scf
    ret
uart_drain:
    push de
    ld e,4
    call uart_wait_tx
    pop de
    ret
uart_wait_tx:
    push bc
    ld bc,POLL_LIMIT
uart_tx_poll:
    in a,(0x21)
    and e
    jr nz,uart_tx_ready
    dec bc
    ld a,b
    or c
    jr nz,uart_tx_poll
    pop bc
    scf
    ret
uart_tx_ready:
    pop bc
    or a
    ret
