# 08 小さなProject: 学んだ流れを組み合わせる

[← 前: Logic Analyzer](07-bus.ja.md) | [目次](README.ja.md) | [English](08-projects.md) | [次: Reference →](09-reference.ja.md)

## この章で見る画面

- **Source**を主役にする
- **CPU**でState、Counter、Flagを見る
- **Bus**でRead/Writeを絞る
- **Display**でGame Loopの結果を見る
- **Logic Analyzer**は疑問のある1命令をPauseして調べる

## Projectの進め方

大きなGameを一度に書かず、動くCheckpointを積み重ねます。

1. HALTだけをAssemble/Step
2. Registerを初期化
3. RAM 1 byteをWriteして確認
4. VRAM 1 byteをWriteして確認
5. 有限Loopを追加
6. SubroutineとSP初期化を追加
7. Breakpointを置く
8. 最後にHALTをMain LoopへのJPへ変える

Template:

```asm
org 0x0000
RAM   equ 0x8000
VRAM  equ 0xC000
INPUT equ 0xC400

start:
    ld sp,0xBFFF
    ; initialize

main_loop:
    ; input → update → draw
    halt
    ; jp main_loop
```

## Exercise 1: Counter

### Goal

Aを5から0へ減らし、0でHALTします。

### Checkpoint

- DEC後のAとZ
- JRを取る時/取らない時のPC
- Breakpointで各Iterationを停止

### Extension

初期値をRAM `8000`から読む版へ変更します。

## Exercise 2: Pixel Painter

### Goal

計算した3つのVRAM Addressへbyte Patternを書き、3箇所を表示します。

### Checkpoint

- HL before/after
- Memory Write Address/Data
- Changed PixelとInspector
- Source Execution Overlay

### Extension

Subroutine`draw_byte`を作り、HLとAを使って`LD (HL),A`を実行します。CALL前にSPを初期化します。

## Exercise 3: Pongへつなぐ

まず[`examples/pinpon.asm`](../../examples/pinpon.asm)を開きます。

```console
zig build run -- tui examples/pinpon.asm
```

`Ctrl+E`でRun、`Ctrl+5`でDisplay、EscapeでPauseします。固定PaddleとBallは意図的に無限Loopします。

### 読む順序

1. StartでPaddleとBallを描く
2. HLがBall Address、Bが端までのCounter
3. Delay LoopのC
4. RAM `8000`のDirection
5. `CP 0`と`JR Z,move_left`

### Challenges

- Ball Pattern`0x18`を`0x3C`へ変える
- Delay初期値またはLoop構造を変える
- Paddle Addressを内側へ1 Column移動する
- Memory Write FilterでVRAM Writeだけを観察する

現在は実時間Game Key入力がないためPaddleは固定です。CLI Debuggerでは`input 0x11`のように`C400`を設定できますが、継続GameのRealtime操作ではありません。

## Exercise 4: Game of Lifeへつなぐ

[`examples/game_of_life.asm`](../../examples/game_of_life.asm)はBlinkerの2 Generationを交互に描きます。

```console
zig build run -- tui examples/game_of_life.asm
```

一般的なNeighbor Count Engineではなく、現在の命令Subsetで学べるよう縦`0x38`と横3 byteの`0x10`を事前計算しています。

### Challenges

- Center Addressを変更する
- Vertical Patternを別の3 bitへ移動する
- Delay OuterのBを変更して見かけの速度を比べる
- Pauseして1 Generation分をStepし、全VRAM Writeを表にする

Delay Loopは特定MHzの実Clockを再現しません。Host性能、UI Tick、描画量で見かけの速度は変わります。

## IDE Tips

- 通常はStep、Loop全体を見る時だけRun/Continue。
- SourceでBreakpoint、BusでFilter、DisplayでInspectorを組み合わせる。
- `Ctrl+P`: Assemble、View、Overlay設定を探す。最初からRunする操作は`Ctrl+E`。
- `Ctrl+S`: 小さなCheckpointごとに保存してAssemble。
- `disasm`: 各CheckpointでSourceと生成Bytesを照合。

## 利用フェーズでのFeedback

```text
Environment: OS / terminal / Zig version / terminal size
Goal:        書こうとしたProgram、学ぼうとした概念
Steps:       正確なCommandとKey
Expected:    期待した表示や動作
Actual:      Output、Diagnostic、Terminal状態
Artifact:    最小.asmと必要ならScreenshot
Learning UX: どのPane間の関係が読めなかったか
```

[← 前](07-bus.ja.md) | [目次](README.ja.md) | [次: Reference →](09-reference.ja.md)
