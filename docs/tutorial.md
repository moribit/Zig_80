# Zig_80 Tutorial

[日本語](tutorial.ja.md)

This tutorial is for programmers who have never used a Z80, written assembly, or built CPU hardware. It leads from a one-instruction program to observing source code, machine code, registers, memory, logical Bus events, input, and the 1bpp Display in Zig_80.

Zig_80 is still an educational MVP. It implements a focused instruction subset and is not a complete or cycle-accurate Z80. This guide explicitly distinguishes the current virtual machine from a general, physical Z80 system and from the project's future hardware vision.

## What you will learn

```text
Assembly source (.asm)
        │ assemble
        ▼
Machine-code ROM (.bin)
        │ load
        ▼
Virtual Machine
  CPU ── Bus ── Memory
               ├─ RAM
               ├─ VRAM ── Display
               └─ Input
        │ observe
        ▼
CLI debugger / Zig_80 IDE
```

After completing the guide, you should be able to:

- explain registers, memory, PC, SP, flags, opcodes, and little endian values;
- write small ROMs using loads, arithmetic, comparison, branches, calls, and the Stack;
- choose between `asm`, `disasm`, `run`, `debug`, `test`, `explain`, and `tui`;
- connect one source instruction to its CPU, logical Bus, and Display effects;
- draw pixels in Zig_80's 128×64 1bpp VRAM layout;
- set the virtual input register from the CLI debugger;
- control continuous programs with pause, breakpoints, and execution limits; and
- distinguish logical event traces from physical, cycle-accurate signals.

## 1. Set up the project

You need macOS or Linux, Git, Zig 0.16, and an ANSI/VT100-compatible terminal. An 80×24 or larger terminal is recommended for the TUI. No external TUI or C library is required.

```console
zig version
zig build
zig build test
zig build run -- --help
```

The first `--` in `zig build run --` sends the remaining arguments to Zig_80 rather than Zig's build runner. After building, you may invoke the executable directly:

```console
./zig-out/bin/zig80 --help
```

Use Zig 0.16.x. Zig's development versions can have incompatible standard-library and build APIs.

## 2. Meet the CPU

A CPU reads numbers from memory, interprets them as instructions, and performs their operations. On the Z80, byte `0x76` means `HALT`. An assembler translates the human-readable instruction into that byte.

```text
halt        assembly instruction
  │ assembler
  ▼
76          machine-code byte
```

A byte contains 8 bits and ranges from hexadecimal `00` to `FF`. A 16-bit value uses two bytes and ranges from `0000` to `FFFF`. The Z80 has a 16-bit address space, so it can address 65,536 bytes at once.

### Your smallest program

`examples/halt.asm` contains:

```asm
org 0x0000
start:
    halt
```

- `org 0x0000` sets the next logical address to zero.
- `start:` names that address. The label name is not stored in the ROM.
- `halt` puts the CPU in its halted state.

```console
zig build run -- asm examples/halt.asm -o zig-out/halt.bin
zig build run -- disasm zig-out/halt.bin
zig build run -- run zig-out/halt.bin
```

Read the stop reason, instruction count, T-state count, and PC. PC is the Program Counter—the address of the next instruction. Since `HALT` is one byte, PC advances from `0000` to `0001`.

Conceptually, each instruction follows fetch, decode, and execute:

1. fetch an opcode from the address in PC;
2. decode the opcode;
3. change registers or memory;
4. advance PC or replace it with a branch target.

Zig_80 steps at instruction granularity. An instruction reports a T-state total, but Bus events are not individual electrical T-states.

## 3. Calculate with registers

Registers are small storage locations inside the CPU. Common 8-bit Z80 registers are `A B C D E H L F`; pairs form `AF BC DE HL`.

| Register | Useful first mental model |
|---|---|
| `A` | Accumulator used by arithmetic and comparison |
| `F` | Flags describing the last arithmetic result |
| `B`, `C` | Temporary values or counters; together `BC` |
| `D`, `E` | Temporary values; together `DE` |
| `H`, `L` | Together `HL`, commonly used as a memory address |
| `PC` | Address of the next instruction |
| `SP` | Stack Pointer |

`examples/add.asm` adds decimal 10 and 20:

```asm
org 0x0000
start:
    ld a,10
    ld b,20
    add a,b
    halt
```

`LD` loads a value. `ADD A,B` means `A ← A + B`.

```console
zig build run -- asm examples/add.asm -o zig-out/add.bin
zig build run -- debug zig-out/add.bin
```

At the prompt, try `registers`, three `step` commands, another `registers`, and `quit`. A becomes hexadecimal `1E`, which is decimal 30.

### Flags

| Flag | Meaning |
|---|---|
| `S` | Sign bit of the result |
| `Z` | Result is zero |
| `H` | Half carry or borrow across bit 3 |
| `PV` | Parity or signed overflow, depending on the instruction |
| `N` | A subtraction-type operation |
| `C` | Carry or borrow outside the value width |

Start by watching Z and C. `CP 4` leaves A unchanged but sets flags as if it calculated `A - 4`. If A equals 4, Z becomes one and `JR Z,label` takes its branch.

## 4. Understand memory and addresses

Think of memory as a numbered byte array:

```text
Address   8000  8001  8002  8003
Value       2A    00    FF    10
```

Parentheses mean “use this value as an address and access memory”:

```asm
ld hl,0x8000     ; put 8000 in HL
ld (hl),0x2A     ; write 2A at address 8000
ld a,(hl)        ; read address 8000 into A
```

Current memory forms include:

```asm
ld a,(hl)
ld (hl),a
ld (hl),42
ld a,(0x8000)
ld (0x8000),a
ld hl,(0x8000)
ld (0x8000),hl
```

The Z80 is little endian. Storing `HL=1234` at address `8000` writes `34` at `8000` and `12` at `8001`. Inspect it with `memory 0x8000 2` in the debugger.

### Zig_80 memory map

| Address | Purpose |
|---|---|
| `0000-7FFF` | program loaded at `0000` |
| `8000-BFFF` | general RAM |
| `C000-C3FF` | video RAM |
| `C400` | input state |
| `C401-C402` | little-endian frame counter |
| `C403` | pseudo-random byte |
| `C404-FFFF` | reserved RAM |

This is Zig_80's machine specification, not a universal Z80 memory map. A machine designer chooses which devices respond to which addresses. The current program range is also not write-protected, even when the generated binary is informally called a ROM.

## 5. Compare, branch, and loop

Create `counter.asm`:

```asm
org 0x0000
start:
    ld b,5
loop:
    dec b
    jr nz,loop
    halt
```

`DEC B` subtracts one and sets Z when B reaches zero. `JR NZ,loop` branches while Z is not set. Step it in the debugger and watch B and Z.

- `JP` uses a 16-bit absolute target. Zig_80 supports unconditional, Z, and NZ forms.
- `JR` uses an offset from the following instruction and must stay in -128…+127 bytes. It supports unconditional, Z, and NZ forms.

An infinite loop such as `forever: jp forever` is valid and useful for a game loop. Zig_80 keeps it safe with execution limits:

```console
zig build run -- run program.bin --max-instructions 1000 --max-cycles 10000
```

The TUI executes at most 500 instructions per cooperative UI tick. Escape pauses it. Default total limits are 10,000,000 instructions or 100,000,000 T-states.

## 6. Use subroutines and the Stack

```asm
org 0x0000
start:
    ld sp,0xBFFF
    ld a,1
    call twice
    halt
twice:
    add a,a
    ret
```

`CALL` pushes the return address on the Stack and jumps. `RET` pops that address back into PC. The Z80 Stack grows toward lower addresses. Initializing SP to the end of general RAM avoids casually colliding with VRAM or reserved device memory.

Register pairs can also be saved:

```asm
push af
push hl
; temporary work
pop hl
pop af
```

Pop in reverse order. Zig_80 currently supports AF, BC, DE, and HL. An unbalanced Stack can make RET return to an unintended address.

## 7. Draw your first pixel

`examples/pixel.asm` writes one byte to VRAM:

```asm
org 0x0000
VRAM equ 0xC000
start:
    ld hl,VRAM
    ld (hl),0x01
    halt
```

```console
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
```

The display is 128×64 at 1bpp. One byte represents eight vertical pixels:

```text
address = C000 + (y / 8) * 128 + x
bit     = y % 8
mask    = 1 << bit
```

| Pixel | Address | Bit | Value |
|---|---:|---:|---:|
| `(0,0)` | `C000` | 0 | `01` |
| `(0,7)` | `C000` | 7 | `80` |
| `(0,8)` | `C080` | 0 | `01` |
| `(64,4)` | `C040` | 4 | `10` |

Combining individual pixels in one byte normally requires bitwise operations. Current Zig_80 does not implement `OR`, so examples write complete byte patterns such as `18` or `38`.

## 8. Follow one instruction through the IDE

```console
zig build run -- tui examples/pixel.asm
```

Non-empty source is assembled and loaded at startup. Editing makes it Dirty without assembling on every keystroke. `Ctrl+R` assembles the in-memory source; `Ctrl+S` saves and assembles.

Press `Ctrl+T` three times:

1. `LD HL,VRAM`: CPU shows `HL 0000 ↓ C000`; the Source overlay shows `HL ← C000`.
2. `LD (HL),01`: Bus shows a Memory Write and Display highlights the changed pixel.
3. `HALT`: execution enters the halted state.

Each pane is a different view of the same instruction:

| Pane | Question it answers |
|---|---|
| Source | What did I write? |
| Instruction | What opcode, length, timing, and description were decoded? |
| CPU | Which registers and flags changed? |
| Bus | Which addresses were logically read or written? |
| Display | Which VRAM write became a pixel? |

Source markers are independent: `┃` editing cursor, `▶` current PC, `●` breakpoint, `!` diagnostic, and `▲` last executed line.

### Essential keys

| Key | Action |
|---|---|
| `Ctrl+R` | assemble |
| `Ctrl+E` | reset and run |
| `Ctrl+T` | step one instruction |
| `Ctrl+Space` | continue |
| `Esc` | pause or cancel an input mode |
| `Ctrl+B` | toggle source breakpoint |
| `Ctrl+P` | Command Palette |
| `Ctrl+S` | save |
| `Ctrl+Q` | quit |
| `Ctrl+1..5` | Source, CPU, Memory, Bus, Display |

See the [TUI Guide](tui.md) for completion, search, navigation, rename, Memory input, Bus filters, waveform zoom, Display scale, grid, and pixel inspection.

## 9. Stop at a breakpoint

Open `examples/add.asm`, place the editing cursor on `add a,b`, press `Ctrl+B`, then press `Ctrl+E`. At the breakpoint, inspect A and B and use `Ctrl+T` to execute only the addition.

Breakpoints use generated instruction addresses. Comment-only, blank, or label-only lines may not generate one. Reassembly can move addresses.

The CLI debugger accepts direct addresses:

```text
break 0x0004
continue
delete 0x0004
```

## 10. Read the Bus and Logic Analyzer

A physical bus carries addresses, data, and control levels between a CPU, memory, and peripherals. Zig_80 currently records logical Opcode Fetch, Operand Read, Memory Read, and Memory Write events. I/O and refresh event kinds are reserved for future use.

In the Bus pane, `[` and `]` select events, End follows the newest event, Enter follows its source, `+`/`-` changes zoom, `f` fits, and `<`/`>` pans.

> Bus Waveform visualizes logical bus accesses observed during instruction execution as equal-width events. It does not reproduce the electrical timing of a physical Z80 or the duration of individual T-states.

- The horizontal axis is event order, not seconds or a physical clock.
- `t_state_start` is the instruction's starting total, not an access timestamp.
- `t_state_count = 0` means an unmeasured logical model.
- A slash in `/MREQ`, `/RD`, or `/WR` denotes an active-low signal.
- Do not infer physical pulse widths from the display.

## 11. Set virtual input

Address `C400` is the input register:

| Bit | Mask | Input |
|---:|---:|---|
| 0 | `01` | Up |
| 1 | `02` | Down |
| 2 | `04` | Left |
| 3 | `08` | Right |
| 4 | `10` | A |
| 5 | `20` | B |
| 6 | `40` | Start |
| 7 | `80` | Reserved |

Combine buttons by combining their bits; Up+A is `0x11`. In the CLI debugger:

```text
input 0x11
memory 0xC400 1
```

`examples/moving_pixel.asm` reads this register and treats value 4 as Left. It performs one movement and HALTs. The current TUI does not provide real-time game-key input, so use the CLI debugger for input experiments.

## 12. Watch continuous programs

```console
zig build run -- tui examples/pinpon.asm
zig build run -- tui examples/game_of_life.asm
```

Press `Ctrl+E`, then `Ctrl+5` for Display. Pinpon bounces a ball between fixed paddles. The Game of Life example alternates two precomputed blinker patterns; it does not implement a general neighbor-counting engine. Both stay within the current instruction subset and deliberately loop without HALT. Escape pauses them.

Their delay loops make visual changes observable, but TUI Run is not synchronized to a physical Z80 frequency. Apparent speed depends on the host, cooperative UI ticks, and rendering work. There is no implied 3.5 MHz or other real-time clock guarantee.

## 13. Assembly syntax reference

### Values and expressions

```asm
42              ; decimal
0x2A            ; hexadecimal
0b101010        ; binary
'A'             ; one-byte character literal
$               ; current logical address
VRAM + 64       ; simple addition
end - start     ; simple subtraction
```

Expressions currently support simple recursive `+` and `-`. There is no arithmetic-parenthesis precedence, multiplication, division, or general bitwise expression syntax.

### Directives

```asm
org 0x0000
db 1,2,0xFF
db "HELLO",0
dw 0x1234,start
VALUE equ 42
```

`db` emits bytes and strings; `dw` emits little-endian words; `equ` defines a symbol without output. `org` changes the logical PC but does not pad the flat output file. Beginner programs should use one continuous region starting at `org 0x0000`.

### Currently supported instruction forms

```text
NOP                 HALT                RET
JP address          JP Z,address        JP NZ,address
JR address          JR Z,address        JR NZ,address
CALL address
PUSH AF|BC|DE|HL    POP AF|BC|DE|HL
INC A|B|C|D|E|H|L|HL
DEC A|B|C|D|E|H|L|HL
ADD A,r8            ADD A,n8
SUB r8              SUB n8
CP r8               CP n8
LD r8,n8            r8 = A|B|C|D|E|H|L
LD r16,n16          r16 = BC|DE|HL|SP
LD A,(HL)           LD (HL),A           LD (HL),n8
LD A,(address)      LD (address),A
LD HL,(address)     LD (address),HL
```

Editor completion contains a wider educational Z80 vocabulary. A suggestion such as LDI, IX, or IY does not mean it is implemented. Use this list and assembler diagnostics as the authority.

## 14. Choose a CLI command

| Command | Purpose |
|---|---|
| `asm` | create a ROM binary from source |
| `disasm` | inspect addresses, bytes, and decoded instructions |
| `run` | execute quickly until HALT or a limit |
| `debug` | step and operate memory, breakpoints, and input in a REPL |
| `test` | check that a program HALTs within 100,000 instructions |
| `explain` | inspect concise source encoding output |
| `tui` | edit and observe Source, CPU, Bus, and Display together |

A useful iteration is:

```console
zig build run -- asm my_program.asm -o zig-out/my_program.bin
zig build run -- disasm zig-out/my_program.bin
zig build run -- test zig-out/my_program.bin
zig build run -- tui my_program.asm
```

An intentional infinite loop will not pass `test`; that command only verifies HALT. Use TUI pause, breakpoints, and limits for continuous programs.

## 15. Read diagnostics

Diagnostics include file, line, column, source span, and where available a hint. Common causes are:

| Diagnostic | Check |
|---|---|
| invalid mnemonic | spelling and the supported list |
| invalid operand | register combination, commas, parentheses |
| undefined symbol | label spelling and definition |
| duplicate symbol | repeated label or `equ` |
| value out of range | 8-bit values are 0…255; 16-bit values are 0…65535 |
| JR out of range | use JP or move code closer |
| invalid expression | empty operand or unsupported operator |
| unterminated string | closing quote in `db "..."` |
| invalid character literal | exact one-byte form such as `'A'` |

The TUI shows `!` and an inline message and can navigate to a diagnostic with Enter. Assembly currently stops after the first error, so another may appear after reassembly.

## 16. Start your own program

```asm
; my_program.asm
org 0x0000
RAM   equ 0x8000
VRAM  equ 0xC000
INPUT equ 0xC400

start:
    ld sp,0xBFFF
    ; initialize state

main_loop:
    ; read input, update state, draw
    halt               ; keep early lessons finite
    ; jp main_loop      ; replace HALT for a continuous program
```

Grow it in small verified stages: HALT, load a register, write one RAM byte, draw one VRAM byte, add a finite loop, add a subroutine, and only then make the main loop continuous. Disassemble after each stage.

## 17. Exercises

1. Load A with 255, add one, and predict A, Z, and C before stepping.
2. Store `HL=1234` at `8000` and confirm bytes `34 12`.
3. Count A down from three and HALT at zero using `DEC` and `JR NZ`.
4. Draw pixel `(10,9)`. Its address is `C08A`, bit 1, mask `02`.
5. For exercise 4, record Source line, PC, opcode bytes, HL before/after, Memory Write address/data, and changed pixel. This is the core Source→CPU→Bus→Display relationship.

## 18. Before physical hardware

The current machine is software. A physical Z80, breadboard, PCB, and MCU chipset remain future ideas described in [Vision](vision.md), not implemented project features.

Physical systems add voltage levels, current, power, grounds, reset and clock timing, tri-state buses, chip-select logic, signal integrity, decoupling, ROM programming, and debug wiring. Always consult the exact component data sheets. A 5 V Z80 and a 3.3 V MCU may require level translation; direct connection is not automatically safe. Never use Zig_80's logical waveform as a wiring diagram or electrical timing guarantee.

## 19. Current boundaries

- The complete Z80 instruction set, prefixes, IX/IY, interrupts, and I/O instructions are not implemented.
- Execution is not cycle-accurate or frequency-synchronized, and input is not real time.
- Bus slots are equal-width logical events.
- CLI `test` checks only HALT and has no ROM assertion format.
- TUI targets macOS/Linux terminals and lacks Windows, mouse, clipboard, and multiple-file support.
- Program memory is not write-protected.
- Frame and pseudo-random registers are simple machine-device models, not physical timers.

## 20. Give useful feedback

During the usage phase, record feedback with enough context to reproduce it:

```text
Environment: OS, terminal, Zig version, terminal size
Goal:        program or concept you were working on
Steps:       exact command and keys
Expected:    intended behavior
Actual:      output, diagnostic, or terminal behavior
Artifact:    minimal .asm and screenshot when relevant
```

For learning UX, also note which instruction you were trying to understand and which Source, CPU, Bus, or Display relationship was unclear.

## 21. Continue learning

- [TUI Guide](tui.md): complete Editor, Memory, Bus, Display, and palette controls
- [Vision and Architecture](vision.md): principles and possible hardware direction
- [`examples/pixel.asm`](../examples/pixel.asm): smallest Display program
- [`examples/add.asm`](../examples/add.asm): register arithmetic
- [`examples/pinpon.asm`](../examples/pinpon.asm): continuous game loop
- [`examples/game_of_life.asm`](../examples/game_of_life.asm): continuous VRAM animation

## Glossary

| Term | Meaning |
|---|---|
| assembly | low-level language made of mnemonics and operands |
| assembler | tool translating assembly into machine code |
| opcode | byte identifying an instruction |
| operand | register, value, or address used by an instruction |
| register | storage inside the CPU |
| PC / SP | Program Counter / Stack Pointer |
| flag | bit recording zero, carry, and other arithmetic properties |
| RAM / ROM | working memory / program-oriented read-only memory |
| VRAM | memory representing Display contents |
| Bus | address, data, and control connection between components |
| T-state | basic Z80 timing clock unit |
| little endian | low byte stored at the lower address |
| Stack | LIFO memory area for return addresses and temporary values |
| label | source name for an address |
| immediate | value embedded directly in instruction bytes |
| 1bpp | one bit per pixel |

