# 07 Logic Analyzer: read logical Bus events

[← Previous](06-display.md) | [Contents](README.md) | [日本語](07-bus.ja.md) | [Next: Projects →](08-projects.md)

## Panels to watch

- **Bus Instruction Card** selected instruction and event group
- **Logic Analyzer** event-time axis, signals, cursor
- **Source/Instruction** instruction responsible for an event

## Goal

Distinguish Opcode Fetch, Operand Read, and Memory Write; read address, data, event slots, and the Time Cursor; and explain why this is not a physical trace.

A bus carries:

- **Address**: where an access goes;
- **Data**: what is read or written;
- **Control**: read/write and memory/I/O selection; and
- **Event**: one logical access observed by Zig_80.

Step the first two instructions in `examples/pixel.asm`, then open Bus with `Ctrl+4`.

## Event types

```text
Instruction LD HL,C000
  event 0  Opcode Fetch  ADDR 0000  DATA 21
  event 1  Operand Read  ADDR 0001  DATA 00
  event 2  Operand Read  ADDR 0002  DATA C0

Instruction LD (HL),01
  ... instruction-byte accesses ...
  Memory Write           ADDR C000  DATA 01
```

Opcode Fetch reads the operation at PC and asserts logical M1. Operand Reads fetch immediate bytes. Memory Write carries C000 and 01 with `/MREQ` and `/WR` asserted low. Selecting the write links Source, Instruction, captured CPU state, and Display Inspector.

## Read the Analyzer in order

1. `Time →` establishes left-to-right event order.
2. `Instruction #` headings group accesses.
3. The thin `│` Time Cursor crosses all rows at the selected event.
4. Read M1, `/MREQ`, `/RD`, `/WR` transitions.
5. Read boxed ADDR and DATA values.
6. Confirm TYPE and the PC/event/data detail line.

A slash denotes active low; a low pulse means asserted.

> Bus Waveform visualizes logical bus accesses observed during instruction execution as equal-width events. It does not reproduce the electrical timing of a physical Z80 or the duration of individual T-states.

### Column: compared with physical hardware

A real logic analyzer samples voltage levels at a known rate. Engineers measure pulse widths, clock relationships, and setup/hold constraints. Zig_80 gives every event an equal-width slot:

- horizontal width is event order, not ns, µs, or clock count;
- `t_state_start` is the instruction's starting total, not access time;
- `t_state_count = 0` means an unmeasured logical model;
- pulse width cannot establish hardware timing; and
- refresh, interrupt, and I/O events are not currently generated.

## IDE Tips

- `[` / `]`: previous/next event; End: follow latest.
- Enter: follow event source.
- `+` / `-`: 1x/2x/4x zoom; `f`: Fit.
- `<` / `>`: pan independently from the cursor.
- Palette: all events or Memory Write filter.

## Challenge: classify the trace

Step all three instructions in `pixel.asm`. Record instruction number, event index, type, address, and data for every event. Count fetches, operands, and writes, then verify using the Memory Write filter.

[← Previous](06-display.md) | [Contents](README.md) | [Next →](08-projects.md)

