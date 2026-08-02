# 08 Small projects: combine the execution flow

[← Previous](07-bus.md) | [Contents](README.md) | [日本語](08-projects.ja.md) | [Next: Reference →](09-reference.md)

## Panels to watch

- Keep **Source** primary.
- Use **CPU** for state, counters, and flags.
- Filter **Bus** to answer a specific read/write question.
- Treat **Display** as the program's result.
- Pause and use **Logic Analyzer** for one unclear instruction.

## Build in checkpoints

Start with HALT, load a register, write one RAM byte, write one VRAM byte, add a finite loop, add a subroutine and initialized SP, add a breakpoint, and only then replace HALT with a continuous main-loop jump.

```asm
org 0x0000
RAM   equ 0x8000
VRAM  equ 0xC000
INPUT equ 0xC400
start:
    ld sp,0xBFFF
main_loop:
    ; input → update → draw
    halt
    ; jp main_loop
```

## Exercise 1: Counter

Count A from five to zero and HALT. Observe A/Z after DEC, PC on taken/not-taken JR, and each iteration through a breakpoint. Extend it by loading the initial value from RAM `8000`.

## Exercise 2: Pixel painter

Write patterns to three calculated VRAM addresses. Check HL diffs, Memory Write address/data, changed pixels, Inspector, and Source overlay. Extend it with a `draw_byte` subroutine using HL and A.

## Exercise 3: Pong

Open [`examples/pinpon.asm`](../../examples/pinpon.asm), Run with `Ctrl+E`, switch to Display, then pause with Escape. Read initialization, HL as ball address, B as distance counter, C as delay, RAM `8000` as direction, and CP/JR as direction selection.

Challenges: change ball pattern `18` to `3C`, alter delay, move paddles inward, and inspect only VRAM writes. Paddles remain fixed because real-time game input is not implemented.

## Exercise 4: Game of Life

Open [`examples/game_of_life.asm`](../../examples/game_of_life.asm). It alternates precomputed vertical `38` and horizontal `10` patterns rather than implementing a general neighbor engine.

Challenges: move CENTER, shift the three bits, change outer delay B, then pause and record every write in one generation.

Delay loops do not imply a physical MHz rate. Apparent speed depends on host work, cooperative UI ticks, and rendering.

## IDE Tips

- Step normally; Run/Continue only for a whole loop.
- Combine Source breakpoints, Bus filters, and Display Inspector.
- Use the palette for Assemble, Views, and overlays; `Ctrl+E` resets and runs from the start.
- Save at small checkpoints and disassemble each generated ROM.

## Usage-phase feedback

Record OS, terminal, Zig version, terminal size, goal, exact command/keys, expected behavior, actual behavior, minimal `.asm`, and which Source/CPU/Bus/Display relationship was unclear.

[← Previous](07-bus.md) | [Contents](README.md) | [Next →](09-reference.md)
