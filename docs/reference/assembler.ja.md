# アセンブラ構文リファレンス

[目次](README.ja.md) | [English](assembler.md)

2 Passアセンブラは、大文字小文字を区別しないシンボル（Symbol）、ラベル（Label）と前方参照、`;`コメントに対応します。

```asm
org 0x0000
VRAM equ 0xC000
start:
    ld hl,VRAM + 64
    db "HELLO",0
    dw start,0x1234
```

値は10進、`0x` 16進、`0b` 2進、`'A'`形式の1 byte文字、Symbol、現在の論理Address `$`を使用できます。式は再帰的な`+`と`-`のみです。算術括弧、乗除算、剰余、Shift、Bit演算は未実装です。

`org`は論理Addressを変えますが出力FileをPaddingしません。`db`はbyte/String、`dw`はLittle Endianのword、`equ`は定数を定義します。File Assemblyは相対Pathの`include "file.inc"`と`incbin "asset.bin"`、Include Cycle検出、Included File内DiagnosticとSource provenanceに対応します。

`asm`は`--symbols FILE`、`--source-map FILE`、`--listing FILE`も出力できます。SectionとLinker形式の配置は未実装です。

Memory上のResultは出力byte、Label/値Symbol、Source行/Address対応を保持します。Assemblerは最初の構造化Diagnosticで停止します。
