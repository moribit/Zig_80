; Original routines for the original PC-8001. Not PC-8001mkII/PC-8801.
; 8251: mode 4E = async x16, 8 data, no parity, 1 stop. Needs 4800 Hz TxC/RxC.
; Caller reserves D000-D50B. No private stack; AF/BC/DE/HL saved at entry.
UART_DATA equ 0x20
UART_CONTROL equ 0x21
PORT30_SHADOW equ 0xea66
RX_BUFFER equ 0xd400
REPORT equ 0xd500
TX_COUNT equ 0xd501
RX_COUNT equ 0xd503
MISMATCH_COUNT equ 0xd505
TIMEOUT_COUNT equ 0xd507
ERROR_COUNT equ 0xd509
LAST_STATUS equ 0xd50b

uart_init:
    ld a,(PORT30_SHADOW)
    ld (saved_port30),a
    ld hl,REPORT
    ld b,12
    xor a
clear_report:
    ld (hl),a
    inc hl
    djnz clear_report
    out (UART_CONTROL),a
    out (UART_CONTROL),a
    out (UART_CONTROL),a
    ld a,0x40
    out (UART_CONTROL),a
    ld a,0x4e
    out (UART_CONTROL),a
    ld a,0x37
    out (UART_CONTROL),a
    ld a,(saved_port30)
    and 0xcf
    or 0x20
    out (0x30),a
    ret

; E = readiness mask. Preserves BC/DE; carry signals timeout or USART error.
uart_wait:
    push bc
    push de
    ld d,POLL_ROUNDS
wait_reload:
    ld bc,POLL_LIMIT
wait_poll:
    in a,(UART_CONTROL)
    ld (LAST_STATUS),a
    and 0x38
    jr nz,wait_error
    in a,(UART_CONTROL)
    and e
    jr nz,wait_ready
    dec bc
    ld a,b
    or c
    jr nz,wait_poll
    dec d
    jr nz,wait_reload
    ld a,1
    ld (REPORT),a
    push hl
    ld hl,(TIMEOUT_COUNT)
    inc hl
    ld (TIMEOUT_COUNT),hl
    pop hl
    jr wait_failed
wait_error:
    ld a,2
    ld (REPORT),a
    push hl
    ld hl,(ERROR_COUNT)
    inc hl
    ld (ERROR_COUNT),hl
    pop hl
wait_failed:
    pop de
    pop bc
    scf
    ret
wait_ready:
    pop de
    pop bc
    or a
    ret

uart_tx:
    push de
    push af
    ld e,1
    call uart_wait
    jr c,tx_failed
    pop af
    out (UART_DATA),a
    push hl
    ld hl,(TX_COUNT)
    inc hl
    ld (TX_COUNT),hl
    pop hl
    pop de
    or a
    ret
tx_failed:
    pop af
    pop de
    scf
    ret

uart_rx:
    push de
    ld e,2
    call uart_wait
    pop de
    ret c
    in a,(UART_DATA)
    push af
    push hl
    ld hl,(RX_COUNT)
    inc hl
    ld (RX_COUNT),hl
    pop hl
    pop af
    or a
    ret

record_mismatch:
    push af
    push hl
    ld a,3
    ld (REPORT),a
    ld hl,(MISMATCH_COUNT)
    inc hl
    ld (MISMATCH_COUNT),hl
    pop hl
    pop af
    ret

uart_finish:
    ld a,(REPORT)
    or a
    jr nz,finish_disable
    ld hl,(TX_COUNT)
    ld a,h
    or l
    jr z,finish_disable
    ld e,4
    call uart_wait ; Wait for the final STOP bit (TxEMPTY), not just TxRDY.
finish_disable:
    xor a
    out (UART_CONTROL),a
    ld a,(saved_port30)
    out (0x30),a
    pop hl
    pop de
    pop bc
    pop af
    ret
saved_port30:
    db 0
