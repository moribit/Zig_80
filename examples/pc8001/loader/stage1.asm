include "layout.inc"
POLL_LIMIT equ 0
ACTIVE equ STATE
VERIFIED equ STATE+1
LOAD_ADDR equ STATE+2
IMAGE_SIZE equ STATE+4
ENTRY_ADDR equ STATE+6
IMAGE_CRC equ STATE+8
OFFSET equ STATE+10
EXPECTED_SEQ equ STATE+12
PREV_LEN equ STATE+13
REPLY_LEN equ STATE+14
BODY_LEN equ STATE+15
EXEC_PENDING equ STATE+16
VALUE equ STATE+17
IN_FRAME equ STATE+19
UART_ERRORS equ STATE+20
RX_TIMEOUTS equ STATE+22
BACKUP_LEN equ STATE+24
BACKUP equ 0xe850
org STAGE1
    jp main
    jp application_return ; ABI: D803 resets stack, UART and returns to command loop.
main:
    di
    ld sp,STACK_TOP
    xor a
    ld hl,STATE
    ld b,32
clear_state:
    ld (hl),a
    inc hl
    djnz clear_state
    call uart_init
seek_frame:
    xor a
    ld (IN_FRAME),a
    ld (EXEC_PENDING),a
    call uart_rx
    jp c,idle_fault
    cp 0xa5
    jr nz,seek_frame
    ld a,1
    ld (IN_FRAME),a
    call uart_rx
    jp c,frame_fault
    cp 0x5a
    jr nz,seek_frame
    ld hl,FRAME
    ld b,4
read_header:
    call uart_rx
    jp c,frame_fault
    ld (hl),a
    inc hl
    djnz read_header
    ld a,(FRAME+3)
    cp 65
    jp nc,bad_length
    add a,4
    ld (BODY_LEN),a
    sub 4
    or a
    jr z,read_crc
    ld b,a
read_payload:
    call uart_rx
    jp c,frame_fault
    ld (hl),a
    inc hl
    djnz read_payload
read_crc:
    ld hl,FRAME
    ld a,(BODY_LEN)
    ld c,a
    ld b,0
    call crc_range
    call uart_rx
    jp c,frame_fault
    cp e
    jp nz,bad_crc
    call uart_rx
    jp c,frame_fault
    cp d
    jp nz,bad_crc
    ld a,(FRAME)
    cp 1
    jp nz,bad_version
    ld a,(PREV_LEN)
    or a
    jr z,check_command
    ld b,a
    ld a,(FRAME+2)
    ld hl,PREVIOUS+2
    cp (hl)
    jr nz,check_command
    ld a,(BODY_LEN)
    cp b
    jp nz,bad_sequence
    ld hl,FRAME
    ld de,PREVIOUS
compare_previous:
    ld a,(de)
    cp (hl)
    jp nz,bad_sequence
    inc de
    inc hl
    djnz compare_previous
    call send_reply
    jp seek_frame ; Duplicate EXEC replays ACK and MUST NOT execute again.
check_command:
    ld a,(FRAME+1)
    cp 1
    jr z,hello
    ld a,(FRAME+2)
    ld hl,EXPECTED_SEQ
    cp (hl)
    jp nz,bad_sequence
    ld a,(FRAME+1)
    cp 2
    jp z,begin_image
    cp 3
    jp z,data_block
    cp 4
    jp z,verify_image
    cp 5
    jp z,execute_image
    cp 6
    jr z,abort_image
    cp 8
    jp z,echo_block
    cp 9
    jr z,info
    ld a,7
    jp reject
hello:
    ld a,(FRAME+3)
    or a
    jp nz,bad_length
    xor a
    ld (ACTIVE),a
    ld (VERIFIED),a
    ld hl,STAGE1
    ld bc,STAGE1_SIZE
    call crc_range
    ld (VALUE),de
    jp accept
info:
    ld a,(FRAME+3)
    or a
    jp nz,bad_length
    ld hl,(OFFSET)
    ld (VALUE),hl
    jp accept
abort_image:
    ld a,(FRAME+3)
    or a
    jp nz,bad_length
    xor a
    ld (ACTIVE),a
    ld (VERIFIED),a
    jp accept
begin_image:
    xor a
    ld (ACTIVE),a
    ld (VERIFIED),a
    ld a,(FRAME+3)
    cp 9
    jp nz,bad_length
    ld a,(FRAME+12)
    cp 2
    jp nc,bad_length
    ld hl,(FRAME+4)
    ld de,APP_MIN
    or a
    sbc hl,de
    jp c,bad_address
    ld hl,(FRAME+6)
    ld a,h
    or l
    jp z,bad_address
    ld de,(FRAME+4)
    add hl,de
    jp c,bad_address
    ld bc,APP_END
    or a
    sbc hl,bc
    jp c,check_entry
    jp nz,bad_address
check_entry:
    ld hl,(FRAME+8)
    or a
    sbc hl,de
    jp c,bad_address
    ld de,(FRAME+6)
    or a
    sbc hl,de
    jp nc,bad_address
    ld hl,(FRAME+4)
    ld (LOAD_ADDR),hl
    ld hl,(FRAME+6)
    ld (IMAGE_SIZE),hl
    ld hl,(FRAME+8)
    ld (ENTRY_ADDR),hl
    ld hl,(FRAME+10)
    ld (IMAGE_CRC),hl
    ld hl,0
    ld a,(FRAME+12)
    or a
    jr z,begin_offset
    ld hl,(IMAGE_SIZE) ; verify-only: CRC existing RAM, no DATA writes.
begin_offset:
    ld (OFFSET),hl
    ld (VALUE),hl
    ld a,1
    ld (ACTIVE),a
    call load_progress
    jp accept
data_block:
    ld a,(ACTIVE)
    or a
    jp z,bad_state
    ld a,(FRAME+3)
    or a
    jp z,bad_length
    ld c,a
    ld b,0
    ld hl,(OFFSET)
    add hl,bc
    ld de,(IMAGE_SIZE)
    push hl
    or a
    sbc hl,de
    pop hl
    jr c,data_in_range
    jp nz,bad_address
data_in_range:
    ld (VALUE),hl
    ld hl,(LOAD_ADDR)
    ld de,(OFFSET)
    add hl,de
    ex de,hl
    ld hl,FRAME+4
    ldir
    ld hl,(VALUE)
    ld (OFFSET),hl
    xor a
    ld (VERIFIED),a
    call load_progress
    jp accept
verify_image:
    ld a,(FRAME+3)
    or a
    jp nz,bad_length
    ld a,(ACTIVE)
    or a
    jp z,bad_state
    ld hl,(OFFSET)
    ld de,(IMAGE_SIZE)
    or a
    sbc hl,de
    jp nz,bad_state
    ld hl,(LOAD_ADDR)
    ld bc,(IMAGE_SIZE)
    call crc_range
    ld (VALUE),de
    ld hl,(IMAGE_CRC)
    or a
    sbc hl,de
    jp nz,bad_crc
    ld a,1
    ld (VERIFIED),a
    jp accept
execute_image:
    ld a,(FRAME+3)
    or a
    jp nz,bad_length
    ld a,(VERIFIED)
    or a
    jp z,bad_state
    ld a,(ACTIVE)
    or a
    jp z,bad_state
    ld a,1
    ld (EXEC_PENDING),a
    ld hl,(ENTRY_ADDR)
    ld (VALUE),hl
    jp accept
echo_block:
    ld a,(FRAME+3)
    ld (REPLY+5),a
    ld c,a
    ld b,0
    ld hl,FRAME+4
    ld de,REPLY+6
    or a
    jr z,echo_empty
    ldir
echo_empty:
    ld a,0x88
    ld (REPLY+3),a
    call finish_reply
    jr accepted_reply
accept:
    xor a
    call build_info
accepted_reply:
    ld a,(BODY_LEN)
    ld (PREV_LEN),a
    ld c,a
    ld b,0
    ld hl,FRAME
    ld de,PREVIOUS
    ldir
    ld a,(FRAME+2)
    inc a
    ld (EXPECTED_SEQ),a
    call send_reply
    jp c,frame_fault
    ld a,(EXEC_PENDING)
    or a
    jp z,seek_frame
    call uart_drain ; ACK must finish on the wire before application entry.
    jp c,frame_fault
    ld hl,(ENTRY_ADDR)
    ld de,application_return
    push de
    jp (hl)
application_return:
    di
    ld sp,STACK_TOP
    push af
    call uart_init
    pop af
    ld l,a
    ld h,0
    ld (VALUE),hl
    xor a
    ld (VERIFIED),a ; Application may have changed RAM. Require VERIFY again.
    call save_reply
    xor a
    call build_info
    ld a,0x82
    ld (REPLY+3),a
    call finish_reply
    call send_reply
    call uart_drain
    call restore_reply
    jp seek_frame
bad_crc:
    xor a
    ld (VERIFIED),a
    ld a,1
    jr reject
bad_version:
    ld a,2
    jr reject
bad_length:
    ld a,3
    jr reject
bad_address:
    ld a,4
    jr reject
bad_sequence:
    ld a,5
    jr reject
bad_state:
    ld a,6
reject:
    ; Preserve the successful cached reply during a NAK (duplicate ACK recovery).
    push af
    call save_reply
    pop af
    call build_info
    call send_reply
    call restore_reply
    jp seek_frame
save_reply:
    ld a,(REPLY_LEN)
    ld (BACKUP_LEN),a
    ld hl,REPLY
    ld de,BACKUP
    ld bc,80
    ldir
    ret
restore_reply:
    ld hl,BACKUP
    ld de,REPLY
    ld bc,80
    ldir
    ld a,(BACKUP_LEN)
    ld (REPLY_LEN),a
    ret
idle_fault:
    ld a,(LAST_FAULT)
    cp 1
    jp z,seek_frame ; Idle is not a transfer timeout.
frame_fault:
    xor a
    ld (VERIFIED),a
    ld a,(LAST_FAULT)
    cp 2
    ld hl,RX_TIMEOUTS
    jr nz,count_fault
    ld hl,UART_ERRORS
count_fault:
    inc (hl)
    jr nz,recover_uart
    inc hl
    inc (hl)
recover_uart:
    ld a,0x37
    out (0x21),a
    in a,(0x20)
    jp seek_frame
; build_info accepts status in A, value in VALUE. Payload length is always 16.
build_info:
    ld (REPLY+6),a
    or a
    ld a,0x80
    jr z,reply_type
    inc a
reply_type:
    ld (REPLY+3),a
    ld a,16
    ld (REPLY+5),a
    ld a,1
    ld (REPLY+7),a
    ld hl,APP_MIN
    ld (REPLY+8),hl
    ld hl,APP_END
    ld (REPLY+10),hl
    ld hl,(VALUE)
    ld (REPLY+12),hl
    ld a,(VERIFIED)
    add a,a
    ld hl,ACTIVE
    or (hl)
    ld (REPLY+14),a
    ld a,64
    ld (REPLY+15),a
    ld hl,(UART_ERRORS)
    ld (REPLY+16),hl
    ld hl,(RX_TIMEOUTS)
    ld (REPLY+18),hl
    ld a,(LAST_STATUS)
    ld (REPLY+20),a
    xor a
    ld (REPLY+21),a
finish_reply:
    ld hl,0x5aa5
    ld (REPLY),hl
    ld a,1
    ld (REPLY+2),a
    ld a,(FRAME+2)
    ld (REPLY+4),a
    ld a,(REPLY+5)
    add a,4
    ld c,a
    ld b,0
    ld hl,REPLY+2
    call crc_range
    ld (hl),e
    inc hl
    ld (hl),d
    ld a,(REPLY+5)
    add a,8
    ld (REPLY_LEN),a
    ret
send_reply:
    ld a,(REPLY_LEN)
    ld b,a
    ld hl,REPLY
send_reply_byte:
    ld a,(hl)
    call uart_tx
    ret c
    inc hl
    djnz send_reply_byte
    ret
crc_range:
    ld de,0xffff
crc_range_byte:
    ld a,(hl)
    inc hl
    call crc_byte
    dec bc
    ld a,b
    or c
    jr nz,crc_range_byte
    ret
; LOAD bar is RAM availability, not proof of whole-image CRC or execution.
; BEGIN/DATA only, after validation/write; retransmitted blocks never redraw.
; 16 cells = floor(OFFSET * 16 / IMAGE_SIZE), bounded by the validated 2KB.
; Character cells on visible row 19 only. No attribute, CRTC or UART changes.
load_progress:
    ld hl,(OFFSET)
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,(IMAGE_SIZE)
    ld b,0
progress_divide:
    or a
    sbc hl,de
    jr c,progress_counted
    inc b
    jr progress_divide
progress_counted:
    ld a,b
    push af
    ld bc,0x5001 ; 80 visible cells, stride 1.
    ld a,(0xea66)
    and 1
    jr nz,progress_width
    ld bc,0x2802 ; 40 visible cells, stride 2; skipped cells are preserved.
progress_width:
    ld de,0xfbe8
progress_clear:
    ld a,32
    call progress_put
    djnz progress_clear
    ld de,0xfbe8
    ld hl,progress_title
    ld b,6
progress_label:
    ld a,(hl)
    inc hl
    call progress_put
    djnz progress_label
    pop af
    ld h,a
    ld b,16
progress_bar:
    ld a,h
    or a
    ld a,46
    jr z,progress_cell
    dec h
    ld a,35
progress_cell:
    call progress_put
    djnz progress_bar
    ld a,93
progress_put:
    ld (de),a
    inc de
    bit 0,c
    ret nz
    inc de
    ret
progress_title:
    db "LOAD ["
include "crc.inc"
include "uart.inc"
stage1_end:
