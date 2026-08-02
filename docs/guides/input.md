# Input Guide

[Index](README.md) | [日本語](input.ja.md)

The implemented input is one memory-mapped byte at `C400`: bits 0…6 are Up, Down, Left, Right, A, B, Start. Set it in the CLI debugger:

```text
input 0x11
memory 0xC400 1
```

Programs read it with `LD A,(0xC400)`. Multiple active buttons occupy multiple bits. There is no TUI Game Input mode, key-release model, recording/replay, or `--input-script` yet. Proposed syntax in the Roadmap is not accepted by the current CLI.

