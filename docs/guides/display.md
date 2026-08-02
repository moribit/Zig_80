# Display Programming Guide

[Index](README.md) | [日本語](display.ja.md)

The default Display is 128×64, 1bpp, with eight vertical pixels per VRAM byte.

```text
address = C000 + (y / 8) * 128 + x
bit     = y % 8
mask    = 1 << bit
```

Develop a draw operation by calculating the byte, writing it, selecting the Memory Write event, and confirming coordinate/address/bit/value in Pixel Inspector. Palette commands change scale and grid but never alter VRAM layout. Dirty highlights identify recent writes.

Current output is the fixed 1bpp profile. Sprite, Tile, LCD, SSD1306, and alternate Display implementations are future profile/asset work.

