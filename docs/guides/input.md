# Input Guide

[Index](README.md) | [日本語](input.ja.md)

The implemented input is one memory-mapped byte at `C400`: bits 0…6 are Up, Down, Left, Right, A, B, Start. Set it in the CLI debugger:

```text
input 0x11
memory 0xC400 1
```

Programs read it with `LD A,(0xC400)`. Multiple active buttons occupy multiple bits; isolate one with `AND` rather than comparing the entire byte.

Press `Ctrl+G` in TUI to enter Game Input mode. Arrows or lowercase WASD press directions, J/K press A/B, and Space presses Start. Uppercase WASD/J/K explicitly releases a held button; arrow presses expire after a short terminal repeat window because ordinary terminals do not report native key-up events. Escape releases every button and leaves the mode. Editor input is never changed while this mode is active. The status bar shows the current mask. `save input recording` writes `zig80-input.txt` from the Command Palette.

`zig80 run game.bin --input-script input.txt` performs deterministic headless replay. Each line is `<instruction-index> press|release <button>`, for example `0 press right`. Events use executed-instruction order, not wall-clock or fabricated Z80 timing.
