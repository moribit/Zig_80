# Zig_80 Documentation Style Guide

[日本語](style-guide.ja.md)

## Terminology

Prefer one precise term for one concept: register, memory, instruction, address, flag, Stack, Bus, breakpoint, symbol, and Source Map. Preserve official UI names (`Source`, `CPU`, `Instruction`, `Logic Analyzer`) and format mnemonics, register names, signals, commands, paths, and keys as code where practical.

## Implementation status

- State implemented behavior directly.
- State current limits explicitly.
- Introduce future behavior with “planned,” “proposed,” “under consideration,” or “conceptual.”
- Never put an unimplemented CLI example next to implemented commands without a visible status label.
- Never call logical event-slot traces cycle-accurate, real-time, or electrical timing.

## Document roles

- Tutorial: sequential Z80 programming learning path
- Reference: authoritative current behavior
- Guides: task-oriented practice
- Architecture: boundaries, decisions, and future direction
- Roadmap: unimplemented increments and dependencies

Markdown is canonical and must remain readable directly on GitHub. Optional publishing tools must not become Zig_80 build dependencies.

