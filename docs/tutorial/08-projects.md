# 08 Small projects: combine the execution flow

[← Previous](07-bus.md) | [Contents](README.md) | [日本語](08-projects.ja.md) | [Reference](../reference/README.md)

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

### Goal

Count A from five to zero and HALT.

### Prerequisites and starter

Complete Chapters 02 and 04, then copy [the starter](starters/counter.asm).

### Expected behavior

A changes 5→4→3→2→1→0, Z becomes set at zero, the final JR is not taken, and the program HALTs.

### Verification

```console
zig build run -- asm counter.asm -o zig-out/counter.bin
zig build run -- disasm zig-out/counter.bin
zig build run -- test zig-out/counter.bin
```

In TUI, break on DEC and record A on each visit.

### Hint, solution, and extensions

Use `DEC A` followed by `JR NZ,loop`. Compare with the [solution](solutions/counter.asm). Extend it by loading the initial value from RAM `8000`, or by moving the counter to B.

## Exercise 2: Pixel painter

### Goal

Draw pixel `(10,9)`, then expand the program to three calculated VRAM bytes.

### Prerequisites and starter

Complete Chapters 03, 06, and 07, then copy [the starter](starters/pixel.asm).

### Expected behavior and verification

The first write is address `C08A`, bit 1, data `02`. Assemble and run with `--screen`, then Step in TUI and verify HL, Memory Write address/data, changed pixel, Inspector, and Source overlay.

### Hint, solution, and extensions

Use `C000 + (y/8)*128+x`. Compare with the [solution](solutions/pixel.asm). Add two pixels, then make a `draw_byte` subroutine using HL/A and initialize SP before CALL.

## Exercise 3: Pong

### Goal and prerequisites

After Chapters 04–07, understand and modify a continuously moving ball.

### Starter and solution

Use [`examples/pinpon.asm`](../../examples/pinpon.asm); it is both a working starter and the current autonomous solution.

### Expected behavior and verification

Run with `Ctrl+E`, switch to Display, and pause with Escape. The ball must bounce between fixed paddles without HALT. Inspect initialization, HL as ball address, B as distance counter, C as delay, RAM `8000` as direction, and CP/JR as direction selection. Verify direction changes in Memory and VRAM writes in Bus.

### Hints and extensions

Challenges: enter Game Input mode and reverse the ball with Left/Right, change pattern `18` to `3C`, alter delay, move the fixed paddles inward, and inspect only VRAM writes.

## Exercise 4: Game of Life

### Goal and prerequisites

After the Display and Branch chapters, trace one complete two-state blinker animation.

### Starter and solution

Use [`examples/game_of_life.asm`](../../examples/game_of_life.asm). It is a working pattern-animation solution, not a general Game of Life engine.

### Expected behavior and verification

The cells alternate vertical/horizontal indefinitely. Pause, Step one generation, and verify all writes in Bus and changed pixels in Display. The source alternates precomputed `38` and `10` patterns rather than counting neighbors.

### Hints and extensions

Challenges: move CENTER, shift the three bits, change outer delay B, then pause and record every write in one generation.

Delay loops do not imply a physical MHz rate. Apparent speed depends on host work, cooperative UI ticks, and rendering.

## IDE Tips

- Step normally; Run/Continue only for a whole loop.
- Combine Source breakpoints, Bus filters, and Display Inspector.
- Use the palette for Assemble, Views, and overlays; `Ctrl+E` resets and runs from the start.
- Save at small checkpoints and disassemble each generated ROM.

## Challenge: complete one vertical slice

Choose Counter or Pixel Painter and finish Goal through Verification without copying the solution first. Record one instruction as Source, PC, opcode bytes, register diff, Bus event, and visible/memory result.

## Usage-phase feedback

Record OS, terminal, Zig version, terminal size, goal, exact command/keys, expected behavior, actual behavior, minimal `.asm`, and which Source/CPU/Bus/Display relationship was unclear.

[← Previous](07-bus.md) | [Contents](README.md) | [Reference](../reference/README.md)
