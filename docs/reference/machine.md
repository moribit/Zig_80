# Default Machine Reference

[Index](README.md) | [日本語](machine.ja.md)

| Address | Purpose |
|---|---|
| `0000-7FFF` | program area |
| `8000-BFFF` | general RAM |
| `C000-C3FF` | 128×64 1bpp VRAM |
| `C400` | input bits |
| `C401-C402` | little-endian frame counter |
| `C403` | pseudo-random byte |
| `C404-FFFF` | reserved RAM |

Input bits 0…6 are Up, Down, Left, Right, A, B, Start. Pixel `(x,y)` is bit `y % 8` at `C000 + (y / 8) * 128 + x`. Programs are loaded at address zero and may be at most 32KB. The program range is not write-protected. The frame/random device model advances only when Machine `tickFrame` is explicitly called; it is not a real-time clock.

The map is currently fixed in Core constants. Named Machine Profiles and port I/O are not implemented.

