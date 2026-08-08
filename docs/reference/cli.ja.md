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
