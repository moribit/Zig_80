# Zig_80 IDE Tutorial

[日本語](README.ja.md)

This course is for modern programmers who are new to the Z80, assembly language, and CPU hardware. It uses the Zig_80 IDE as a learning instrument rather than presenting an assembler reference to memorize.

## How to use the course

Every chapter follows the same rhythm:

1. narrow your attention with “Panels to watch”;
2. open a small example in the TUI;
3. execute one instruction with `Ctrl+T`;
4. follow `PC → Instruction → CPU → Bus → Display`;
5. learn one IDE operation; and
6. finish a challenge that takes only a few minutes.

You do not need to understand every pane at once. At first, follow the `▶` current-PC marker and the values briefly highlighted after a Step.

## Contents

| Chapter | Topic | Main panels |
|---|---|---|
| [00 Introduction](00-introduction.md) | setup, IDE map, learning workflow | Source, CPU, Instruction |
| [01 CPU and instructions](01-cpu.md) | machine code, PC, fetch/decode/execute | Source, Instruction, Bus |
| [02 Registers and flags](02-register.md) | LD, ADD, registers, Z/C flags | Source, CPU |
| [03 Memory and addresses](03-memory.md) | RAM, parentheses, little endian, memory map | Source, CPU, Memory, Bus |
| [04 Branches and loops](04-branch.md) | CP, DEC, JR, JP, breakpoints | Source, CPU, Bus |
| [05 Subroutines and Stack](05-stack.md) | CALL, RET, SP, PUSH/POP | Source, CPU, Memory |
| [06 From VRAM to pixels](06-display.md) | CPU→Bus→VRAM→Display and Inspector | Source, Bus, Display |
| [07 Logic Analyzer](07-bus.md) | fetches, operands, writes, address/data/events | Bus, Logic Analyzer |
| [08 Small projects](08-projects.md) | Counter, Pixel, Pong, Game of Life | all panes |
| [09 Reference](09-reference.md) | CLI, syntax, supported instructions, diagnostics | consult as needed |

```text
Source instruction ── assemble ──> machine-code bytes
       │                                  │ fetch/execute
       └──────────────────────────────> CPU state
                                          │ logical access
                                          ▼
                                  Bus ── RAM / VRAM ── Display
```

[Next: 00 Introduction →](00-introduction.md)

