# Debugger Reference

[Index](README.md) | [日本語](debugger.ja.md)

The CLI debugger commands include `step/s`, `continue/c`, register/memory/disassembly inspection, `input`, `screen`, `reset`, and quit. Numeric arguments are decimal or hexadecimal with a lowercase `0x` prefix.

CLI Continue stops on HALT, a fixed address breakpoint, an error, or its internal one-million-instruction slice. TUI debugging uses the shared DebugSession for Step snapshots and its own cooperative execution loop.

Breakpoint syntax is `break [address] [if] <register-or-flag> <operator> <value> [hit N]`; omitting address uses current PC. `temporary` is also accepted. Use `delete`, `enable`, or `disable` with an address. Operators are `== != < <= > >=`; flags use `S/Z/H/PV/N/C == 0|1`.

Watchpoint syntax is `watch read|write <address[..end]> [if value <operator> N]`; `io-read` and `io-write` are accepted in preparation for port I/O. CLI and TUI use the same `DebugSession` breakpoint/watchpoint collections. Label resolution is part of the shared Symbol phase.
