; PC-8001 ORBITAL RINGS: deterministic 64x64 semigraphics, 128 frames.
; Loader ABI: DI, private stack, RET; no ROM calls or peripheral writes.
; Preserves width/color/serial settings and restores every changed attribute.
; Scratch is D4E0-D4E5 and D500-D77F; image must end below D4E0.
org 0xd000
STRIDE equ 0xd4e0
FRAME_NO equ 0xd4e1
ANGLE equ 0xd4e2
CLEAR_VALUE equ 0xd4e3
GFX_ATTR equ 0xd4e4
TEXT_ATTR equ 0xd4e5
ATTR_BACKUP equ 0xd500
    ld a,(0xea66)
    and 1
    ld c,a
    ld a,2
    sub c
    ld (STRIDE),a
    ld a,(0xea66)
    and 2
    ld a,0x80
    ld c,0
    jr nz,attribute_mode_ready
    ld a,0xf8
    ld c,0xe8
attribute_mode_ready:
    ld (GFX_ATTR),a
    ld a,c
    ld (TEXT_ATTR),a
    xor a
    ld (FRAME_NO),a
    ld hl,title
    ld de,0xf300
    ld b,title_end-title
    call print_text
    ld hl,running
    ld de,0xfbe8
    ld b,running_end-running
    call print_text
    call save_attributes
    call enable_graphics
next_frame:
    xor a
    call clear_canvas
    xor a
    ld (ANGLE),a
draw_rings:
    ld a,(ANGLE)
    call sine_lookup
    ld b,a
    ld a,(FRAME_NO)
    ld hl,ANGLE
    add a,(hl)
    add a,16
    and 63
    call sine_lookup
    srl a
    add a,16
    ld c,a
    call pixel
    ld a,(ANGLE)
    call sine_lookup
    ld c,a
    ld a,(FRAME_NO)
    ld hl,ANGLE
    add a,(hl)
    add a,16
    and 63
    call sine_lookup
    srl a
    add a,16
    ld b,a
    call pixel
    ld a,(ANGLE)
    inc a
    ld (ANGLE),a
    cp 64
    jr nz,draw_rings
    ld b,32
    ld c,32
    call pixel
    ld bc,8000
frame_delay:
    dec bc
    ld a,b
    or c
    jr nz,frame_delay
    ld a,(FRAME_NO)
    inc a
    ld (FRAME_NO),a
    cp 128
    jr nz,next_frame
    ld a,32
    call clear_canvas
    call restore_attributes
    ld hl,finished
    ld de,0xfbe8
    ld b,finished_end-finished
    call print_text
    ld a,0x52
    ret

; A=index 0..63, result A; BC preserved.
sine_lookup:
    ld e,a
    ld d,0
    ld hl,sine_table
    add hl,de
    ld a,(hl)
    ret

; B=x, C=y in 0..63. BC preserved, other registers scratch.
pixel:
    ld a,c
    and 3
    ld e,a
    ld a,b
    and 1
    rlca
    rlca
    or e
    ld e,a
    ld d,0
    ld hl,pixel_masks
    add hl,de
    ld a,(hl)
    push af
    ld a,c
    srl a
    srl a
    add a,a
    ld e,a
    ld hl,row_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ld a,b
    srl a
    ld l,a
    ld h,0
    ld a,(STRIDE)
    cp 2
    jr nz,pixel_address
    add hl,hl
pixel_address:
    add hl,de
    pop af
    or (hl)
    ld (hl),a
    ret

; Clear only the 32 displayed character cells in each of 16 canvas rows.
clear_canvas:
    ld (CLEAR_VALUE),a
    ld hl,0xf3f0
    ld b,16
clear_row:
    push bc
    push hl
    ld a,(CLEAR_VALUE)
    ld d,a
    ld a,(STRIDE)
    ld c,a
    ld b,32
clear_cell:
    ld (hl),d
    inc hl
    bit 1,c
    jr z,clear_advance
    inc hl
clear_advance:
    djnz clear_cell
    pop hl
    ld de,120
    add hl,de
    pop bc
    djnz clear_row
    ret

save_attributes:
    ld hl,0xf440
    ld de,ATTR_BACKUP
    ld b,16
save_attribute_row:
    push bc
    ld bc,40
    ldir
    ld bc,80
    add hl,bc
    pop bc
    djnz save_attribute_row
    ret

enable_graphics:
    ld hl,0xf440
    ld b,16
enable_attribute_row:
    push bc
    push hl
    ld b,20
    ld a,(TEXT_ATTR)
    ld c,a
fill_attribute_pairs:
    ld (hl),80
    inc hl
    ld (hl),c
    inc hl
    djnz fill_attribute_pairs
    pop hl
    ld (hl),0
    inc hl
    ld a,(GFX_ATTR)
    ld (hl),a
    inc hl
    ld a,(STRIDE)
    add a,a
    add a,a
    add a,a
    add a,a
    add a,a
    ld (hl),a
    inc hl
    ld a,(TEXT_ATTR)
    ld (hl),a
    ld de,117
    add hl,de
    pop bc
    djnz enable_attribute_row
    ret

restore_attributes:
    ld hl,ATTR_BACKUP
    ld de,0xf440
    ld b,16
restore_attribute_row:
    push bc
    ld bc,40
    ldir
    ex de,hl
    ld bc,80
    add hl,bc
    ex de,hl
    pop bc
    djnz restore_attribute_row
    ret

print_text:
    ld a,(STRIDE)
    ld c,a
print_character:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    bit 1,c
    jr z,print_advance
    inc de
print_advance:
    djnz print_character
    ret

pixel_masks:
    db 1,2,4,8,16,32,64,128
row_table:
    dw 0xf3f0,0xf468,0xf4e0,0xf558,0xf5d0,0xf648,0xf6c0,0xf738
    dw 0xf7b0,0xf828,0xf8a0,0xf918,0xf990,0xfa08,0xfa80,0xfaf8
; round(32 + 30*sin(2*pi*i/64)), checked-in integer table, no runtime FP.
sine_table:
    db 32,35,38,41,43,46,49,51,53,55,57,58,60,61,61,62
    db 62,62,61,61,60,58,57,55,53,51,49,46,43,41,38,35
    db 32,29,26,23,21,18,15,13,11,9,7,6,4,3,3,2
    db 2,2,3,3,4,6,7,9,11,13,15,18,21,23,26,29
title:
    db "ZIG_80  ORBITAL RINGS"
title_end:
running:
    db "RUNNING - RETURNS TO LOADER"
running_end:
finished:
    db "COMPLETE - LOADER READY    "
finished_end:
demo_end:
