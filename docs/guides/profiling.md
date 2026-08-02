# Profiling Guide (planned)

[Index](README.md) | [日本語](profiling.ja.md)

Zig_80 does not currently provide a `profile` command. For now, use run totals, TUI instruction/T-state counters, and Trace Buffer metrics for coarse investigation. Do not interpret host elapsed time as Z80 performance.

The planned Profiler will aggregate instructions and T-states by address/label, calls, branch outcomes, memory/VRAM/I/O accesses, and hot loops. CLI-first APIs and accounting tests precede a possible TUI view. See Roadmap Phase 5.

