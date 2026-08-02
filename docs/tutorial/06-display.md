# 06 From VRAM to pixels: make an instruction visible

[← Previous](05-stack.md) | [Contents](README.md) | [日本語](06-display.ja.md) | [Next: Logic Analyzer →](07-bus.md)

## Panels to watch

- **Source** LD that writes VRAM
- **CPU** HL holding a VRAM address
- **Bus** Memory Write address and data
- **Display** dirty-pixel highlight
- **Pixel Inspector** x/y, address, bit, value, writer

## Goal

Follow one `CPU → Bus → VRAM → Display` operation and calculate a pixel's address, bit, and mask.

## How the Z80 works

The CPU only writes a byte to an address. The Machine's memory map makes that address VRAM, and the Display layout interprets its bits as pixels.

## Try it with the CLI

```console
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
```

## Observe it in the TUI

```console
zig build run -- tui examples/pixel.asm
```

```asm
ld hl,0xC000
ld (hl),0x01
halt
```

## Step 1: prepare the address

```text
Source       LD HL,C000
PC           0000→0003
Instruction  21 00 C0, length 3
CPU          HL 0000→C000
Bus          Opcode Fetch + two Operand Reads
VRAM/Display unchanged
Overlay      HL ← C000
```

The immediate is encoded `00 C0` because it is little endian.

## Step 2: write VRAM

```text
Source       LD (HL),01
PC           0003→0005
Bus          Memory Write: address C000, data 01
VRAM         C000 changes 00→01
Display      pixel (0,0) changes 0→1
Inspector    Addr C000, Bit 0, Value 1
Overlay      VRAM[C000] ← 01
```

```text
HL contains C000
       ↓
Bus carries address C000 and data 01
       ↓
VRAM byte C000 becomes 01
       ↓
bit 0 maps to pixel (0,0)
       ↓
Display highlights that pixel
```

## VRAM page layout

The Display is 128×64 at 1bpp. Each byte holds eight vertical pixels:

```text
address = C000 + (y / 8) * 128 + x
bit     = y % 8
mask    = 1 << bit
```

| Pixel | Address | Bit | Mask |
|---|---:|---:|---:|
| `(0,0)` | C000 | 0 | 01 |
| `(0,7)` | C000 | 7 | 80 |
| `(0,8)` | C080 | 0 | 01 |
| `(64,4)` | C040 | 4 | 10 |

Combining pixels uses a read-modify-write: `LD A,(HL)`, `OR mask`, then `LD (HL),A`. The bundled examples still write complete byte patterns to keep their display loop short. Clearing one selected bit would additionally need an inverted mask; the current expression syntax has no unary bitwise complement.

In Display (`Ctrl+5`), move the pixel cursor with arrows and inspect coordinate, VRAM address, bit, value, and last writer. The palette changes 1x/2x/4x scale and grid. Selecting a VRAM Write in Bus links the Inspector to its byte; this does not restore historical memory.

## IDE Tips

- `Ctrl+5`: Display; arrows: pixel cursor.
- Palette: scale and grid.
- Changed pixels last one frame; linked highlights last about 300 ms.
- The Display title marker indicates a recent VRAM update.
- Source's right margin shows observed execution, not a source comment.

## Challenge: pixel (10,9)

Calculate and then write it: address `C08A`, bit 1, mask `02`. Step the two LD instructions and verify Bus and Inspector values.

[← Previous](05-stack.md) | [Contents](README.md) | [Next →](07-bus.md)
