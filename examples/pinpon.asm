; Pinpon: an autonomous bouncing-ball demo for the Zig_80 TUI.
;
; Open with:
;   zig build run -- tui examples/pinpon.asm
;
; In the TUI, press Ctrl+E to run, then switch to Display with Ctrl+5
; or the `display` command in Ctrl+P. Press Esc to pause.
;
; The current TUI has no real-time game-key input, so both paddles are
; fixed. The ball deliberately runs forever instead of executing HALT.

org 0x0000

VRAM equ 0xC000
DIRECTION equ 0x8000

start:
    ; Draw full-height paddles at the left and right edges of the first
    ; eight-pixel VRAM band.
    ld hl, VRAM
    ld (hl), 0xFF
    ld hl, VRAM + 127
    ld (hl), 0xFF

    ; Start the two-pixel ball near the center, moving right.
    ld hl, VRAM + 64
    ld b, 62
    ld a, 1
    ld (DIRECTION), a

game_loop:
    ld (hl), 0x18

    ; A visible delay keeps cooperative TUI execution responsive and makes
    ; the movement slow enough to observe in the Display pane.
    ld c, 0
delay:
    dec c
    jr nz, delay

    ld (hl), 0
    ld a, (DIRECTION)
    cp 0
    jr z, move_left

move_right:
    inc hl
    dec b
    jr nz, game_loop
    ld a, 0
    ld (DIRECTION), a
    ld b, 125
    jp game_loop

move_left:
    dec hl
    dec b
    jr nz, game_loop
    ld a, 1
    ld (DIRECTION), a
    ld b, 125
    jp game_loop
