# Zig_80: Vision and Architectural Direction

[日本語版](vision.ja.md)

## Status of this document

This document describes the long-term direction of Zig_80 and the design principles behind it. It is not an implementation specification, a committed delivery plan, or a compatibility guarantee.

Many ideas presented here remain conceptual. The design is still evolving and may change as technical assumptions are tested and the project matures.

## Purpose

Zig_80 aims to become an integrated environment for learning about the Z80, developing programs for it through the modern Zig toolchain, and eventually deploying those programs to physical hardware.

The project is neither merely a Z80 emulator nor merely an assembler. Its central concern is a continuous experience around one Z80 program: writing it, translating it, running it, observing it, and delivering it to hardware. One direction under consideration is to connect software and hardware through a shared Machine contract rather than treating them as separate subjects.

The project also values understanding how each layer works. The intended audience should be able to begin with instructions and registers, then gradually explore emulation, toolchains, peripherals, and hardware.

## Why Z80

The Z80 is a historic processor that appeared in personal computers, game systems, and embedded devices. Studying it provides a direct route into concepts that continue to shape modern computers.

Compared with a contemporary processor, it exposes a manageable amount of state. Fetch, decode, execution, flags, memory, and the stack can be observed relatively directly. Although the complete instruction set has its own complexity, learning can begin with a small subset and expand incrementally.

Recreating the Z80 is also a useful emulator exercise. Registers, address spaces, stacks, interrupts, and execution timing can be investigated in small units. Physical Z80 processors remain obtainable, and experiments can begin with comparatively simple supporting circuitry. This creates a plausible path from software understanding to self-built hardware.

Zig_80 therefore treats the Z80 not only as a preserved historical processor, but as a shared language for making fundamental computer architecture visible.

## Why Zig

Zig may allow host development tools and embedded software to be expressed with closely related principles.

- Cross-compilation is central to the language and toolchain, which suits a possible progression from host CLI tools to microcontroller targets.
- Explicit memory management helps communicate ownership and lifetime in an emulator built around fixed CPU and memory state.
- Minimal implicit runtime requirements make embedded firmware a possible future target.
- `comptime` may help validate instruction descriptions and other static data, provided it remains balanced with readability for learners.
- Zig is well suited to constructing self-contained CLI tools for assembly, execution, and analysis.
- Explicit integer widths, bits, and memory layout are valuable when modelling a processor and its peripherals.

These properties do not prescribe a particular implementation. Their appropriate use will remain subject to the evolution of Zig and the constraints of target platforms.

## What Zig_80 aims to become

### A learning environment

The project aims to make changes to registers, flags, memory, and the program counter observable one instruction at a time. Abstractions should organize the system without permanently hiding the boundaries that learners may want to inspect.

### An emulator

The emulator is intended to reproduce Z80 behavior in software so experiments remain available without physical hardware. Accuracy matters, but so do a structure that can be studied and methods that can be verified. The intended accuracy level may be defined progressively.

### An assembler

The project aims to let users produce their own ROMs without making the complete workflow depend on an external tool. Parsing, symbol resolution, and instruction encoding also provide a compact introduction to language implementation.

### A debugging environment

Users should eventually be able to stop a program and inspect registers and memory while advancing one instruction at a time. A common observation model across a CLI, a possible TUI, and physical hardware is one direction under consideration.

### A small game development environment

Zig_80 may support small games and demonstrations built around constrained video, input, audio, and time. The intended direction is not a large game engine, but a small SDK that keeps the relationship between the CPU and its peripherals visible.

### A physical-computer development environment

In the long term, the project aims to transfer a ROM developed in the emulator to a physical system and run the same program on a real Z80. This connection is central to viewing Zig_80 as a development environment rather than a collection of isolated tools.

## The intended world

```text
            Zig
             │
   ┌─────────┼─────────┐
   │         │         │
Assembler Emulator Debugger
   │         │         │
   └─────────┼─────────┘
             │
        Z80 Program
             │
      ┌──────┴──────┐
      │             │
 CLI Emulator   Real Hardware
```

Tools written in Zig cooperate around a common Z80 program. The assembler produces a ROM, the emulator provides an execution environment, and the debugger exposes state. In the intended future, that ROM is not solely an emulator artifact; it can also become input to physical hardware.

The diagram does not prescribe implementation relationships. Its important property is that each tool shares the meaning of the program and Machine instead of creating a separate, closed world.

## From emulator to real hardware

Early exploration can center on a deterministic and observable CLI emulator. It enables instructions and memory maps to be tested without requiring hardware and provides a controlled place to isolate problems.

The project may later develop toward a physical PCB. The central idea is not to rewrite emulator programs for that board, but for the same ROM to run unchanged on the real system.

Timing, initial state, undefined behavior, and peripheral differences make strict equivalence difficult. No compatibility guarantee is currently implied. The intended approach is to document a Machine specification over time and bring both environments toward the same contract.

## Hardware concept

Physical hardware remains a future concept rather than an implementation commitment. One direction under consideration places a genuine Z80 at the center while a modern microcontroller provides much of its supporting circuitry.

The microcontroller would implement a software-defined chipset as observed by the Z80. Possible responsibilities include:

- RAM
- ROM
- Video
- Input
- Audio
- Timer
- Storage
- USB Debug

When the Z80 accesses its address and control buses, the microcontroller would respond as the selected memory or virtual device. This could preserve the Z80 as the executing processor while giving display, storage, transfer, and debugging modern flexibility.

Bus timing, electrical requirements, and microcontroller response latency require careful validation. The final design may need dedicated logic or additional components; this concept should not be read as a selected schematic.

## Zig firmware direction

The firmware for the supporting microcontroller may eventually be written in Zig as well.

```text
Zig
│
├─ CLI Emulator
├─ Assembler
├─ Debugger
└─ Firmware
      │
      ▼
    Real Z80
```

Sharing a language between host tools and firmware may help align data formats, testing principles, and the expression of the Machine specification. It also provides a progression for learning Zig from CLI programming into embedded systems.

The target microcontroller, Zig's embedded support, and real-time constraints have not yet been fully evaluated. Direct code reuse should not become a goal in itself; sharing meaning and contracts is more important.

## A shared Machine specification

The CLI and physical versions are intended to share a Machine specification. The Machine is the contract for the computer as observed by a Z80 program. It may cover:

- Memory Map
- The roles of ROM and RAM
- VRAM layout and pixel representation
- Input bit representation
- Timer and frame state
- Future virtual peripherals

The emulator would reproduce this contract in software, while the physical microcontroller would present the same meaning on the bus. Ideally, a Z80 program uses defined addresses and state without needing to know where it is running.

The specification is not yet settled. Versioning, compatibility boundaries, and hardware-specific extensions will require further design work.

## Intended development experience

```text
Write ASM

↓

Generate ROM

↓

Run in the CLI

↓

Debug

↓

Transfer to hardware

↓

Run the same ROM
```

The CLI should provide short iteration cycles and detailed observation. Once a ROM has been examined there, it could be transferred to a system where a genuine Z80 executes the same instruction stream. When behavior differs, the ideal environment would make CLI and hardware state comparable through common concepts.

Transfer to hardware is not necessarily the end of development. The intended experience is a cycle between the emulator and hardware in which software errors, ambiguous Machine behavior, and physical constraints can all be studied.

## Educational value

Zig_80 is not solely intended to produce finished games efficiently. The tools and execution environment are themselves learning material.

- The CPU layer introduces instructions, registers, flags, stacks, interrupts, and timing.
- The assembler introduces syntax, expressions, symbols, relocation concepts, and machine-code representation.
- The emulator introduces state machines, decoding, verification, and an abstract bus.
- The debugger introduces observability and the role of development tools.
- Hardware introduces memory maps, buses, signals, timing, and peripheral circuits.
- Zig introduces explicit data representation, memory management, and the distinction between host and embedded environments.

Rather than hiding every layer behind a finished interface, the project aims to let learners descend one layer at a time. Future automation and abstraction should be assessed partly by whether they preserve that educational value.

## Possible long-term directions

The following items describe possible directions, not committed work. Their order, scope, and feasibility remain open.

- A complete Z80 emulator
- A broader assembler
- A debugger spanning CLI and hardware
- A TUI for continuous state observation
- A small game SDK
- Virtual video, input, audio, timer, and storage devices
- An original PCB containing a real Z80
- Microcontroller firmware written in Zig
- A USB debugger
- A shared ROM and Machine contract across CLI and hardware
- A WebAssembly edition for learning and sharing in a browser

These are not independent ends. The criterion for selecting a direction should be whether it strengthens a coherent experience across learning, development, observation, and hardware around a common ROM.

## Principles for future decisions

1. Keep the Z80 program central and avoid unnecessary dependence on closed, tool-specific formats.
2. Share the meaning of the Machine between CLI and hardware as far as practical.
3. Pursue accuracy while retaining a structure that learners can follow.
4. Build small, verifiable stages and distinguish clearly between concepts and implemented behavior.
5. Respect the constraints of a historic computer while making appropriate use of modern development support.

The final form of Zig_80 is not yet fixed. This document is not a permanent destination; it is a reference for the values by which the project may choose its direction.
