# Hardware boundary / 実機Debug境界

`--snapshot FILE` exports schema `zig80.snapshot`, version 1: profile/config,
full architectural CPU state and interrupt/fault state, 65,536 logical memory bytes,
bank map and configured physical ROM/RAM, display dimensions/page bytes,
deterministic device phases, bounded ordered Bus Trace and input event timeline.
Byte data is always numeric arrays (never data-dependent UTF-8 strings). JSON field
names/units and schema version are the interchange boundary, not Zig struct ABI.
This release exports inspection data; it does not restore snapshots or implement
a hardware debugger transport. Future incompatible changes require a new version.

Trace metadata says `logical-instruction`; events have instruction index, event
index, sequence, PC, logical address, signals and instruction-start T-state.
`t_state_count=0` explicitly means not cycle-accurate. The ring retains the latest
4,096 events; first/next sequence numbers expose truncation. Input events use
instruction-index-before-execution with zero initial mask in CLI exports.

Future adapters can expose capabilities for ROM upload/reset/memory access,
register snapshot/step/breakpoints/trace and emulator comparison. Register access
and single stepping may require a monitor ROM or external circuitry; none are
assumed universally available. Define capability negotiation before any protocol.
Compare snapshots only at agreed program/interrupt/bank/input boundaries and
compatible trace accuracy levels. Do not compare logical trace against pin cycles.

日本語: まず安定したJSON検査出力を優先し、通信プロトコルは実装しません。レジスタ取得やStepには
外部回路やMonitorが必要な場合があり、全実機で使用可能とは仮定しません。Traceは命令単位の
論理イベントで、直近4096件です。Snapshot復元、ROM転送、実機比較ツールは今後の作業です。
