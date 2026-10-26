; Original PC-8001 mini invaders. Current width/color and serial preserved.
; Reads active-low keyboard ports 00,08,09. No ROM/CRTC calls.
; Cursor right / SHIFT+cursor right; keypad 4/6 aliases; SPACE fire/retry.
; ESC or STOP clears to text and RETs to the resident (A=49h).
; All code/tables below D700. State D700-D729 and D7E0-D7E5.
org 0xd000
PLAYER_X equ 0xd700
SHOT_ACTIVE equ 0xd701
SHOT_X equ 0xd702
SHOT_Y equ 0xd703
FLEET_X equ 0xd704
FLEET_Y equ 0xd705
FLEET_DIR equ 0xd706
TICK equ 0xd707
LIVES equ 0xd708
REMAINING equ 0xd709
ENEMY_SHOT equ 0xd70a
ENEMY_X equ 0xd70b
ENEMY_Y equ 0xd70c
SHOOT_INDEX equ 0xd70d
HIT_TIMER equ 0xd70e
GAME_MODE equ 0xd70f
RESTART_ARMED equ 0xd710
KEY8 equ 0xd711
KEY9 equ 0xd712
MOVE_FLAGS equ 0xd713
INDEX equ 0xd714
ALIVE equ 0xd720
STRIDE equ 0xd7e0
GFX_ATTR equ 0xd7e1
TEXT_ATTR equ 0xd7e2
SPRITE_X equ 0xd7e3
SPRITE_ROWS equ 0xd7e4

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
    jr nz,color_ready
    ld a,0xf8
    ld c,0xe8
color_ready:
    ld (GFX_ATTR),a
    ld a,c
    ld (TEXT_ATTR),a

reset_round:
    xor a
    ld hl,PLAYER_X
    ld b,32
reset_state:
    ld (hl),a
    inc hl
    djnz reset_state
    ld hl,ALIVE
    ld b,10
    ld a,1
reset_aliens:
    ld (hl),a
    inc hl
    djnz reset_aliens
    ld (FLEET_DIR),a
    ld a,36
    ld (PLAYER_X),a
    ld a,4
    ld (FLEET_X),a
    ld (FLEET_Y),a
    ld a,3
    ld (LIVES),a
    ld a,10
    ld (REMAINING),a
    call clear_screen
screen_cleared:
    call enable_graphics
    ld hl,cursor_help
    ld de,0xf378
    ld b,cursor_help_end-cursor_help
    call print_text
    ld hl,controls
    ld de,0xfbe8
    ld b,controls_end-controls
    call print_text

frame_loop:
    in a,(9)
    cpl
    ld (KEY9),a
    and 0x81
    jp nz,exit_game
    ld a,(GAME_MODE)
    or a
    jr z,playing
    ld a,(KEY9)
    and 0x40
    jr nz,restart_pressed
    ld a,1
    ld (RESTART_ARMED),a
    jp render
restart_pressed:
    ld a,(RESTART_ARMED)
    or a
    jp nz,reset_round
    jp render
playing:
    call read_movement
    ld a,(HIT_TIMER)
    or a
    jr z,shoot_player
    dec a
    ld (HIT_TIMER),a
shoot_player:
    ld a,(SHOT_ACTIVE)
    or a
    jr nz,advance_player_shot
    ld a,(KEY9)
    and 0x40
    jr z,advance_player_shot
    ld a,1
    ld (SHOT_ACTIVE),a
    ld a,(PLAYER_X)
    add a,3
    ld (SHOT_X),a
    ld a,55
    ld (SHOT_Y),a
advance_player_shot:
    call update_player_shot
    ld a,(GAME_MODE)
    or a
    jp nz,render
    call update_fleet
    ld a,(GAME_MODE)
    or a
    jp nz,render
    call update_enemy_shot
render:
    call clear_canvas
    call draw_enemies
    ld a,(HIT_TIMER)
    and 2
    jr nz,draw_projectiles
    ld a,(PLAYER_X)
    ld b,a
    ld c,57
    ld hl,ship_sprite
    call sprite
draw_projectiles:
    ld a,(SHOT_ACTIVE)
    or a
    jr z,draw_enemy_projectile
    ld a,(SHOT_X)
    ld b,a
    ld a,(SHOT_Y)
    ld c,a
    call pixel
    inc c
    call pixel
draw_enemy_projectile:
    ld a,(ENEMY_SHOT)
    or a
    jr z,draw_hud
    ld a,(ENEMY_X)
    ld b,a
    ld a,(ENEMY_Y)
    ld c,a
    call pixel
    inc c
    call pixel
draw_hud:
    call update_hud
    call update_status
    ld bc,4000
frame_delay:
    dec bc
    ld a,b
    or c
    jr nz,frame_delay
    ld a,(TICK)
    inc a
    ld (TICK),a
    jp frame_loop

read_movement:
    xor a
    ld (MOVE_FLAGS),a
    in a,(0)
    cpl
    and 0x50
    ld b,a
    bit 4,b
    jr z,keypad_right
    ld a,1
    ld (MOVE_FLAGS),a
keypad_right:
    bit 6,b
    jr z,cursor
    ld a,(MOVE_FLAGS)
    or 2
    ld (MOVE_FLAGS),a
cursor:
    in a,(8)
    cpl
    ld (KEY8),a
    bit 2,a
    jr z,move_ship
    bit 6,a
    ld a,1
    jr nz,cursor_flag
    ld a,2
cursor_flag:
    ld hl,MOVE_FLAGS
    or (hl)
    ld (hl),a
move_ship:
    ld a,(MOVE_FLAGS)
    cp 1
    jr z,move_left
    cp 2
    ret nz
    ld a,(PLAYER_X)
    add a,2
    cp 74
    jr c,store_player
    ld a,73
    jr store_player
move_left:
    ld a,(PLAYER_X)
    sub 2
    jr nc,store_player
    xor a
store_player:
    ld (PLAYER_X),a
    ret

update_player_shot:
    ld a,(SHOT_ACTIVE)
    or a
    ret z
    ld a,(SHOT_Y)
    sub 2
    jr c,clear_player_shot
    ld (SHOT_Y),a
    xor a
    ld (INDEX),a
shot_collision_loop:
    call alive_pointer
    ld a,(hl)
    or a
    jr z,shot_next_enemy
    ld a,(INDEX)
    call enemy_position
    ld a,(SHOT_Y)
    sub c
    cp 5
    jr nc,shot_next_enemy
    ld a,(SHOT_X)
    sub b
    cp 7
    jr nc,shot_next_enemy
    call alive_pointer
    xor a
    ld (hl),a
    ld (SHOT_ACTIVE),a
    ld hl,REMAINING
    dec (hl)
    ret nz
    ld a,1
    ld (GAME_MODE),a
    xor a
    ld (RESTART_ARMED),a
    ret
shot_next_enemy:
    ld a,(INDEX)
    inc a
    ld (INDEX),a
    cp 10
    jr nz,shot_collision_loop
    ret
clear_player_shot:
    xor a
    ld (SHOT_ACTIVE),a
    ret

update_fleet:
    ld a,(TICK)
    and 7
    ret nz
    ld a,(FLEET_DIR)
    or a
    jr z,fleet_left
    ld a,(FLEET_X)
    cp 24
    jr nc,fleet_descend
    inc a
    ld (FLEET_X),a
    ret
fleet_left:
    ld a,(FLEET_X)
    cp 2
    jr z,fleet_descend
    dec a
    ld (FLEET_X),a
    ret
fleet_descend:
    ld a,(FLEET_DIR)
    xor 1
    ld (FLEET_DIR),a
    ld a,(FLEET_Y)
    add a,2
    ld (FLEET_Y),a
    cp 42
    ret c
lose:
    ld a,2
    ld (GAME_MODE),a
    xor a
    ld (RESTART_ARMED),a
    ret

update_enemy_shot:
    ld a,(ENEMY_SHOT)
    or a
    jr nz,advance_enemy_shot
    ld a,(TICK)
    and 31
    ret nz
    ld b,10
find_shooter:
    ld a,(SHOOT_INDEX)
    ld (INDEX),a
    inc a
    cp 10
    jr c,save_shooter_index
    xor a
save_shooter_index:
    ld (SHOOT_INDEX),a
    call alive_pointer
    ld a,(hl)
    or a
    jr nz,spawn_enemy_shot
    djnz find_shooter
    ret
spawn_enemy_shot:
    ld a,(INDEX)
    call enemy_position
    ld a,b
    add a,3
    ld (ENEMY_X),a
    ld a,c
    add a,5
    ld (ENEMY_Y),a
    ld a,1
    ld (ENEMY_SHOT),a
    ret
advance_enemy_shot:
    ld a,(ENEMY_Y)
    inc a
    ld (ENEMY_Y),a
    cp 63
    jr nc,clear_enemy_shot
    cp 56
    ret c
    cp 62
    ret nc
    ld a,(HIT_TIMER)
    or a
    ret nz
    ld a,(ENEMY_X)
    ld hl,PLAYER_X
    sub (hl)
    cp 7
    ret nc
    xor a
    ld (ENEMY_SHOT),a
    ld (SHOT_ACTIVE),a
    ld a,24
    ld (HIT_TIMER),a
    ld a,36
    ld (PLAYER_X),a
    ld hl,LIVES
    dec (hl)
    ret nz
    jp lose
clear_enemy_shot:
    xor a
    ld (ENEMY_SHOT),a
    ret

alive_pointer:
    ld a,(INDEX)
    ld e,a
    ld d,0
    ld hl,ALIVE
    add hl,de
    ret

; A=index 0..9 -> B=x C=y.
enemy_position:
    ld b,a
    ld a,(FLEET_Y)
    ld c,a
    ld a,b
    cp 5
    jr c,enemy_column
    sub 5
    ld b,a
    ld a,c
    add a,10
    ld c,a
    ld a,b
enemy_column:
    add a,a
    ld b,a
    add a,a
    add a,b
    add a,a
    ld hl,FLEET_X
    add a,(hl)
    ld b,a
    ret

draw_enemies:
    xor a
    ld (INDEX),a
draw_enemy:
    call alive_pointer
    ld a,(hl)
    or a
    jr z,draw_next_enemy
    ld a,(INDEX)
    call enemy_position
    ld hl,alien_sprite
    ld a,(TICK)
    and 8
    jr z,draw_alien_sprite
    ld hl,alien_sprite_alt
draw_alien_sprite:
    call sprite
draw_next_enemy:
    ld a,(INDEX)
    inc a
    ld (INDEX),a
    cp 10
    jr nz,draw_enemy
    ret

; HL=5-row 7-bit sprite, B=x C=y. Pixel keeps BC; preserve DE/HL.
sprite:
    ld a,b
    ld (SPRITE_X),a
    ld a,5
    ld (SPRITE_ROWS),a
sprite_row:
    ld a,(hl)
    inc hl
    push hl
    ld e,a
    ld d,7
sprite_column:
    bit 6,e
    jr z,skip_sprite_pixel
    push de
    call pixel
    pop de
skip_sprite_pixel:
    sla e
    inc b
    dec d
    jr nz,sprite_column
    ld a,(SPRITE_X)
    ld b,a
    inc c
    pop hl
    ld a,(SPRITE_ROWS)
    dec a
    ld (SPRITE_ROWS),a
    jr nz,sprite_row
    ret

; Clipped 80x64 canvas, 2x4 pixels per displayed character.
pixel:
    ld a,b
    cp 80
    ret nc
    ld a,c
    cp 64
    ret nc
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

; Full 25x120-byte video area: fresh text cells AND clean attributes.
clear_screen:
    ld hl,0xf300
    ld b,25
clear_screen_row:
    push bc
    ld b,80
    ld a,32
clear_screen_character:
    ld (hl),a
    inc hl
    djnz clear_screen_character
    push hl
    ld a,(TEXT_ATTR)
    ld c,a
    ld b,20
clear_screen_attribute:
    ld (hl),80
    inc hl
    ld (hl),c
    inc hl
    djnz clear_screen_attribute
    pop de
    xor a
    ld (de),a
    inc de
    ld a,c
    ld (de),a
    pop bc
    djnz clear_screen_row
    ret

clear_canvas:
    ld hl,0xf3f0
    ld b,16
clear_canvas_row:
    push bc
    push hl
    ld a,(STRIDE)
    ld c,a
    ld b,40
    xor a
clear_canvas_character:
    ld (hl),a
    inc hl
    bit 1,c
    jr z,clear_canvas_advance
    inc hl
clear_canvas_advance:
    djnz clear_canvas_character
    pop hl
    ld de,120
    add hl,de
    pop bc
    djnz clear_canvas_row
    ret

enable_graphics:
    ld hl,0xf440
    ld b,16
graphics_row:
    ld (hl),0
    inc hl
    ld a,(GFX_ATTR)
    ld (hl),a
    inc hl
    ld a,(STRIDE)
    ld c,a
    add a,a
    add a,a
    add a,c
    add a,a
    add a,a
    add a,a
    ld (hl),a
    inc hl
    ld a,(TEXT_ATTR)
    ld (hl),a
    ld de,117
    add hl,de
    djnz graphics_row
    ret

print_text:
    ld a,(STRIDE)
    ld c,a
print_character:
    ld a,(hl)
    call put_character
    inc hl
    djnz print_character
    ret
put_character:
    ld (de),a
    inc de
    bit 1,c
    ret z
    inc de
    ret

update_hud:
    ld hl,hud
    ld de,0xf300
    ld b,hud_end-hud
    call print_text
    ld a,10
    ld hl,REMAINING
    sub (hl)
    cp 10
    ld b,48
    jr c,score_units
    sub 10
    inc b
score_units:
    push af
    ld a,b
    call put_character
    pop af
    add a,48
    call put_character
    ld hl,lives_text
    ld b,lives_end-lives_text
    call print_text
    ld a,(LIVES)
    add a,48
    call put_character
    ret

update_status:
    ld hl,playing_text
    ld b,playing_end-playing_text
    ld a,(GAME_MODE)
    or a
    jr z,status_text_ready
    dec a
    ld hl,win_text
    ld b,win_end-win_text
    jr z,status_text_ready
    ld hl,lose_text
    ld b,lose_end-lose_text
status_text_ready:
    ld de,0xfb70
    call print_text
    ret

exit_game:
    call clear_screen
    ld hl,exit_text
    ld de,0xf300
    ld b,exit_end-exit_text
    call print_text
    ld a,0x49
    ret

alien_sprite:
    db 28,62,107,127,34
alien_sprite_alt:
    db 28,62,107,127,65
ship_sprite:
    db 8,28,62,127,99
pixel_masks:
    db 1,2,4,8,16,32,64,128
row_table:
    dw 0xf3f0,0xf468,0xf4e0,0xf558,0xf5d0,0xf648,0xf6c0,0xf738
    dw 0xf7b0,0xf828,0xf8a0,0xf918,0xf990,0xfa08,0xfa80,0xfaf8
hud:
    db "INVADERS  SCORE "
hud_end:
lives_text:
    db "  LIVES "
lives_end:
controls:
    db "CURSOR L/R SPACE FIRE ESC EXIT"
controls_end:
cursor_help:
    db "LEFT SHIFT+RIGHT  KEYPAD 4/6"
cursor_help_end:
playing_text:
    db "CLEAR ALL 10 INVADERS            "
playing_end:
win_text:
    db "YOU WIN! SPACE RETRY ESC EXIT     "
win_end:
lose_text:
    db "GAME OVER SPACE RETRY ESC EXIT    "
lose_end:
exit_text:
    db "LOADER READY - INVADERS CLOSED"
exit_end:
game_end:
