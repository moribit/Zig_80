; PC-8001 ASCII chat terminal. Resident ABI: DI, private stack, RET.
; No ROM calls or display mode/attribute/UART configuration changes.
; uPD3301 cursor position only: 81h to port 51h, X/Y to 50h.
; Keyboard mapping: MAME src/mame/nec/pc88_kbd.cpp (original PC8001).
org 0xd000
PROMPT equ 0xd680
RX equ 0xd6c0
TX equ 0xd700
PREVIOUS equ 0xd730
KEYS equ 0xd760
ENTRY_SP equ 0xd770
STRIDE equ 0xd772
WIDTH equ 0xd773
COL equ 0xd774
ROW equ 0xd775
LENGTH equ 0xd776
TXSEQ equ 0xd777
RXSEQ equ 0xd778
RETRIES equ 0xd779
STATE equ 0xd77a
EXITING equ 0xd77b
TXLEN equ 0xd77c
LAST_STATUS equ 0xd77d
LAST_FAULT equ 0xd77e
CURSOR_POS equ 0xd780
VRTC_LAST equ 0xd782
ANIM_COUNT equ 0xd783
ANIM_PHASE equ 0xd784
POLL_LIMIT equ 0

    xor a
    ld hl,KEYS
    ld b,40
init_state:
    ld (hl),a
    inc hl
    djnz init_state
    ld (ENTRY_SP),sp
    ld hl,0xffff
    ld (CURSOR_POS),hl
    ld a,(0xea66)
    and 1
    ld c,a
    ld a,2
    sub c
    ld (STRIDE),a
    ld a,40
    dec c
    jr nz,width_ready
    ld a,80
width_ready:
    ld (WIDTH),a
    ld hl,0xf300
    ld b,25
clear_initial:
    call clear_row
    djnz clear_initial
    ld hl,title
    call puts
    call newline
    ld hl,waiting
    call puts
    ld a,2
    ld (ROW),a
    xor a
    ld (COL),a
    call cursor_update
    ld a,1
    ld (TX),a
    ld a,2
    ld (TX+3),a
    ld a,'C'
    ld (TX+4),a
    ld a,'1'
    ld (TX+5),a
    call reliable
chat_loop:
    call cursor_update
    call animate
    in a,(0x21)
    and 0x38
    jp nz,fault_exit
    in a,(0x21)
    and 2
    jr z,keyboard
    call receive
    jr c,chat_loop
    ld a,(RX)
    cp 7
    jr z,chat_loop
    call apply_frame
    jr chat_loop
keyboard:
keyboard_read:
    call key
    or a
    jr z,chat_loop
    push af
    ld bc,1500
key_debounce:
    dec bc
    ld a,b
    or c
    jr nz,key_debounce
    pop af
    ld b,a
    ld a,(STATE)
    cp 1
    jr nz,chat_loop
    ld a,b
    cp 13
    jr z,submit
    cp 8
    jr z,backspace
    ld a,(LENGTH)
    cp 64
    jr nc,chat_loop
    ld e,a
    ld d,0
    ld hl,PROMPT
    add hl,de
    ld (hl),b
    inc a
    ld (LENGTH),a
    ld a,b
    call putc
    jr chat_loop
backspace:
    ld a,(LENGTH)
    or a
    jr z,chat_loop
    dec a
    ld (LENGTH),a
    call erase
    jr chat_loop
submit:
    ld a,(LENGTH)
    or a
    jr z,chat_loop
    xor a
    ld (ANIM_COUNT),a
    ld (ANIM_PHASE),a
    ld hl,busy_text
    call status
    call newline
    ld hl,ai
    call puts
    ld a,2
    ld (STATE),a
    ld hl,PROMPT
    ld a,(LENGTH)
    ld c,a
prompt_chunk:
    push hl
    push bc
    ld a,3
    ld (TX),a
    ld b,31
    ld a,c
    cp 32
    jr nc,prompt_count
    ld b,c
prompt_count:
    ld a,b
    inc a
    ld (TX+3),a
    ld a,c
    sub b
    ld (LENGTH),a
    ld a,0
    jr nz,more_prompt
    inc a
more_prompt:
    ld (TX+4),a
    ld de,TX+5
copy_prompt:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz copy_prompt
    ex de,hl
    pop bc
    pop hl
    ld a,(TX+3)
    dec a
    ld e,a
    ld d,0
    add hl,de
    push hl
    call reliable
    pop hl
    ld a,(LENGTH)
    ld c,a
    or a
    jr nz,prompt_chunk
    jp chat_loop

; Validate version READY and frame sequence before mutating the screen.
apply_frame:
    ld a,(RX+1)
    ld b,a
    ld a,(RXSEQ)
    cp b
    jr z,new_frame
    dec a
    cp b
    ret nz
    ld a,(RX+2)
    add a,5
    ld b,a
    ld hl,RX
    ld de,PREVIOUS
compare_previous:
    ld a,(de)
    cp (hl)
    ret nz
    inc hl
    inc de
    djnz compare_previous
    jp send_ack
new_frame:
    ld a,(RX)
    cp 2
    jr z,ready_frame
    cp 4
    jr z,text_frame
    cp 5
    jp z,done_frame
    cp 6
    jp z,error_frame
    cp 8
    ret nz
    call remember_ack
    jp return_loader
ready_frame:
    ld a,(STATE)
    or a
    ret nz
    ld a,(RX+2)
    cp 2
    ret c
    ld a,(RX+3)
    cp 'C'
    ret nz
    ld a,(RX+4)
    cp '1'
    ret nz
    ld a,(RX+2)
    sub 2
    jr z,model_done
    cp 21
    ret nc
    ld (TXLEN),a
    ld b,a
    ld hl,RX+5
validate_model:
    ld a,(hl)
    cp 32
    ret c
    cp 127
    ret nc
    inc hl
    djnz validate_model
    ld a,(TXLEN)
    ld b,a
    ld hl,RX+5
    xor a
    ld (ROW),a
    ld a,20
    ld (COL),a
model_character:
    ld a,(hl)
    push hl
    push bc
    call putc
    pop bc
    pop hl
    inc hl
    djnz model_character
    ld a,2
    ld (ROW),a
    xor a
    ld (COL),a
model_done:
    call remember_ack
    jp new_question
text_frame:
    ld a,(STATE)
    cp 2
    ret nz
    ld a,(RX+2)
    ld b,a
    ld hl,RX+3
    or a
    jr z,remember_ack
validate_text:
    ld a,(hl)
    cp 10
    jr z,text_valid
    cp 32
    ret c
    cp 127
    ret nc
text_valid:
    inc hl
    djnz validate_text
    ld a,(RX+2)
    ld b,a
    ld hl,RX+3
display_text:
    ld a,(hl)
    push hl
    push bc
    call putc
    pop bc
    pop hl
    inc hl
    djnz display_text
    jr remember_ack
done_frame:
    ld a,(RX+2)
    or a
    ret nz
    call remember_ack
    jp new_question
error_frame:
    call remember_ack
    ld hl,error_text
    call puts
new_question:
    ld hl,ready_text
    call status
    call newline
    ld hl,you
    call puts
    ld a,1
    ld (STATE),a
    xor a
    ld (LENGTH),a
    ret
remember_ack:
    ld a,(RXSEQ)
    inc a
    ld (RXSEQ),a
    ld hl,RX
    ld de,PREVIOUS
    ld bc,37
    ldir
send_ack:
    ld a,(RX+1)
    ld hl,TX
    push hl
    ld hl,ack_buffer
    ld (hl),7
    inc hl
    ld (hl),a
    inc hl
    ld (hl),0
    dec hl
    dec hl
    call send_frame
    pop hl
    ret

; TX layout type,seq,reserved,len,payload; reserved permits simple scratch use.
reliable:
    ld a,(TXSEQ)
    ld (TX+1),a
    ld a,(TX+3)
    ld (TX+2),a
    ld hl,TX+4
    ld de,TX+3
    ld c,a
    ld b,0
    or a
    jr z,reliable_empty
    ldir
reliable_empty:
    ld a,3
    ld (RETRIES),a
retry_frame:
    ld hl,TX
    call send_frame
ack_wait:
    call receive
    jr c,retry_timeout
    ld a,(RX)
    cp 7
    jr nz,ack_wait
    ld a,(RX+2)
    or a
    jr nz,ack_wait
    ld a,(TXSEQ)
    ld b,a
    ld a,(RX+1)
    cp b
    jr nz,ack_wait
    ld a,b
    inc a
    ld (TXSEQ),a
    ret
retry_timeout:
    ld a,(RETRIES)
    dec a
    ld (RETRIES),a
    jr nz,retry_frame
    jp fault_exit
send_frame:
    push hl
    ld a,0xa5
    call tx_byte
    ld a,0x5a
    call tx_byte
    pop hl
    ld de,0xffff
    ld a,(hl)
    call send_crc
    inc hl
    ld a,(hl)
    call send_crc
    inc hl
    ld a,(hl)
    ld b,a
    call send_crc
    inc hl
    inc b
send_payload:
    dec b
    jr z,send_crc_end
    ld a,(hl)
    call send_crc
    inc hl
    jr send_payload
send_crc_end:
    ld a,e
    call tx_byte
    ld a,d
    call tx_byte
    ret
send_crc:
    push af
    call crc_byte
    pop af
    jp tx_byte
tx_byte:
    call uart_tx
    jp c,fault_exit
    ret
receive:
    call rx_byte
    ret c
    cp 0xa5
    jr nz,receive
sync_second:
    call rx_byte
    ret c
    cp 0xa5
    jr z,sync_second
    cp 0x5a
    jr nz,receive
    ld hl,RX
    ld de,0xffff
    ld b,3
receive_header:
    call rx_crc
    ret c
    djnz receive_header
    ld a,(RX+2)
    cp 33
    jr nc,bad_frame
    ld b,a
    or a
    jr z,receive_crc
receive_payload:
    call rx_crc
    ret c
    djnz receive_payload
receive_crc:
    call rx_byte
    ret c
    ld (hl),a
    inc hl
    cp e
    jr nz,bad_frame
    call rx_byte
    ret c
    ld (hl),a
    cp d
    jr nz,bad_frame
    or a
    ret
bad_frame:
    scf
    ret
rx_crc:
    call rx_byte
    ret c
    ld (hl),a
    inc hl
    call crc_byte
    or a
    ret
rx_byte:
    push af
    ld a,(EXITING)
    or a
    jr nz,rx_wait
    in a,(9)
    and 0x81
    cp 0x81
    jp nz,exit_chat
rx_wait:
    pop af
    jp uart_rx

exit_chat:
    ld sp,(ENTRY_SP)
    ld a,1
    ld (EXITING),a
    ld a,8
    ld (TX),a
    xor a
    ld (TX+3),a
    call reliable
return_loader:
    ld sp,(ENTRY_SP)
    call uart_drain
    ld a,0x43
    ret
fault_exit:
    ld sp,(ENTRY_SP)
    ld a,0x45
    ret

; Edge triggered active-low scanning, row 1..9. Letters normalize uppercase.
key:
    in a,(9)
    and 0x81
    cp 0x81
    jp nz,exit_chat
    ld hl,KEYS+1
    ld c,1
key_row:
    in a,(c)
    cpl
    ld e,a
    xor (hl)
    and e
    ld (hl),e
    or a
    jr nz,key_bits
key_next:
    inc hl
    inc c
    ld a,c
    cp 10
    jr nz,key_row
    xor a
    ret
key_bits:
    ld b,0
key_bit:
    rrca
    jr c,key_found
    inc b
    jr key_bit
key_found:
    ld a,c
    cp 1
    jr nz,key_letters
    ld a,b
    cp 7
    jr nz,key_next
    ld a,13
    ret
key_letters:
    cp 8
    jr c,key_table
    jr nz,key_space
    ld a,b
    cp 3
    jr nz,key_next
    ld a,8
    ret
key_space:
    ld a,b
    cp 6
    jr nz,key_next
    ld a,32
    ret
key_table:
    sub 2
    add a,a
    add a,a
    add a,a
    add a,b
    ld e,a
    ld d,0
    ld hl,key_plain
    in a,(8)
    and 0x40
    jr nz,key_lookup
    ld hl,key_shift
key_lookup:
    add hl,de
    ld a,(hl)
    ret

; Character-only VRAM operations leave all 1000 attribute bytes unchanged.
; CRTC columns use 80-byte character slots, so 40-column X is doubled.
cursor_update:
    ld a,(COL)
    ld l,a
    ld a,(ROW)
    ld h,a
    ld de,(CURSOR_POS)
    or a
    sbc hl,de
    ret z
    add hl,de
    ld (CURSOR_POS),hl
    ld a,0x81
    out (0x51),a
    ld a,(STRIDE)
    cp 2
    ld a,l
    jr nz,cursor_x
    add a,a
cursor_x:
    out (0x50),a
    ld a,h
    out (0x50),a
    ret
; One phase per eight VRTC rising edges. Never wait for retrace or UART.
animate:
    in a,(0x40)
    and 0x20
    ld b,a
    ld a,(VRTC_LAST)
    cp b
    ret z
    ld a,b
    ld (VRTC_LAST),a
    or a
    ret z
    ld a,(STATE)
    cp 2
    ret nz
    ld hl,ANIM_COUNT
    inc (hl)
    ld a,(hl)
    and 7
    ret nz
    ld a,(ANIM_PHASE)
    ld e,a
    inc a
    and 3
    ld (ANIM_PHASE),a
    ld d,0
    ld hl,spinner
    add hl,de
    ld b,(hl)
    ld hl,0xf382
    ld a,(STRIDE)
    dec a
    jr z,spinner_store
    ld hl,0xf38c
spinner_store:
    ld (hl),b
    ret
status:
    ld a,(ROW)
    push af
    ld a,(COL)
    push af
    xor a
    ld (COL),a
    inc a
    ld (ROW),a
    call puts
    pop af
    ld (COL),a
    pop af
    ld (ROW),a
    ret
puts:
    ld a,(hl)
    or a
    ret z
    push hl
    call putc
    pop hl
    inc hl
    jr puts
putc:
    cp 10
    jp z,newline
    push af
    call cell
    pop af
    ld (hl),a
    ld a,(COL)
    inc a
    ld (COL),a
    ld b,a
    ld a,(WIDTH)
    cp b
    ret nz
newline:
    xor a
    ld (COL),a
    ld a,(ROW)
    inc a
    cp 25
    jr z,scroll
    ld (ROW),a
    ret
scroll:
    ld hl,0xf468
    ld de,0xf3f0
    ld b,22
scroll_row:
    push bc
    ld bc,80
    ldir
    ld bc,40
    add hl,bc
    ex de,hl
    add hl,bc
    ex de,hl
    pop bc
    djnz scroll_row
    ld hl,0xfe40
    call clear_row
    ret
clear_row:
    push bc
    ld b,80
    ld a,32
clear_cells:
    ld (hl),a
    inc hl
    djnz clear_cells
    ld de,40
    add hl,de
    pop bc
    ret
cell:
    ld hl,0xf300
    ld de,120
    ld a,(ROW)
    or a
    jr z,cell_col
    ld b,a
cell_row:
    add hl,de
    djnz cell_row
cell_col:
    ld a,(COL)
    ld e,a
    ld d,0
    add hl,de
    ld a,(STRIDE)
    cp 2
    ret nz
    add hl,de
    ret
erase:
    ld a,(COL)
    or a
    jr nz,erase_col
    ld a,(ROW)
    dec a
    ld (ROW),a
    ld a,(WIDTH)
erase_col:
    dec a
    ld (COL),a
    call cell
    ld (hl),32
    ret

include "loader/crc.inc"
include "loader/uart.inc"
key_plain:
    db "@ABCDEFGHIJKLMNOPQRSTUVWXYZ[",0,"]^-0123456789",58,59,44,46,47,0
key_shift:
    db "@ABCDEFGHIJKLMNOPQRSTUVWXYZ{",0,"}^=0!",34,"#$%&'()*+<>?_"
title: db "ZIG_80 LOCAL AI CHAT",0
waiting: db "CONNECTING / ESC EXIT",0
ready_text: db "READY      / ESC EXIT",0
busy_text: db "RECEIVING  / ESC EXIT",0
you: db "YOU> ",0
ai: db "AI> ",0
error_text: db " [ERROR]",0
; ACK scratch is in application RAM, never resident state.
ack_buffer: db 7,0,0
spinner: db 124,47,45,92
chat_end:
