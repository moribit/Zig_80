# CLI Reference

[Index](README.md) | [日本語](cli.ja.md)

```text
zig80 asm <source.asm> -o <output.bin>
zig80 run <program.bin> [--max-instructions N] [--max-cycles N] [--screen]
zig80 debug <program.bin>
zig80 disasm <program.bin>
zig80 test <program.bin>
zig80 explain <source.asm>
zig80 tui [source.asm]
zig80 --help
```

All commands work headlessly except `tui`, which requires interactive stdin and stdout. `asm` writes a flat binary and prints symbols. `run` defaults to 1,000,000 instructions and 10,000,000 T-states. `test` succeeds only when the binary HALTs within 100,000 instructions. `disasm` renders unknown bytes as `DB`. `explain` assembles source and prints decoded output by address.

The existing CLI does not yet support projects, symbol files, input scripts, tracing, profiling, assets, machine selection, or directory test suites.

