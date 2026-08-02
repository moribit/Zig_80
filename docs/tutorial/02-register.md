# 02 Registers and flags: inspect CPU state

[← Previous](01-cpu.md) | [Contents](README.md) | [日本語](02-register.ja.md) | [Next: Memory →](03-memory.md)

## Panels to watch

- **Source** LD, ADD, SUB, and CP
- **CPU** AF, BC, DE, HL, and flags
- **Instruction** affected flags

## Goal

Distinguish 8-bit registers from 16-bit pairs, read register diffs, and use Z and C to describe results.

## How the Z80 works

Registers hold values inside the CPU. Arithmetic writes documented properties of its result into F so that later conditional instructions can act on them.

## Try it with the CLI

```console
zig build run -- asm examples/add.asm -o zig-out/add.bin
zig build run -- debug zig-out/add.bin
```

Use `step` and `registers` at the debugger prompt.

## Observe it in the TUI

```console
zig build run -- tui examples/add.asm
```

| Register | First mental model |
|---|---|
| A | accumulator for arithmetic and comparisons |
| F | flag byte, paired with A as AF |
| B/C, D/E | temporary values and pairs BC/DE |
| H/L | pair HL, commonly used as an address |
| PC / SP | next instruction / Stack top |

In the TUI, Step three times:

```text
LD A,10   AF 0000 → 0A00
LD B,20   BC 0000 → 1400
ADD A,B   AF 0A00 → 1E00 (including updated F)
```

Try a zero result:

```asm
ld a,1
sub 1
cp 0
halt
```

After SUB, A is zero and Z=1; N identifies subtraction. CP keeps A unchanged and updates flags as if it had subtracted its operand.

| Flag | Meaning |
|---|---|
| S | sign bit |
| Z | zero result |
| H | carry/borrow across bit 3 |
| PV | parity or signed overflow |
| N | subtraction-type operation |
| C | carry/borrow outside the value width |

Begin with Z and C. INC/DEC preserve C in the current implementation.

## IDE Tips

- Changed pairs briefly show old value `↓` new value.
- `Ctrl+2` opens the CPU view.
- Use `Ctrl+T` only after predicting the next diff.
- `Ctrl+Z` / `Ctrl+Y` undo/redo source; `Ctrl+F` searches it.

## Challenge: wrap an 8-bit value

Load A with 255 and B with one, then ADD A,B. Predict A, Z, and C before stepping. `FF + 01` wraps within A's eight bits.

[← Previous](01-cpu.md) | [Contents](README.md) | [Next →](03-memory.md)
