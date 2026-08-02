# 03 Memory and addresses: store values outside the CPU

[← Previous](02-register.md) | [Contents](README.md) | [日本語](03-memory.ja.md) | [Next: Branches →](04-branch.md)

## Panels to watch

- **Source** parenthesized LD forms
- **CPU** HL as an address
- **Memory** bytes at an address
- **Bus** Memory Read and Memory Write

## Goal

Separate values from addresses, understand parentheses, inspect little-endian words, and read Zig_80's memory map.

## How the Z80 works

Memory is an address-indexed byte array outside the CPU. Parenthesized operands request a memory access. Z80 words place their low byte at the lower address.

```asm
ld hl,0x8000     ; put value 8000 in HL
ld (hl),0x2A     ; use HL as an address and write
ld a,(hl)        ; read from that address
halt
```

## Try it with the CLI

Save the program as `memory.asm`, then assemble it and use `memory 0x8000 2` in the debugger.

```console
zig build run -- asm memory.asm -o zig-out/memory.bin
zig build run -- debug zig-out/memory.bin
```

## Observe it in the TUI

```console
zig build run -- tui memory.asm
```

### Step through memory

```text
Step 1  HL 0000→8000; operand reads; memory unchanged
Step 2  Memory Write [8000]←2A; HL unchanged
Step 3  Memory Read [8000]=2A; A 00→2A
```

In Memory, press `g`, enter `8000`, and press Enter. Escape cancels address input.

For little endian:

```asm
ld hl,0x1234
ld (0x8000),hl
```

The second Step leaves byte `34` at `8000` and `12` at `8001`: the low byte occupies the lower address.

| Address | Purpose |
|---|---|
| `0000-7FFF` | program |
| `8000-BFFF` | general RAM |
| `C000-C3FF` | VRAM |
| `C400` | input |
| `C401-C402` | frame counter |
| `C403` | pseudo-random byte |
| `C404-FFFF` | reserved RAM |

This is Zig_80's map, not a universal Z80 map. The current program area is not write-protected.

## IDE Tips

- `Ctrl+3`: Memory view.
- Memory `g`: go to a four-digit hexadecimal address.
- Home/End in Memory: follow PC/HL.
- Filter the Bus to Memory Write for a concise trace.
- Step only the write and inspect the resulting cell.

## Challenge: change address and data

Write `7F` to `8010`. Predict HL, Bus address/data, the Memory cell, and whether Display changes (it should not; this is RAM).

[← Previous](02-register.md) | [Contents](README.md) | [Next →](04-branch.md)
