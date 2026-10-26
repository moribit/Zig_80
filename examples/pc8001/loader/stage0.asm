include "layout.inc"
POLL_LIMIT equ 0
org STAGE0
; Enter ONLY via N-BASIC USR after CLEAR 300,&HCFFF, interrupts enabled.
; Reserve D000-E8FF before entry. Host arms idle BEFORE USR is invoked.
    push af
    push bc
    push de
    push hl
    ld (BASIC_SP),sp
    di
    ld sp,STACK_TOP
    ld a,(0xea66)
    ld (OLD_PORT),a
    xor a
    ld (BOOT_RESULT),a
    call uart_init
    ld d,32
ready_again:
    ld hl,ready_text
    ld b,5
ready_byte:
    ld a,(hl)
    call uart_tx
    jp c,boot_failed
    inc hl
    djnz ready_byte
    call uart_rx
    jr c,ready_retry
    cp 0x47
    jr z,receive_image
    cp 0x54
    jr nz,ready_retry
    ld a,1
    ld (0xe807),a
    ld bc,256
    jr receive_common
ready_retry:
    ld a,0x37
    out (0x21),a
    in a,(0x20)
    dec d
    jr nz,ready_again
    jr boot_failed
receive_image:
    xor a
    ld (0xe807),a
    ld bc,STAGE1_SIZE
receive_common:
    ld hl,STAGE1
    ld de,0xffff
receive_byte:
    call uart_rx
    jr c,boot_failed
    ld (hl),a
    inc hl
    call crc_byte
    dec bc
    ld a,b
    or c
    jr nz,receive_byte
    call uart_rx
    jr c,boot_failed
    cp e
    jr nz,boot_failed
    call uart_rx
    jr c,boot_failed
    cp d
    jr nz,boot_failed
    ld a,(0xe807)
    or a
    jr z,send_ok
    ld hl,STAGE1
    ld bc,256
echo_pattern:
    ld a,(hl)
    call uart_tx
    jr c,boot_failed
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,echo_pattern
send_ok:
    ld a,0x4f
    call uart_tx
    jr c,boot_failed
    call uart_drain
    jr c,boot_failed
    ld a,(0xe807)
    or a
    jr nz,boot_return
    jp STAGE1
boot_failed:
    ld a,1
    ld (BOOT_RESULT),a
boot_return:
    xor a
    out (0x21),a
    ld a,(OLD_PORT)
    out (0x30),a
    ld sp,(BASIC_SP)
    pop hl
    pop de
    pop bc
    pop af
    ei
    ret
ready_text:
    db 0x5a,0x30,1
    dw STAGE1_SIZE
include "crc.inc"
include "uart.inc"
stage0_end:
