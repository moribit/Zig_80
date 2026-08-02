# 00 Introduction: use the IDE as a learning instrument

[Contents](README.md) | [日本語](00-introduction.ja.md) | [Next: CPU and instructions →](01-cpu.md)

## Panels to watch

- **Source**: assembly and current PC
- **CPU**: PC and execution state
- **Instruction**: address, opcode, length, and timing
- Ignore the detailed Bus, Analyzer, and Display views for now

## Goal

Build Zig_80, find the next instruction on screen, and execute exactly one instruction rather than running the whole program.

## Set up

Use macOS or Linux, Zig 0.16.x, and an ANSI/VT100-compatible terminal. An 80×24 terminal is recommended.

```console
zig version
zig build
zig build test
zig build run -- --help
zig build run -- tui examples/halt.asm
```

Find the Source `▶`, CPU `PC 0000`, Instruction `HALT`, and `[ASSEMBLED]` status badge. Source markers are independent:

| Marker | Meaning |
|---|---|
| `┃` | editing cursor |
| `▶` | next CPU instruction |
| `▲` | last executed instruction |
| `●` | breakpoint |
| `!` | diagnostic |

## Your first Step

Press `Ctrl+T` once.

```text
Source       HALT becomes last executed
PC           0000 → 0001
Instruction  HALT, opcode 76, length 1
CPU          HALTED
Bus          Opcode Fetch event
Display      unchanged
```

The CPU fetched byte `76` from address `0000`, decoded it as HALT, advanced PC by one byte, and halted. A byte is eight bits (`00`…`FF`); a 16-bit Z80 address is `0000`…`FFFF`, selecting 65,536 bytes.

## IDE Tips

- `Ctrl+T`: step one instruction—the course's primary action.
- `Ctrl+1` / `Ctrl+2`: Source / CPU view.
- `Ctrl+P`: open the Command Palette and select `step` if you forget a key.
- `Ctrl+Q`: quit; press it twice if source is unsaved.

## Challenge: add NOP

Insert `nop` before `halt`, press `Ctrl+R`, reset, and Step twice. Predict PC after each instruction. NOP changes no data, but still fetches an opcode and advances PC.

[Contents](README.md) | [Next →](01-cpu.md)

