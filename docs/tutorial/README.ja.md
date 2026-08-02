# Zig_80によるZ80プログラミング入門

[English](README.md)

このチュートリアルは、Z80やアセンブリ言語（Assembly language）を知らない現代のプログラマーが、Z80プログラミングとコンピュータ構成を学ぶためのものです。Zig_80のCLIとTUIは、プログラムを書く、アセンブルする、実行する、デバッグする、観察するための対等な道具として扱います。

## 学び方

各章は同じ順序で進みます。

1. 「この章で見る画面」で注目するPaneを絞る
2. ExampleをTUIで開く
3. 命令を1つずつStepする
4. `PC → Instruction → CPU → Bus → Display`の順で変化を見る
5. IDE Tipsで操作を1つ覚える
6. 数分のChallengeで値や命令を変更する

一度に全Paneを理解する必要はありません。最初はCurrent PCの`▶`と、Step後に強調された箇所だけを見ます。

## 目次

| 章 | 学ぶこと | 主に見る画面 |
|---|---|---|
| [00 はじめに](00-introduction.ja.md) | Setup、IDEの見取り図、学習方法 | Source、CPU、Instruction |
| [01 CPUと命令](01-cpu.ja.md) | Machine Code、PC、Fetch/Decode/Execute | Source、Instruction、Bus |
| [02 RegisterとFlag](02-register.ja.md) | `LD`、`ADD`、Register、Z/C Flag | Source、CPU |
| [03 MemoryとAddress](03-memory.ja.md) | RAM、括弧、Little Endian、Memory Map | Source、CPU、Memory、Bus |
| [04 比較・分岐・Loop](04-branch.ja.md) | `CP`、`DEC`、`JR`、`JP`、Breakpoint | Source、CPU、Bus |
| [05 SubroutineとStack](05-stack.ja.md) | `CALL`、`RET`、SP、`PUSH`/`POP` | Source、CPU、Memory |
| [06 VRAMからPixelへ](06-display.ja.md) | CPU→Bus→VRAM→Display、Inspector | Source、Bus、Display |
| [07 Logic Analyzer](07-bus.ja.md) | Fetch、Operand、Write、Address/Data/Event | Bus、Logic Analyzer |
| [08 小さなProject](08-projects.ja.md) | Counter、Pixel、Pong、Game of Life | 全Pane |

## Courseの到達点

```text
Source instruction
       │ assemble
       ▼
Machine-code bytes
       │ fetch / execute
       ▼
CPU registers and flags
       │ logical access
       ▼
Bus ── RAM / Input / VRAM ── Display
```

最後には、自分で短いROMを書き、どの命令がどのRegister、Memory Address、Bus Event、Pixelを変えたかをIDE上で説明できることを目指します。

必要な仕様は独立した[リファレンス](../reference/README.ja.md)、目的別の手順は[ガイド](../guides/README.ja.md)を参照してください。

[次: 00 はじめに →](00-introduction.ja.md)
