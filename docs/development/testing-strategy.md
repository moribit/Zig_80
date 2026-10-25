# Testing / テスト方針

Use Zig 0.16.0: `zig fmt --check .`, `zig build`, `zig build test --summary all`.
Tests are grouped by CPU, assembler, disassembler, Machine, debugger, trace and
TUI; `src/tests.zig` imports each suite. Documentation tests remain included.
CPU quality tests exhaustively compare ADD/ADC/SUB/SBC operand/carry combinations
against a signed/nibble arithmetic oracle. Golden data covers a complete program,
encoding, disassembly, CPU transitions, memory writes and ordered logical trace.
The 696-row metadata test roundtrips and executes every canonical encoding.
These are complementary checks; internal agreement alone is not CPU validation.

## Optional independent differential tests

Source: [SingleStepTests/z80](https://github.com/SingleStepTests/z80), revision
`ebe1875d48f374bcfd4b505d8eb8ee751568b5f7`, MIT, Copyright (c) 2024 SingleStepTests.
The upstream README describes Ares-derived vectors with fixes and does not claim
perfect hardware accuracy. No external data or library is required by normal build/test.
Run `zig build differential -- /path/to/v1/00.json ...` with locally downloaded
JSON files. Preserve the upstream MIT license when redistributing data.
`scripts/differential.sh` optionally downloads the pinned representative subset
and its license, then runs the same runner; set `ZIG` or `SST_CACHE_DIR` as needed.

The runner compares primary/alternate registers, IX/IY/I/R, documented F mask D7,
IFF/IM, final RAM, total T-states and ordered port transactions. It does not compare
flags 3/5, WZ/Q, upstream internal ei/p state, HALT idle cycles or per-pin waveforms.
Input port values are supplied from each vector. Unknown opcodes are failures,
not silently skipped. A mismatch causes nonzero exit status with diagnostics.

Local result: **27,000 / 27,000** passed after correcting DAA for non-BCD subtraction
states. Files: 00,07,09,10,27,34,76,86,8e,96,9e,be,c4,c5,ed42,ed4a,ed57,ed67,
ed6f,eda0,edb0,edb1,dd21,dd36,dd66,ddcb46,fd86 (1,000 vectors each).
The first run had 174 DAA failures; a regression test was added before the correction.

日本語: 通常テストは外部依存なしで実行できます。独立検証はMITの固定リビジョンを任意に取得し、
別の `differential` ステップで実行します。代表27命令・27,000件は成功しました。
比較対象は文書化レジスタ・フラグ・RAM・T-state・Port入出力です。未文書化状態や端子波形は
比較しません。外部Suite自身も完全性を保証するものではありません。

## CI and frontend checks

`.github/workflows/quality.yml` checks Zig 0.16/0.17 on Linux and macOS, Debug,
ReleaseSafe and ReleaseFast builds, Debug/ReleaseSafe unit tests, CLI smoke and
samples/replay comparison, and POSIX PTY terminal restoration. Formatting and
coverage reproducibility use 0.16 only. Actions are pinned to commit SHAs.
The optional external suite is a manual workflow input, separate from normal CI.

`scripts/smoke.sh` uses only the built CLI and standard shell utilities.
`python3 scripts/test_terminal.py` is an optional integration test tool: it opens
isolated PTYs for both profiles, sends Ctrl+Q and Ctrl+C, and verifies original
termios attributes, cursor visibility and alternate-screen exit, including forced startup failure. It does not
modify the user's terminal. Hard kills, power loss and fatal OS signals are not
restoration guarantees. Python/curl are development tools, not zig80 dependencies.

日本語: CIはLinux/macOSと0.16/0.17の組合せで実行します。外部CPUデータは手動オプションです。
PTY検証は両ProfileのCtrl+Q/Ctrl+C終了・起動途中の失敗後に端末設定・Cursor・代替画面の復元を確認します。
通常のzig80実行にはPythonやcurlは不要です。
