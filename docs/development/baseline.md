# Baseline / ベースライン

Recorded 2026-10-24, commit `90543fedd217f16e8c8cb960639bcbcdf9a6599c`, macOS ARM64.
Baseline compiler: Zig **0.16.0** (`/Users/mimoc/.zvm/0.16.0/zig`).
The shell default is 0.17.0; use an explicit compiler path for reproducibility.

## Verification / 検証

| Command (Zig 0.16.0) | Result |
|---|---|
| `zig version` | 0.16.0 |
| `zig fmt --check .` | pass |
| `zig build --summary all` | 3/3 steps, pass |
| `zig build test --summary all` | **65/65**, pass |
| `zig build run -- --help` | pass |
| `zig80 asm examples/pixel.asm -o /tmp/zig80-baseline-pixel.bin` | 6 bytes |
| `zig80 disasm /tmp/zig80-baseline-pixel.bin` | LD HL,0xC000; LD (HL),0x01; HALT |
| `zig80 run /tmp/zig80-baseline-pixel.bin --screen` | 3 instructions, 24 T-states, PC=0006, first pixel lit |

## Structure / 構造

- `cpu/cpu.zig`: explicit execution switch; `registers.zig`, `flags.zig`, `instruction.zig`: register pairs, arithmetic, partially shared metadata. `decoder.zig` only handles fixed definitions; `execute.zig` is a placeholder.
- `machine/`: 64 KiB Bus, Machine, 128×64 video, input scripts. `timer.zig` is an extension point; frame advance is explicit, not CPU-clock scheduled.
- `assembler/assembler.zig`: both passes, expression evaluation, encoding, recursive include/incbin and source provenance. Lexer/parser/encoder/expression files are placeholders.
- `disassembler/`: separate opcode switch, maximum three-byte instruction buffer.
- `debugger/`: shared DebugSession, conditional breakpoints, watchpoints, REPL; TUI uses this session.
- `trace/`: fixed-capacity ring, logical instruction-level bus events; no electrical/cycle timing.
- `tui/state.zig`: editor, execution, input and display tracking; `app.zig`: rendering; terminal session has restoration paths.
- `tests.zig`: most tests in one file; also imports documentation tests. `build.zig`: executable, run, test steps.
- `docs/`: English/Japanese reference, tutorials, guides and architecture. No CI workflow at baseline.

## Supported instruction families / 対応命令

NOP, HALT, immediate LD r/n and rr/nn, LD r/r and (HL), LD A/(nn), LD HL/(nn), INC/DEC r/(HL)/HL;
ADD A,r/n (missing (HL)), ADC A,r/(HL)/n, SUB r/n (missing (HL)), SBC A,r/(HL)/n,
CP r/n (missing (HL)); AND/OR/XOR r/(HL)/n; ADD HL,BC/DE/HL/SP;
JP unconditional/Z/NZ, JR unconditional/Z/NZ, DJNZ, unconditional CALL/RET,
PUSH/POP AF/BC/DE/HL; documented CB RLC/RRC/RL/RR/SLA/SRA/SRL and BIT/RES/SET, all registers/(HL).
Documented flags S/Z/H/PV/N/C are modeled; undocumented bits 3/5 are not modeled.

No IX/IY, DD/FD/ED, alternate registers, I/R, interrupt state, EI delay, INT/NMI, port instructions or block instructions.
Unknown opcode returns `UnknownOpcode`; PC is restored and instruction/T-state counters are unchanged.
CB decoding currently reads (HL) before rejecting undocumented SLL; this creates a misleading data-read trace.
PUSH currently writes stack low byte before high byte, contrary to Z80 logical access order.
16-bit Bus accesses wrap at FFFF. ROM is writable. CPU depends on Bus, not terminal/OS.

## Initialization and determinism / 初期化と再現性

`Machine.load` resets CPU but copies only new bytes; RAM, old program tail, input and random state remain.
`Machine.reset` resets CPU and frame count, preserves RAM/input/random state. TUI instead replaces Machine with `.{} ` before loading.
Input Recording appends events; script parsing sorts with an unstable sort using only instruction number.
Replay starts with zero input and has no reset API. Equal-timestamp order therefore lacks a contract.
CLI execution and headless runner call Cpu.step directly. No wall-clock dependency in headless execution.

## Documentation discrepancies / 文書との差異

File assembly already supports include/incbin and provenance (tested by existing fixtures), although README limitations still describe file-aware assembly as future work.
TUI calls `assembleLocated` on its buffer, so it cannot resolve includes as CLI does.
Disassembler accepts ADD/SUB/CP (HL) encodings that CPU and assembler reject.
The INC/DEC disassembly switch includes opcode 34 but omits it from its `is_inc` predicate: INC (HL) renders DEC (HL).
These observations are to be locked down by regression tests before behavior changes.

## Scope and reference / 検証範囲

Passing these 65 tests does not establish full Z80 compatibility. No independent differential suite was run at baseline.
Authoritative instruction reference: [Zilog UM0080](https://www.zilog.com/docs/z80/um0080.pdf).
Future machine addresses/ports are provisional; no physical hardware interface is implemented.

日本語要約: Zig 0.16.0 でビルド・整形・65件のテスト・CLIサンプルは成功。
CPUは文書化命令の一部のみ対応し、割り込みやIX/IYは未実装です。
再ロード後の旧データ、同時刻入力の順序、CBエラー時の不要なメモリ読出し、スタック書込み順、
INC (HL) の逆アセンブル、CLI/TUIのinclude経路差を回帰テストの対象とします。
