# CPU contract / CPU契約

Cpu depends on registers, flags, instruction metadata and a statically typed Bus interface; no OS,
terminal, display or concrete peripheral code is imported. `step` and internal
helpers accept `anytype` Bus operations; a standalone test bus proves that Machine
and its devices are not required to compile CPU execution. Execution remains an
explicit switch. The canonical metadata in `cpu/extended_metadata.zig` describes
696 documented encodings, operand templates, lengths, timing/alternate timing and
flag effects. New encodings use the same table in assembler and disassembler;
legacy family implementations retain their syntax/formatting and are checked
against that table automatically. `zig build coverage` emits the reference table.

Implemented families include all canonical base instructions, documented CB,
ED arithmetic/load/I/O/interrupt/block instructions, IX/IY and indexed CB memory
operations. Alternate AF/BC/DE/HL, IX/IY, I/R, IFF1/2 and IM0/1/2 are explicit state.
R increments its low seven bits per M1 while preserving bit 7; DD/FD CB final
opcode is not M1. Repeated block instructions execute one iteration per step,
rewind PC by two and take 21 T-states while repeating, otherwise 16.

INT is level-sensitive through `setInt(asserted, vector)`. NMI is edge-latched by
`requestNmi()`, has priority, saves IFF1 to IFF2 and vectors to 0066. EI inhibits
maskable acceptance until after the following instruction. HALT is released by an
accepted interrupt; idle steps advance four T-states and R without retiring a new
instruction. IM1 vectors to 0038 (13 T); IM2 uses I:vector with wrapped word read
(19 T); NMI takes 11 T. IM0 currently supports injected RST only (13 T); other
injected instructions fail before state changes. Interrupt acceptance increments
the logical step index and emits an acknowledgement for maskable interrupts.
RETI restores IFF1 from IFF2 like RETN; daisy-chain device signalling is not modeled.

Unknown decode is atomic as described in [quality contracts](../development/quality-improvements.md).
For DD/FD CB faults, `fault.prefix` identifies DD/FD and `fault.opcode` the final
byte; intermediate CB/displacement bytes remain available in the logical trace.

Limits: flags 3/5, WZ/Q, undocumented opcodes/aliases, ignored/repeated prefixes,
WAIT/BUSRQ, refresh pins and cycle-accurate bus timing are not modeled. This is a
documented-instruction software development core, not a pin-level Z80 replacement.
Independent verification currently covers 27,000 vectors over 27 representative
encodings; it does not independently verify every table row or interrupt timing.

日本語: CPUはOSや具体的周辺機器から独立し、明示的switchで実行します。共通表の696行を
Assembler/Disassembler/CPU間で照合します。代替レジスタ、IX/IY、I/R、IFF、IMを保持し、
EI遅延、HALT解除、INT/NMIを命令境界で扱います。IM0はRST注入のみ対応します。
Block命令は1反復ずつStep可能です。未文書化フラグ、Prefixの無視や繰返し、WAITなどの
電気的挙動は対象外です。27,000件の独立検証は代表命令の検証で、全命令の実機一致を意味しません。
