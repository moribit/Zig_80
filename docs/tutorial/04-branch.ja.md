# 04 比較・分岐・Loop: PCを選ぶ

[← 前: Memory](03-memory.ja.md) | [目次](README.ja.md) | [English](04-branch.md) | [次: Stack →](05-stack.ja.md)

## この章で見る画面

- **Source**: Label、`DEC`、`CP`、`JR`、`JP`
- **CPU**: PC、Counter Register、Z Flag
- **Bus**: 同じ命令Addressが繰り返される様子
- **Breakpoint**: Loop途中で停止する

## この章のゴール

- Labelと実Addressを対応付ける
- Z Flagで次のPCが選ばれる様子を見る
- 有限Loopと無限Loopを安全に扱う

## Z80の仕組み

分岐命令は通常の次PCを別Addressへ置換します。条件分岐は以前の命令が設定したFlagを読み、Source Registerを直接調べません。

## CLIで試す

[Counter Solution](solutions/counter.asm)を使います。

```console
zig build run -- asm docs/tutorial/solutions/counter.asm -o zig-out/counter.bin
zig build run -- debug zig-out/counter.bin
```

## TUIで観察する

```console
zig build run -- tui docs/tutorial/solutions/counter.asm
```

### Counter Loop

```asm
org 0x0000
start:
    ld b,3
loop:
    dec b
    jr nz,loop
    halt
```

### 命令ごとの観察

```text
Step 1  LD B,3       B=03, PC advances
Step 2  DEC B        B=02, Z=0
Step 3  JR NZ,loop   condition true, PC returns to DEC
Step 4  DEC B        B=01, Z=0
Step 5  JR NZ,loop   returns again
Step 6  DEC B        B=00, Z=1
Step 7  JR NZ,loop   condition false, PC advances
Step 8  HALT
```

`JR NZ`自身はBを調べません。直前の`DEC B`が設定したZ Flagを読みます。

## JPとJR

- `JP label`: 16 bit絶対Address。無条件、Z、NZに対応
- `JR label`: 次の命令から-128〜+127 byteの相対Offset。無条件、Z、NZに対応

近いLoopには短いJR、遠い場所にはJPを使えます。JR範囲外ではAssemblerがDiagnosticと`JP`を使うHintを表示します。

### BreakpointでLoopを止める

1. `DEC B`行へ編集Cursorを置く
2. `Ctrl+B`で`●`を付ける
3. `Ctrl+E`でResetしてRun
4. `[BREAKPOINT]`で止まったらBとPCを見る
5. `Ctrl+T`でDECだけを実行
6. `Ctrl+Space`で次のBreakpointまでContinue

Breakpointは生成された命令開始Addressへ設定されます。CommentやLabelだけの行には設定できない場合があります。再AssembleでAddressが動く点にも注意します。

## 無限Loopと実行上限

```asm
forever:
    jp forever
```

Game Loopでは無限Loopが正常です。TUIは1 UI tick最大500命令で協調実行し、EscapeでPauseできます。既定の総上限は10,000,000命令または100,000,000 T-stateです。ResetはCounterを戻し、上限到達後も明示的なStepは1命令だけ実行できます。

CLIでは上限を指定できます。

```console
zig build run -- run program.bin --max-instructions 1000 --max-cycles 10000
```

## IDE Tips

- `Ctrl+B`: Source Breakpoint切替。
- `Ctrl+Space`: Pause位置からContinue。
- `Esc`: 無限LoopをPause。
- `Ctrl+F`: Label名をSearch。
- `Ctrl+]`またはLabel上のEnter: 定義へJump。
- `Alt+Left` / `Alt+Right`: Jump履歴を戻る/進む。

## Challenge: Loop回数を変える

Bの初期値を5へ変更します。RunせずStepし、`DEC`が何回、`JR`が何回実行されるか予想してください。次にBreakpointを使い、Continueを繰り返してBだけを記録します。

[← 前](03-memory.ja.md) | [目次](README.ja.md) | [次: Stack →](05-stack.ja.md)
