; Conway's Game of Life — blinker oscillator
;
; Run in the TUI:
;   zig build run -- tui examples/game_of_life.asm
;
; Then press Ctrl+E to run and Ctrl+5 to open the Display view.
; Press Esc to pause execution.
;
; The three live cells form a period-2 oscillator.  Each state below is an
; exact Conway generation: vertical, horizontal, vertical, and so on.  This
; compact example precomputes the two states instead of implementing a
; general-purpose neighbour-counting engine, keeping it compatible with the
; instructions currently supported by Zig_80.

        org 0x0000

VRAM equ 0xC000
CENTER equ 0xC040

start:
        ld sp,0xBFFF

generation_loop:
        ; Generation A: three vertical cells at x=64, y=3..5.
        ld hl,CENTER
        ld (hl),0x38
        call delay

        ; Clear generation A.
        ld (hl),0x00

        ; Generation B: three horizontal cells at x=63..65, y=4.
        ld hl,VRAM + 63
        ld (hl),0x10
        inc hl
        ld (hl),0x10
        inc hl
        ld (hl),0x10
        call delay

        ; Clear generation B before drawing the next generation.
        ld hl,VRAM + 63
        ld (hl),0x00
        inc hl
        ld (hl),0x00
        inc hl
        ld (hl),0x00
        jp generation_loop

; Slow the oscillator enough to observe it in the TUI.
delay:
        ld b,30
delay_outer:
        ld c,0
delay_inner:
        dec c
        jr nz,delay_inner
        dec b
        jr nz,delay_outer
        ret
