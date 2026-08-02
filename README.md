# Zig_80

[日本語](README.ja.md)

Zig_80 is a dependency-free CLI environment for learning about the Z80 by observing instructions, registers, flags, and memory. The current MVP targets Zig 0.16 and combines assembly, execution, disassembly, debugging, and 1bpp display output in a single binary.

For the project's principles, long-term direction, and possible path toward physical hardware, see [Vision and Architectural Direction](docs/vision.md). The future described there remains conceptual and is not a delivery commitment.

New to the Z80, assembly language, or CPU hardware? Start with the comprehensive [Zig_80 Tutorial](docs/tutorial.md), which builds from a one-instruction ROM to debugging registers, memory, branches, the Stack, logical Bus events, input, and the 1bpp Display.

## Build and quick start

```console
zig build
zig build test
zig build run -- --help
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- disasm zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
zig build run -- debug zig-out/pixel.bin
zig build run -- test zig-out/pixel.bin
```

## Terminal UI

Open the dependency-free terminal frontend with an optional assembly source:

```console
zig build run -- tui examples/pixel.asm
```

For a program that does not immediately HALT, open the autonomous Pinpon demo:

```console
zig build run -- tui examples/pinpon.asm
```

Press `Ctrl+E` to run, then use `Ctrl+5` or the Command Palette's `display` action to watch the ball bounce between fixed paddles. Press Escape to pause. The demo intentionally loops forever; TUI execution limits still provide a safety stop.

The source-first TUI gives the editor roughly 70% of the normal layout, then relates subdued source addresses and bytes, current PC, grouped CPU and Instruction cards, and logical Bus accesses. Its quiet header contains only file state; pane focus changes context help on the badge-style status bar. Ctrl+P opens the command-centered palette, with no Function-key bindings. The Bus view places an instruction card beside an equal-width logical waveform. The waveform is not cycle-accurate. See [TUI Guide](docs/tui.md) for details.

The Display view presents the 128×64 1bpp output as a game screen with 1x, 2x, and 4x scales (2x by default), optional grid, pixel inspection, update count, changed-pixel count, and display-update FPS. Stepping links the observed source result, register before/after values, logical Bus accesses, and changed VRAM pixels; Bus selection also links its instruction PC and captured CPU state. Display scale/grid and Bus filters are available from `Ctrl+P`.

The Logic Analyzer uses high/low traces with explicit rising and falling edges, a vertical time cursor, 1x/2x/4x/Fit zoom, and independent pan. Its time axis remains logical event order and is explicitly not cycle-accurate.

The Source pane is Z80-aware rather than a general text editor: cached syntax tokens drive contextual mnemonic, register, directive, operand, and source-label completion; it also provides indentation, selection, Undo/Redo, incremental search, label navigation and rename, inline diagnostics and bytes, and short-lived overlays of actual Step results.

TUI Run and Continue stop at default totals of 10,000,000 instructions or 100,000,000 T-states. Reset clears both totals; an explicit Step remains available after a limit stop.

Execution always has default instruction and T-state limits. Use `--max-instructions N` and `--max-cycles N` with `run` to change them. `--screen` renders the display when execution stops.

## Commands

- `asm source.asm -o program.bin`: assemble in two passes and print the generated binary and symbol list
- `run program.bin`: execute until HALT or a configured limit
- `disasm program.bin`: show addresses, encoded bytes, and instructions; unknown opcodes appear as `DB`
- `debug program.bin`: start the line-oriented REPL; enter `help` for its commands
- `test program.bin`: perform a basic check that the program reaches HALT within 100,000 instructions
- `explain source.asm`: show a concise view of each encoded instruction

The debugger supports `step/s`, `continue/c`, `registers/r`, `memory/m`, `disasm`, `break`, `delete`, `input`, `screen`, `reset`, and `quit/q`. An input register value can be assigned directly with a command such as `input 0x11`.

## Virtual machine

| Address | Purpose |
|---|---|
| `0000-7FFF` | program area |
| `8000-BFFF` | general RAM |
| `C000-C3FF` | video RAM |
| `C400` | input state |
| `C401-C402` | frame counter, little endian |
| `C403` | pseudo-random value |
| `C404-FFFF` | reserved RAM |

The display is 128×64 at 1bpp. Bit `y % 8` at `C000 + (y / 8) * 128 + x` represents one pixel, using a page layout similar to the SSD1306. The terminal renderer combines two vertical pixels into one Unicode block character. Input bits 0 through 7 represent Up, Down, Left, Right, A, B, Start, and Reserved.

## Assembly syntax

The assembler supports labels, forward references, `;` comments, decimal (`42`), hexadecimal (`0x2A`), binary (`0b101010`), characters (`'A'`), the current address (`$`), and simple `+`/`-` expressions. Its directives are `org`, `db`, `dw`, and `equ`; strings can be emitted with syntax such as `db "HELLO", 0`. `org` changes the logical address and does not add padding to the output file.

Supported instructions are NOP, HALT, JP, conditional JP (Z/NZ), JR, conditional JR (Z/NZ), CALL, RET, the MVP's 8-bit and 16-bit LD forms, INC/DEC, ADD A, SUB, CP, and PUSH/POP for AF/BC/DE/HL. Arithmetic updates S/Z/H/PV/N/C as applicable, while INC/DEC preserve C.

## Architecture

- CPU: fetch → decode → execute → update registers/flags → return T-states in `StepResult`. It does not depend on files or terminal I/O.
- Bus: provides 8-bit and 16-bit access to a 64KB address space and a boundary for future I/O. Words are little endian and wrap from `FFFF` to `0000`.
- Machine: integrates the CPU, Bus, memory map, VRAM, input, frame counter, and pseudo-random register.
- Frontend: contains the CLI, screen renderer, disassembler, and REPL debugger.

Assembler Pass 1 parses lines, calculates addresses, and collects symbols. Pass 2 resolves those symbols, encodes instructions, and produces bytes and source-line mappings.

New instructions currently require corresponding additions to the CPU opcode family, assembler encoder, and disassembler. Shared metadata for fixed instructions lives in `src/cpu/instruction.zig` and is an integration point for future expansion. New peripherals should extend reserved Bus addresses and Machine synchronization without introducing device dependencies into the CPU.

## Current limitations and roadmap

The MVP does not support the complete Z80 instruction set, CB/DD/ED/FD prefixes, IX/IY, interrupts, I/O instructions, cycle-accurate behavior, real-time input, watchpoints, time travel, UART/PSG/SD devices, Wasm, GDB, or LSP. The ROM range is not currently write-protected. Bus Trace represents logical instruction-level accesses and is not a reproduction of electrical or per-T-state Z80 timing. The CLI `test` command only checks HALT; detailed register and memory assertions can be written through the Zig unit-test API around `Machine`.

Likely next areas include broader shared instruction metadata, a detailed program-test format, watchpoints, non-blocking real-time input, and CB-prefixed instructions.
