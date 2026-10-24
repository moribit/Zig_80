# Core contracts / Coreの契約

## Instruction faults

Unknown base or CB opcodes leave PC at the first instruction byte, all registers,
HALT state, instruction index and total T-states unchanged. No data reads or writes
occur for a rejected decode. `Cpu.fault` records PC, optional prefix and failing
opcode; legacy `last_unknown_*` fields remain supported. Instruction-byte fetch
events remain in the trace for diagnosis; they use the uncommitted instruction
index/T-state. Retrying may therefore produce another set of fetches at that same
index, distinguished by trace sequence. Trace is logical, not cycle-accurate.

The CB second byte is an opcode fetch (M1), not an operand fetch. PUSH/CALL write
the high stack byte first, then the low byte, with 16-bit address wrapping.

日本語: デコード失敗時はPCを命令先頭に保ち、レジスタ・HALT・命令数・T-stateを変更しません。
命令バイト取得のみTraceへ残し、データ読出し・書込みは行いません。再試行は同一命令番号ですが
Trace sequenceで区別できます。`fault` はプレフィックスを含む診断情報です。

## Initialization

| Operation | CPU | Program 0000–7FFF | RAM / VRAM | Input / frame / random | Trace |
|---|---|---|---|---|---|
| `resetCpu()` | reset | keep | keep | keep | keep |
| `resetPeripherals()` | keep | keep | RAM keep, VRAM clear | zero / zero / ACE1 | keep |
| `resetMachine()` / `reset()` | reset | keep | clear | reset | sequence/context reset |
| `powerOn()` | reset | clear | clear | reset | sequence/context reset |
| `load(program)` | reset | clear then copy | clear | reset | sequence/context reset |

Oversize load is rejected before any state change. Reset preserves attached trace
sinks; the owner clears external ring buffers. Debugger breakpoints/watchpoints
are owned by DebugSession, not Machine. Call `DebugSession.reset` after resetting
Machine to refresh snapshots and clear watchpoint history while preserving rules.
TUI no longer replaces Machine independently; load/reset use the shared contract.
Classic ROM remains writable for compatibility; protection is a profile concern.

日本語: CPU単独Reset、周辺Reset、ROM保持のMachine Reset、全消去のPower-on、
全消去後コピーするLoadを分けます。Traceの接続は保持し、外部バッファの消去は所有者が行います。
Debuggerの規則は保持し、Machine Reset後にSession ResetでSnapshotを更新してください。
従来の `reset()` はMachine Resetへ統一したため、RAM・入力・疑似乱数も初期化されます。

## Input replay

Scripts are stably sorted by instruction index; equal indices keep source order.
Events apply before the indicated instruction. Initial input defaults to zero;
`initial_state` can supply another value. `Replay.reset()` restores it and rewinds
the cursor. Advancing to a smaller instruction number automatically rewinds;
reset explicitly when resetting at the same instruction number. Event arrays
supplied directly to Replay must already be ordered. No wall clock participates.
`parseScriptLocated` returns one-based line/column and a precise error category.

日本語: 同一命令番号では記録順にpress/releaseを適用します。初期入力は既定0です。
Resetは初期入力と再生位置を復元し、命令番号が戻った場合も自動復元します。
同じ番号へのResetでは明示的に `reset()` を呼んでください。直接渡す配列は整列済みが前提です。

## Phase 1 verification

Baseline 65 tests; regression tests first produced 66 pass / 4 fail (70 total).
The fixes make those four tests pass. Additional tests cover reset contracts,
oversize-load atomicity, replay reset/order/diagnostics, exhaustive ADC/SBC and
ADD/SUB over all operands/carry values, INC/DEC boundaries, and an integration
golden for encoding/disassembly/CPU/memory/ordered logical trace.
Existing tests cover LD matrix, logic, CB documented matrix, branches, stack,
watchpoints, editor, display, waveform and rendering. This is not full Z80 validation.
