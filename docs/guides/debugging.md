# Debugging Workflow

[Index](README.md) | [日本語](debugging.ja.md)

Use the CLI for repeatable, line-oriented inspection and the TUI for correlated visual inspection.

1. Assemble and disassemble to validate bytes.
2. Step to the first wrong state.
3. Inspect register pairs and relevant RAM.
4. Add an address/source breakpoint before a loop.
5. Filter logical Bus events to the suspected read/write.
6. For VRAM, verify Pixel Inspector and writer instruction.
7. Reduce the program to a minimal ROM before reporting a tool issue.

Breakpoints support conditions, hit counts, temporary stops, and enable/disable. Watchpoints support logical read/write ranges and value conditions. Bus traces explain logical accesses, not physical timing.
