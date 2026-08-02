# Core Boundaries

[Index](README.md) | [日本語](core.ja.md)

```text
Assembler ── bytes/symbols/source map ──┐
                                         ▼
CLI / TUI ── DebugSession ── Machine ── CPU
                              │
                              ├─ Bus / TraceSink
                              └─ Memory-mapped devices
```

- CPU implements instruction semantics and timing totals. It does not open files or draw UI.
- Bus owns the address space and emits optional logical events.
- Machine composes CPU, Bus, and device synchronization.
- Assembler produces bytes and source metadata without frontend behavior.
- Disassembler decodes bytes without executing them.
- DebugSession captures reusable execution state; frontend-specific policy remains outside Core.
- CLI and TUI call Core APIs directly. Neither frontend invokes the other.

Tutorial progress, quizzes, terminal keys, and hardware-specific electrical behavior must not enter CPU or Machine semantics.

