# Game Development Guide

[Index](README.md) | [日本語](game-development.ja.md)

Start with a deterministic state update, one VRAM-byte draw, and HALT. Inspect it with Step before introducing a continuous loop.

```asm
org 0
STATE equ 0x8000
VRAM equ 0xC000
start:
    ld sp,0xBFFF
    ld a,1
    ld (STATE),a
loop:
    ld hl,VRAM + 64
    ld (hl),0x18
    halt
    ; jp loop
```

Use general RAM for game state, HL for a current address, counters for finite loops, and complete VRAM byte patterns because bitwise read-modify-write support remains limited. Assemble, disassemble, Step, verify memory/display, and only then replace HALT with JP.

Pinpon demonstrates a continuous autonomous loop; Game of Life demonstrates alternating display patterns. Real-time input and project manifests are not implemented yet.

