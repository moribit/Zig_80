# Debugger Reference

[Index](README.md) | [日本語](debugger.ja.md)

The CLI debugger commands are `step/s`, `continue/c`, `registers/r`, `memory/m <address> <length>`, `disasm <address> <count>`, `break <address>`, `delete <address>`, `input <value>`, `screen`, `reset`, and `quit/q`. Numeric arguments are decimal or hexadecimal with a lowercase `0x` prefix.

CLI Continue stops on HALT, a fixed address breakpoint, an error, or its internal one-million-instruction slice. TUI debugging uses the shared DebugSession for Step snapshots and its own cooperative execution loop.

Only address breakpoints are implemented. Label, conditional, hit-count, enable/disable, temporary breakpoints, and read/write watchpoints are Roadmap work.

