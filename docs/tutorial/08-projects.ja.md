# 08 小さなProject: 学んだ流れを組み合わせる

[← 前: Logic Analyzer](07-bus.ja.md) | [目次](README.ja.md) | [English](08-projects.md) | [リファレンス](../reference/README.ja.md)

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

### Goal（目標）

Aを5から0へ減らし、0でHALTします。

### PrerequisiteとStarter

02章と04章を終え、[Starter File](starters/counter.asm)をCopyします。

### Expected Behavior

Aが5→4→3→2→1→0、0でZがSet、最後のJRは分岐せずHALTします。

### Verification（検証）

```console
zig build run -- asm counter.asm -o zig-out/counter.bin
zig build run -- disasm zig-out/counter.bin
zig build run -- test zig-out/counter.bin
```

TUIではDECへBreakpointを置き、各VisitのAを記録します。

### Hint、Solution、Extension

- DEC後のAとZ
- JRを取る時/取らない時のPC
- Breakpointで各Iterationを停止

Hintは`DEC A`と`JR NZ,loop`です。[Solution](solutions/counter.asm)と比較します。初期値をRAM `8000`から読む版、またはBをCounterにする版へ拡張します。

## Exercise 2: Pixel Painter

### Goal（目標）

計算した3つのVRAM Addressへbyte Patternを書き、3箇所を表示します。

### PrerequisiteとStarter

03、06、07章を終え、[Starter File](starters/pixel.asm)をCopyします。

### Expected BehaviorとVerification

最初のWriteはAddress `C08A`、bit 1、Data `02`です。Assembleして`run --screen`、次にTUIでStepし、以下を検証します。

- HL before/after
- Memory Write Address/Data
- Changed PixelとInspector
- Source Execution Overlay

### Hint、Solution、Extension

式`C000 + (y/8)*128+x`を使い、[Solution](solutions/pixel.asm)と比較します。3 Pixelへ増やし、Subroutine`draw_byte`を作って`LD (HL),A`を実行します。CALL前にSPを初期化します。

## Exercise 3: Pongへつなぐ

### GoalとPrerequisite

04〜07章の後に、継続移動するBallを理解して変更します。

### StarterとSolution

[`examples/pinpon.asm`](../../examples/pinpon.asm)は動作するStarterであり、現在の自律版Solutionでもあります。

```console
zig build run -- tui examples/pinpon.asm
```

`Ctrl+E`でRun、`Ctrl+5`でDisplay、EscapeでPauseします。固定PaddleとBallは意図的に無限Loopします。

### Expected BehaviorとVerification

BallがHALTせず固定Paddle間を往復します。EscapeでPauseし、Direction RAMとVRAM Writeを確認します。

### Hintと読む順序

1. StartでPaddleとBallを描く
2. HLがBall Address、Bが端までのCounter
3. Delay LoopのC
4. RAM `8000`のDirection
5. `CP 0`と`JR Z,move_left`

### Extension

- Ball Pattern`0x18`を`0x3C`へ変える
- Delay初期値またはLoop構造を変える
- Paddle Addressを内側へ1 Column移動する
- Memory Write FilterでVRAM Writeだけを観察する

Paddleは固定ですが、`Ctrl+G`のGame Input ModeでLeft/Rightを押すとBallの方向を変更できます。CLIでは`--input-script`で同じInput Registerを決定的にReplayできます。

## Exercise 4: Game of Lifeへつなぐ

### GoalとPrerequisite

Display/Branch章の後に、Blinkerの2 Stateを1 Cycle追跡します。

### StarterとSolution

[`examples/game_of_life.asm`](../../examples/game_of_life.asm)は動作するPattern Animation Solutionで、一般Game of Life Engineではありません。

```console
zig build run -- tui examples/game_of_life.asm
```

### Expected BehaviorとVerification

縦/横を無限に交互表示します。Pauseし、1 GenerationをStepしてBusの全WriteとDisplay Pixelを検証します。Neighbor Countではなく縦`0x38`と横3 byteの`0x10`を事前計算しています。

### HintとExtension

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

## Challenge: 1つを検証まで完了する

CounterまたはPixel Painterを選び、Solutionを先にCopyせずGoalからVerificationまで進めます。1命令についてSource、PC、Opcode byte、Register差分、Bus Event、画面またはMemory結果を記録してください。

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

[← 前](07-bus.ja.md) | [目次](README.ja.md) | [リファレンス](../reference/README.ja.md)
