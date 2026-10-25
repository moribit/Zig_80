# Implementation report / 実装結果

Recorded 2026-10-25. Baseline: `90543fe`, Zig 0.16.0, 65 tests.
All new runtime functionality uses Zig/std only. Python/curl are optional test tools.

## Phase results

| Phase | Main commit | Result |
|---|---|---|
| 0 baseline | `0182c66` | Build, format, 65 tests and pixel CLI sample verified; audit recorded |
| 1 correctness | `50adcdc` | 76 tests; decode fault, reset/load, replay contracts and golden |
| 2 test split | `cfe1257` | All tests retained, separated by subsystem |
| 2 assembler split | `ac7e1e6` | Expression, Encoder and File Loader separated without behavior changes |
| 2 file assembly | `31ea97a` | Unsaved TUI root, include/incbin, cached pass inputs |
| 2 CPU | `7a88c6b` | 85 tests; 696 canonical encodings; 27,000 independent vectors passed |
| 3 handheld | `9ed0532` | 96 tests; profiles, banks, VFD, timer/input, samples and snapshots |
| CPU boundary | `f30c248` | Static Bus interface with independent test bus; 97 tests |
| Zig compatibility | `3d5c173` | Separate 0.17 reflection/error syntax compatibility, 0.16 retained |
| CI | `207e269` | First complete Linux/macOS × 0.16/0.17 matrix passed |

Final QA adds four-byte instruction display/timing, ED/indexed fault rollback,
prefix diagnostics, configured TUI initialization, included-file source matching,
and optimized macOS terminal-size regression coverage. Current suite: **100 tests**.
Operand normalization also preserves lowercase/space character literals, and RST/IM
accept hexadecimal expressions. Unconditional JR metadata reports its fixed 12 T.
See Git history for the final QA commit and the current CI run for its status.

## CPU

Canonical documented base, CB, ED, DD/FD, indexed CB encodings cover load,
arithmetic/logic, all condition codes, stack/exchange, DAA, rotate/shift, nibble
rotate, transfer/search/block I/O, ports and interrupt instructions. Alternate
registers, IX/IY, I/R, IFF/IM, EI delay, HALT, INT/NMI are explicit state.
[Generated table](cpu-coverage.md) records operands, length, timing and flags.
Every row roundtrips and executes in an internal consistency test.

Arithmetic validation exhausts operands/carry for ADD/ADC/SUB/SBC; DAA tests include
all valid packed-BCD add/subtract pairs and a non-BCD regression. Existing/new
tests cover CB operands, memory/stack ordering, conditional timing and address
wrapping. The golden compares encoding/disassembly/CPU/memory/logical trace and
final program result. Optional SingleStepTests comparison passed **27,000/27,000**
at pinned upstream revision; its scope/license are in [testing strategy](testing-strategy.md).
It caught 174 DAA mismatches before the correction. No full independent 696-form
or pin-timing validation is claimed.

Remaining incompatibilities: IM0 injects RST only, not arbitrary instructions;
undocumented flags 3/5, WZ/Q, undocumented aliases/SLL/index-high registers,
ignored/repeated prefixes, WAIT/BUSRQ and electrical cycle fidelity are not modeled.

## Machine and frontends

Classic's default map and pixel sample remain compatible (6 bytes, 3 instructions,
24 T-states). Reset/load now deliberately clear stale state under documented
contracts. Handheld has configurable clock/ports, four logical 16-KiB slots, up to
four ROM and four RAM banks, ROM write protection and independent 2,048-byte VFD.
Low-byte-decoded ports provide display addressing/data, buttons, banking and timer.
Device time advances solely from CPU T-states. Timers/input can wake HALT.
Six assembly samples are asserted headlessly; TUI uses the same Machine.step and
existing Display/editor/debugger features. Configured initialization loads the
selected profile before Step. Included source locations cannot masquerade as
root-buffer lines; editing included files in multiple tabs is not implemented.

PBM export and schema-v1 inspection snapshots provide CPU, full logical/physical
memory, mappings, display, device phases, bounded logical trace and input timeline.
Identical replay produces byte-identical JSON, and byte data is always numeric
arrays. Snapshot restore and hardware transport are not implemented. Trace is
instruction-level; it is not interchangeable with future cycle-accurate capture.

## Verification

- Zig 0.16 remains the format/minimum baseline; 0.17 builds/tests are supported.
- Debug and ReleaseSafe tests; Debug/ReleaseSafe/ReleaseFast executable builds.
- CLI samples, deterministic replay export, four-byte disassembly and fault diagnostics.
- POSIX PTY: both profiles, Ctrl+Q/Ctrl+C and startup failure restore termios,
  alternate screen and cursor. Debug and optimized builds are checked.
- Linux x86_64-musl cross-build succeeded locally. First GitHub CI matrix at
  `207e269` passed all four Linux/macOS × compiler jobs, including release builds.
- Optional external differential tests are isolated from normal builds and CI.

## Before hardware development

Confirm ROM/RAM capacities, bank-window/register design and power-on values,
clock/WAIT behavior, interrupt wiring/priority/vector protocol, button layout,
actual VFD model/controller/connector/timing and upload/reset interface. Decide
which debugging operations require a monitor or external circuit. Then define
capability negotiation and compatible snapshot/trace comparison points.

Recommended next work: broaden independent CPU vectors to all canonical forms
and interrupt sequences; add snapshot restore/roundtrip validation; improve
multi-file editor navigation and diagnostic recovery; specify actual hardware
before replacing provisional ports or inventing a transport.

日本語: Phase 0〜3の実装と検証を行い、既存65テストから100テストへ拡充しました。
696エンコードの内部整合性、27,000件の独立比較、Classic/Handheld、Golden、Replay、
CLI/TUI・端末復元を検証します。初回CIの4構成は成功しています。最低Zigは0.16のままで
0.17互換修正を別コミットに分離しました。

残る制限はIM0のRST以外、非公式命令/フラグ、サイクル精密性、複数診断の回復、複数ファイルを
同時編集するUI、Snapshot復元と実機通信です。TUIの実行速度は協調バッチで実時間同期ではありません。
実機開発前にBank・Clock・IRQ・VFD型番/接続・入力配置・Debug回路の仕様確定が必要です。
