# 09 Reference

[← Previous](08-projects.md) | [Contents](README.md) | [日本語](09-reference.ja.md)

Consult this chapter while writing examples; do not memorize it before using the IDE.

## CLI

| Command | Purpose |
|---|---|
| `asm source.asm -o program.bin` | two-pass assembly and symbols |
| `disasm program.bin` | addresses, bytes, instructions |
| `run program.bin` | execute until HALT or limit |
| `debug program.bin` | Step, Memory, breakpoint, input REPL |
| `test program.bin` | basic HALT-within-100,000-instructions check |
| `explain source.asm` | concise source encoding |
| `tui [source.asm]` | Zig_80 IDE |

Intentional infinite loops do not pass `test`, because it verifies only HALT.

Debugger commands are `step/s`, `continue/c`, `registers/r`, `memory/m <address> <length>`, `disasm <address> <count>`, `break <address>`, `delete <address>`, `input <value>`, `screen`, `reset`, and `quit/q`. Debugger numbers are decimal or hexadecimal with a lowercase `0x` prefix.

## Values and directives

```asm
42              ; decimal
0x2A            ; hexadecimal
0b101010        ; binary
'A'             ; one-byte character
$               ; current logical address
VRAM + 64       ; simple + / - expressions

org 0x0000
db 1,2,0xFF
db "HELLO",0
dw 0x1234,start
VALUE equ 42
```

There is no arithmetic-parenthesis precedence, multiplication, division, or general bitwise expression syntax. `org` changes logical PC but does not pad the flat output. `dw` is little endian.

## Supported instruction forms

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

Completion includes wider educational vocabulary. LDI, IX/IY, prefixes, interrupts, and I/O instructions are not currently implemented.

## Diagnostics

Check spelling/support for invalid mnemonic; register combinations and punctuation for invalid operand; definitions for undefined/duplicate symbols; 0…255 or 0…65535 for range errors; JP for a distant JR; closing quotes for strings; and exact `'A'` form for characters. Assembly currently stops at the first error.

## Before physical hardware

Physical Z80s, breadboards, PCBs, and an MCU chipset remain future ideas in [Vision](../vision.md). Real systems add voltage/current limits, grounds, clock/reset timing, tri-state buses, chip selects, signal integrity, and decoupling. Consult exact data sheets; a 5 V Z80 and 3.3 V MCU are not automatically safe to connect. Never use the logical waveform as wiring or electrical timing guidance.

## Current boundaries

The full instruction set, prefixes, IX/IY, interrupts, I/O, cycle accuracy, frequency synchronization, and real-time input are absent. Bus slots are logical events. TUI targets macOS/Linux and lacks Windows, mouse, clipboard, and multiple files. Program memory is not write-protected.

## Glossary

| Term | Meaning |
|---|---|
| mnemonic / operand | operation name / register, value, or address it uses |
| opcode | byte identifying an instruction |
| PC / SP | Program Counter / Stack Pointer |
| flag | bit recording zero, carry, or another result property |
| RAM / ROM / VRAM | working / program / Display memory |
| Bus | address, data, and control connection |
| T-state | basic Z80 timing clock unit |
| little endian | low byte at lower address |
| Stack | LIFO area for return addresses and temporary values |
| immediate | value embedded in instruction bytes |
| 1bpp | one bit per pixel |

[← Previous](08-projects.md) | [Contents](README.md)

