# Zig_80 Development Roadmap

This roadmap separates implemented behavior from possible future work. It is a planning document, not a delivery commitment. Each phase should preserve the dependency-free Zig 0.16 implementation, existing CLI compatibility, headless operation, and the shared Core APIs used by CLI and TUI.

## Investigated baseline before this change (2026-08-02, main `45d6e0d`)

### CPU and assembler

- Implemented instructions: NOP, HALT, RET, JP (unconditional/Z/NZ), JR (unconditional/Z/NZ), CALL, PUSH/POP AF/BC/DE/HL, INC/DEC A/B/C/D/E/H/L/HL, ADD A with register/immediate, SUB and CP with register/immediate, immediate 8/16-bit LD, selected `(HL)` and absolute-memory LD forms.
- Assembly syntax: labels and forward references; `org`, `db`, `dw`, and `equ`; decimal, `0x` hexadecimal, `0b` binary, one-byte character literals, strings in `db`, current address `$`, and simple recursive `+`/`-` expressions.
- The two-pass assembler returns bytes, symbols, and source-line/address mappings. These are in-memory results; no stable symbol, source-map, listing, or map file format exists yet.
- Structured diagnostics retain severity, file, line, column, span, source line, and an optional hint. Assembly currently stops at the first error.

### Debugging and frontends

- CLI debugger: Step, Continue (up to an internal limit), register and memory inspection, disassembly, address breakpoints, breakpoint deletion, static input-register assignment, screen output, reset, and quit.
- TUI: source editing, assembly/reload, Step/Run/Continue/Pause, source-address breakpoints, CPU and Instruction cards, Memory view, Display view and Pixel Inspector, logical Bus event groups, filters, and a Logic Analyzer-style event-time view.
- Breakpoints are fixed addresses only. Labels, conditions, hit counts, enable/disable, temporary breakpoints, and watchpoints are not implemented.
- CLI and TUI use the same CPU, assembler, disassembler, Machine, and trace types. The TUI does not invoke CLI subprocesses.

### Machine, input, display, trace, and tests

- Machine: a fixed 64KB profile with program (`0000-7FFF`), RAM (`8000-BFFF`), VRAM (`C000-C3FF`), memory-mapped input (`C400`), frame counter (`C401-C402`), and pseudo-random byte (`C403`).
- Input: bit-defined Up/Down/Left/Right/A/B/Start state can be assigned by the CLI debugger. Real-time press/release, recording, replay, and headless scripts are not implemented.
- Display: 128×64 1bpp page layout, terminal rendering, TUI scale/grid, dirty-pixel highlight, update statistics, Pixel Inspector, and last observed writer.
- Trace: optional fixed-capacity logical events for opcode fetch, operand read, memory read/write, with reserved I/O/refresh/interrupt kinds. Events include instruction and within-instruction ordering. The waveform is explicitly not cycle-accurate.
- Test runner: unit tests exercise Core/TUI behavior; CLI `test` only checks that a binary reaches HALT within 100,000 instructions. Fixtures, assertions, snapshots, and golden files do not exist.

### Symbols and CLI/TUI gaps

- The assembler's symbol and source mappings already power generated Source gutters, PC/source synchronization, jump-to-definition, rename, and source breakpoints in the TUI.
- The CLI prints symbols after assembly but cannot save/load a symbol file. Disassembly, debugger breakpoints, and memory commands cannot resolve labels.
- The TUI has no Symbol Explorer or reference-results view. The CLI has no Logic Analyzer, while the TUI has no scripted input or stable machine-readable trace export.

### Documentation baseline before reorganization

- Tutorial: numbered bilingual chapters intended for sequential reading.
- TUI and Vision documents exist in English and Japanese.
- Dedicated Reference, task-oriented Guides, Architecture directory, terminology style guide, documentation integrity tests, and optional Web documentation plan are still to be established.

## Phase 1 — Core instruction and assembler expansion

### Objective

Make the current CPU useful for a broader class of programs while establishing shared metadata and synchronized CPU/assembler/disassembler behavior.

### In scope

- First increment: AND/OR/XOR register and immediate forms; general `LD r,r`, `LD r,(HL)`, and `LD (HL),r` forms.
- Later increments: ADC/SBC, INC/DEC `(HL)`, ADD HL pairs, DJNZ, CB-prefixed BIT/SET/RES and rotate/shift groups.
- Metadata sufficient to describe opcode family, size, T-states, operands, and flags for documentation and tests.
- CPU, assembler, disassembler, Explain, logical Trace, tests, and instruction Reference updated together.

### Out of scope

- Undocumented opcodes, IX/IY prefix substitutions, interrupts, and cycle-accurate bus timing.
- Completing every listed instruction in one change.

### Completion criteria

- Every implemented form has opcode, operand, size, T-state, flag, and edge-case tests.
- No assembler-emitted opcode is unknown to the CPU or disassembler.
- Existing binaries and CLI syntax remain compatible.

### Test method

- Table-driven CPU and flags tests, assembler byte assertions, disassembly text assertions, Trace event assertions, and end-to-end assemble/run programs.
- `zig fmt --check .`, `zig build`, and `zig build test` after each increment.

### Dependencies

- Existing registers, flags, Bus logical trace, two-pass assembler, and disassembler.
- Later CB work depends on prefix-aware decode and larger decoded-byte storage.

## Phase 2 — Input and debugging tools

### Objective

Support interactive games and reproducible debugging without coupling terminal input to the Machine.

### In scope

- A shared Input timeline/state API; explicit TUI Game Input mode (`Ctrl+G`, Escape to leave); press/release and simultaneous keys.
- Recording/replay and a deterministic headless input script.
- Label breakpoints, conditional expressions, hit counts, enable/disable, and temporary breakpoints.
- Read/write/range/value watchpoints, including VRAM and future I/O.

### Out of scope

- OS-global keyboard hooks, tutorial lesson logic, and time-travel state restoration.

### Completion criteria

- Editor input never mutates game input outside Game Input mode.
- The same input recording and DebugSession behavior works in CLI, TUI, and tests.
- Pinpon can be interactively controlled and replayed deterministically.

### Test method

- Terminal-free press/release/state tests, replay determinism, parser tests, breakpoint/watchpoint trigger matrices, and PTY terminal-restoration smoke tests.

### Dependencies

- A deterministic execution-time unit must be selected (instruction or logical tick, not fake wall-clock Z80 timing).
- Conditional breakpoints depend on a bounded expression evaluator or a deliberately smaller debug grammar.

## Phase 3 — Symbol and project support

### Objective

Turn assembler symbols and source mappings into a shared, serializable project-level service.

### In scope

- Stable Symbol/SourceMap Core types with label→address, address→label, address↔source lookup.
- Symbol, source-map, listing, and optional map output; CLI `--symbols` support; symbolized disassembly and label/address parsing.
- Relative `include` with source provenance, cycle detection, missing-file and included-file diagnostics; `incbin` after safe binary/source ownership is established.
- Symbol Explorer and shared jump/reference/rename foundations.
- A minimal project manifest and `zig80 build`, while preserving single-file commands.

### Out of scope

- A linker, object format, macro language, package registry, or complex build DSL.
- Full sections in the first increment; section metadata may precede placement/linking.

### Completion criteria

- CLI and TUI consume the same symbol/source-map implementation.
- Included-file diagnostics point to the included path and exact source location.
- Listing output round-trips the assembler's actual addresses and bytes.

### Test method

- Include tree/cycle/path fixtures, symbol serialization round trips, duplicate detection across files, listing golden tests, and CLI/TUI lookup tests.

### Dependencies

- File-aware assembly ownership and diagnostics; output formats should be versioned before project manifests depend on them.

## Phase 4 — I/O and machine profiles

### Objective

Represent machine differences explicitly and add Z80 port I/O without removing memory-mapped VRAM/input.

### In scope

- IN A,(n), OUT (n),A, an I/O Bus/peripheral interface, and logical `/IORQ` trace events.
- Initial status/input/display/UART/timer/debug port allocation as profiles require, not as unconditional devices.
- Dependency-free Machine Profile describing ranges, display, input, ports, nominal clock metadata, stack recommendation, and entry address.
- `--machine` in CLI/TUI/test and generated assembler constants.

### Out of scope

- Claiming cycle-accurate peripherals or enforcing real-time clock frequency.
- Replacing existing memory-mapped input and VRAM.

### Completion criteria

- Default profile preserves current binary behavior.
- CPU depends on a bus interface rather than concrete terminal/device implementations.
- Trace distinguishes memory and I/O reads/writes.

### Test method

- Port decode, peripheral isolation, profile validation, default-profile compatibility, and I/O trace signal tests.

### Dependencies

- Shared symbols for generated constants; profile schema must remain simple enough for Zig standard-library parsing.

## Phase 5 — Trace, profiler, and testing

### Objective

Make execution observable and verifiable in scripts and CI.

### In scope

- Trace filters, triggers, pause/bookmarks, save/load, JSON/CSV, and event-slot VCD with explicit logical-event metadata.
- Profiler counts by address/label, T-states, calls, branch outcomes, memory/VRAM/I/O access, loops, and optional frame boundaries.
- Test fixtures for initial/expected registers, flags, memory, Bus events, Display snapshots, input scripts, and stable exit codes.

### Out of scope

- Fabricated real-time VCD timestamps and cycle accuracy.
- A TUI Profiler view in the first increment; API and CLI output come first.

### Completion criteria

- Exports can be read back where applicable and identify event-slot time semantics.
- Profiler totals match CPU and trace totals.
- Fixture failures report exact expected/actual locations and return stable nonzero status.

### Test method

- Export golden/round-trip tests, filter/trigger matrices, profiler accounting invariants, and fixture pass/fail integration tests.

### Dependencies

- Symbol files and Machine Profiles; I/O counters depend on Phase 4.

## Phase 6 — Asset pipeline

### Objective

Convert dependency-free, simple source assets into machine-ready 1bpp data.

### In scope

- PBM, text bitmap, raw binary, and CSV inputs; 1bpp page/raw output; generated `db` include files; font/tile helpers.
- `incbin` integration after Phase 3.

### Out of scope

- PNG or other compressed image formats unless a small, maintainable standard-library-only implementation is justified later.
- Image editing or a general media framework.

### Completion criteria

- Deterministic output with validated dimensions and actionable diagnostics.
- Generated assets assemble and render in the default profile.

### Test method

- Tiny golden images, invalid-input matrices, page-layout checks, and end-to-end Display snapshots.

### Dependencies

- Machine Profile display metadata and assembler include support.

## Phase 7 — Documentation reorganization

### Objective

Keep sequential learning, lookup material, task guides, and internal design clearly separated while Markdown remains canonical.

### In scope

- `docs/tutorial`, `docs/reference`, `docs/guides`, and `docs/architecture` with bilingual indexes and navigation.
- Hardware basics and terminology style guides.
- Integrity tests for links, bilingual chapter parity, commands, key bindings, memory map, and instruction lists; generate from Core metadata where practical.
- An optional Web publication comparison/configuration that is never required to build Zig_80.

### Out of scope

- Tutorial Mode, quizzes, lesson progress, a custom tutorial DSL, or mandatory mdBook/MkDocs dependencies.

### Completion criteria

- Tutorial teaches Z80 programming and presents CLI/TUI as equal tools.
- Reference is authoritative and generated/checkable where possible.
- Guides are task-oriented and do not describe planned features as implemented.

### Test method

- Zig documentation integrity tests plus link and snippet checks; direct GitHub Markdown review.

### Dependencies

- Stable metadata and CLI/key/machine declarations improve generation. Documentation structure itself can start earlier.

## Phase 8 — Hardware-target preparation

### Objective

Define the boundary that could let one Machine specification and ROM target both the emulator and a future physical Z80 board.

### In scope

- Versioned Machine/ROM contract, firmware-facing Bus/peripheral interface, transfer/debug protocol concepts, and conformance tests.
- Investigation of a real Z80 with an RP2350-class MCU implementing the software chipset/firmware in Zig.

### Out of scope

- Claiming a PCB, firmware, USB debugger, electrical timing, or hardware support before it exists.
- Letting hardware-specific details enter the CPU Core.

### Completion criteria

- Emulator and prototype firmware can be tested against shared memory, I/O, display, input, and ROM conformance vectors.
- Electrical design has independent schematic, data-sheet, voltage-level, and timing review.

### Test method

- Machine contract vectors, protocol fuzz/round-trip tests, firmware simulation where possible, then explicitly documented physical measurements.

### Dependencies

- Machine Profiles, I/O abstraction, deterministic tests, and stable symbol/debug formats.

## Current implementation increment

Phase 1 is complete for the forms listed above: shared opcode-family helpers; AND/OR/XOR; general register and `(HL)` LD; ADC/SBC; INC/DEC `(HL)`; ADD HL pairs; DJNZ; and documented CB BIT/SET/RES/rotate/shift groups. CPU, assembler, disassembler, Explain, logical Trace, documentation, and exhaustive operand-matrix tests are synchronized. Undocumented SLL remains deliberately unsupported.

The Phase 7 documentation structure and integrity-test foundation were also established early because the implemented/planned boundary must remain visible. Phases 2–6 and 8 remain pending until their own completion criteria are met.
