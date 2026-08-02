# Zig_80 IDE チュートリアル

[English](README.md)

この教材は、Z80やAssemblyを知らない現代のProgrammerが、Zig_80 IDEを操作しながらCPUとComputer Architectureを学ぶためのCourseです。Referenceを先に暗記する必要はありません。各章の小さなProgramを`Ctrl+T`でStepし、画面の変化を順に追ってください。

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
| [09 Reference](09-reference.ja.md) | CLI、Syntax、対応命令、Diagnostic、用語 | 必要な時だけ参照 |

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

[次: 00 はじめに →](00-introduction.ja.md)

