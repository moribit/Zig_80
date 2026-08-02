# Z80 Hardware Basics and Future Zig_80 Target

[Index](README.md) | [日本語](hardware-basics.ja.md)

The physical board described here is a future direction, not an implemented Zig_80 target. Current execution is a software virtual machine.

## CPU and buses

A physical Z80 exposes a 16-bit Address Bus, 8-bit bidirectional Data Bus, and control pins. Address lines select a location; Data lines carry a byte; control lines say what kind of transfer is occurring.

| Signal | Role |
|---|---|
| Clock | sequences internal CPU activity |
| `/MREQ` | memory request |
| `/IORQ` | port I/O request |
| `/RD` | CPU reads from the selected device |
| `/WR` | CPU writes to the selected device |
| `/M1` | first machine cycle of an instruction, including opcode fetch |
| `/RFSH` | dynamic-RAM refresh address/cycle indication |
| `/WAIT` | external device extends an access |
| `/INT`, `/NMI` | maskable and non-maskable interrupt requests |
| `/BUSREQ`, `/BUSACK` | another bus master requests/receives the buses |

The slash denotes active low: the asserted state is the lower voltage level. A schematic or data sheet may instead draw an overbar or suffix such as `_n`.

## Logic levels and safe interfacing

Classic Z80 parts commonly operate at 5 V, while an RP2350-class MCU is a 3.3 V device and is not generally 5 V tolerant. A logic “1” is a voltage range, not the abstract boolean shown by the emulator. Check the exact Z80 variant and MCU data sheets for input thresholds, output levels, current, absolute maximum ratings, and power sequencing.

A future design may need direction-controlled level shifters or 5 V-compatible buffers. Bidirectional Data Bus and ownership changes are more complex than unidirectional Address outputs. Incorrect direction can cause bus contention and damage components. Decoupling, common ground, reset, clock quality, propagation delay, fan-out, and chip-select decoding also require independent electrical review.

## Possible RP2350 Bus Controller

One direction under consideration is a real Z80 executing the ROM while an RP2350-class MCU implements a software chipset:

```text
Real Z80
   │ address / data / control
   ▼
RP2350-class Bus Controller (future Zig firmware)
   ├─ RAM / ROM service
   ├─ Video and input
   ├─ Audio / timer / storage
   └─ USB debug bridge
```

This would require deterministic bus-response firmware, level translation, safe bus ownership, measured timing, and a PCB. None is implemented or electrically validated in the repository today.

## Logical Trace versus a real waveform

Zig_80 Trace records equal-width logical accesses. A physical analyzer samples pins over real time and exposes clock edges and pulse widths. Current `t_state_count=0` events cannot prove setup/hold time, WAIT behavior, refresh timing, or signal integrity. They must never be used as electrical timing evidence.

## Shared Machine contract

The long-term goal is for CLI Emulator and a future PCB to share a versioned contract: entry address, ROM/RAM/VRAM ranges, Display layout, Input bits, I/O ports, and observable debug behavior. “The same ROM runs on both” requires conformance tests; it is a design objective, not a current hardware capability.

