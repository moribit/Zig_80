# CLIリファレンス

[目次](README.ja.md) | [English](cli.md)

```text
zig80 asm <source.asm> -o <output.bin> [--symbols FILE] [--source-map FILE] [--listing FILE]
zig80 run <program.bin> [--max-instructions N] [--max-cycles N] [--input-script FILE] [--screen]
zig80 debug <program.bin>
zig80 disasm <program.bin>
zig80 test <program.bin>
zig80 explain <source.asm>
zig80 tui [source.asm]
zig80 --help
```

`tui`以外はHeadlessで利用できます。`asm`はFlat Binaryを書きSymbolを表示し、相対Include/Incbinを解決し、Symbol/Source Map/Listing Artifactを任意出力します。`run`の既定上限は1,000,000命令、10,000,000 T-stateです。`test`は100,000命令以内のHALTだけを検証します。`disasm`は未知byteを`DB`として表示します。

`--input-script`は命令IndexでPress/Release Eventを決定的にReplayします。Disassembly/DebuggerでのSymbol File読込、Project、Trace、Profile、Asset、Machine選択、Directory Test SuiteはまだCLIに実装されていません。

## Profiles and exports / Profile・検査出力

`run` and `tui` accept `--profile classic|handheld` and `--clock-hz N`.
`run --export-frame FILE` writes PBM; `--snapshot FILE` writes schema-v1 JSON
(CPU, memory/banks, display, devices, bounded logical trace, input timeline).
`run --rom-bank N FILE` loads an extra physical ROM bank in Handheld.
See [Handheld VM](../handheld/virtual-machine.md) and [snapshot contract](../handheld/hardware-debugging.md).

日本語: Profileの既定はClassicです。追加オプションは既存の呼出しを維持し、Handheldと検査出力を
明示的に有効化します。ROM bankファイルは16KiB以下です。実機への通信は行いません。
