# Memory and I/O map / Memory・I/O Map

## Classic (existing contract)

0000–7FFF program (writable); 8000–BFFF RAM; C000–C3FF 128×64 VRAM;
C400 input; C401–C402 frame counter (little endian); C403 deterministic random;
C404–FFFF reserved RAM. Unassigned port reads return FF; writes are ignored.

## Handheld (provisional)

| Logical range | Default mapping | Control |
|---|---|---|
| 0000–3FFF | ROM bank 0 | fixed boot slot |
| 4000–7FFF | ROM bank 1 | ROM bank port 20 |
| 8000–BFFF | RAM bank 0 | RAM bank port 21 |
| C000–FFFF | RAM bank 1 | fixed working/stack slot |

Up to four 16 KiB ROM and four RAM banks; configured counts must be 2–4.
`Banks.map` can assign any valid physical bank/kind to any slot for alternative
virtual layouts. Logical addresses and physical bank indices remain distinct.
CPU writes to ROM are ignored but attempted writes remain logical trace events.
Invalid bank register values are ignored; invalid direct map calls return an error.
Word accesses wrap FFFF→0000 and can cross different mapped/protected regions.

The display's 2,048 bytes are independent VRAM, accessed only through controller
ports. All 16-bit I/O port addresses are traced; this provisional device map decodes
only the low byte. Therefore 0142 and FF42 select the same display data port.
Undefined ports read FF and ignore writes. A configured external PortDevice may
replace I/O dispatch; it is separate from CPU semantics and needs no allocation.

日本語: ClassicのMMIOマップは維持します。Handheldは16KiB単位の4窓をROM/RAMへ対応し、
既定では4000窓と8000窓のみPortで切り替えます。ROM書込みは無視し、試行をTraceへ残します。
独立VRAMはPort経由です。16bitのZ80 PortをTraceし、仮デバイスは下位8bitだけを解釈します。
アドレス・Portは実機の決定後に置換する暫定仕様です。
