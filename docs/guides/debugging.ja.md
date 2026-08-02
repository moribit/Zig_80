# デバッグ手順ガイド

[目次](README.ja.md) | [English](debugging.md)

再現可能な行単位確認にはCLI、相関した可視化にはTUIを使います。

1. Assemble/Disassembleでbyteを確認
2. 最初にStateが崩れる命令までStep
3. Register Pairと関連RAMを確認
4. Loop前へAddress/Source Breakpoint
5. 疑わしいRead/WriteへBus Filter
6. VRAMならPixel InspectorとWriterを確認
7. Tool Issueは最小ROMへ縮小

Breakpointは条件、Hit Count、Temporary、Enable/Disableに対応し、WatchpointはRead/Write RangeとValue条件に対応します。Bus Traceは論理Accessで、実Timingではありません。
