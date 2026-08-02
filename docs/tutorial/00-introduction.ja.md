# 00 はじめに: IDEを学習装置として使う

[目次](README.ja.md) | [English](00-introduction.md) | [次: CPUと命令 →](01-cpu.ja.md)

## この章で見る画面

- **Source**: Assembly SourceとCurrent PC
- **CPU**: PCと実行状態
- **Instruction**: 現在命令のAddress、Opcode、長さ、Timing
- Display、Bus、Logic Analyzerはまだ詳しく読みません

## この章のゴール

- Zig_80をBuildしてTUIを開く
- 画面上で「次に実行される命令」を見つける
- RunではなくStepを使って1命令だけ進める

## 1. 準備

必要なものはmacOSまたはLinux、Git、Zig 0.16系、ANSI/VT100互換Terminalです。TUIには80×24以上を推奨します。外部TUI LibraryやC Libraryは不要です。

```console
zig version
zig build
zig build test
zig build run -- --help
```

`zig build run --`の`--`より後ろは、Zig Build SystemではなくZig_80へ渡されます。Build後は`./zig-out/bin/zig80`を直接実行しても構いません。

## 2. 最小Programを開く

```console
zig build run -- tui examples/halt.asm
```

Sourceは起動直後に自動Assembleされます。画面で次を探してください。

1. Source Gutterの`▶`: Current PC
2. CPU Cardの`PC 0000`
3. Instruction Cardの`HALT`
4. Status Barの`[ASSEMBLED]`

Source Markerは別々の意味を持ちます。

| Marker | 意味 |
|---|---|
| `┃` | 文字を編集するCursor |
| `▶` | CPUが次に実行する命令 |
| `▲` | 直前に実行した命令 |
| `●` | Breakpoint |
| `!` | Assembler Diagnostic |

編集CursorとCurrent PCが同じ行にあっても、同じものではありません。

## 3. 最初のStep

`Ctrl+T`を1回だけ押します。

### Step 1で追う順序

```text
Source          HALT行がLast Executedになる
   ↓
PC              0000 → 0001
   ↓
Instruction     HALTをdecodeした情報
   ↓
CPU state       HALTED
   ↓
Bus             Opcode Fetch event
   ↓
Display         変化なし
```

この「上から順に見る」習慣がCourse全体の基本です。変化した値は約300 ms強調されるため、最初は強調箇所だけを追います。

## CPUは何をしたのか

CPUはMemoryのAddress`0000`からbyteを読み、`0x76`を`HALT`として解釈しました。1 byteを読んだためPCは`0001`へ進み、CPUは停止状態になりました。

```text
halt  ── assembler ──>  76
human-readable         CPU-readable
```

1 byteは8 bit、16進数で`00`〜`FF`です。Z80のAddressは16 bitなので`0000`〜`FFFF`、合計65,536 byteを指定できます。

## IDE Tips

- `Ctrl+T`: 1命令Step。学習中の基本操作です。
- `Ctrl+1`: Source Viewへ切替。
- `Ctrl+2`: CPU Viewへ切替。
- `Ctrl+P`: Command Palette。Keyを忘れたらここから`step`を選べます。
- `Ctrl+Q`: Quit。未保存変更がある場合は2回押します。

## Challenge: NOPを1つ追加する

`halt`の前に`nop`を追加し、`Ctrl+R`で再Assembleしてください。Reset後に2回Stepし、NOP後のPCとHALT後のPCを予想してから確認します。

```asm
start:
    nop
    halt
```

NOPは何もしませんが、Opcode FetchとPCの進行は発生します。

[目次](README.ja.md) | [次: CPUと命令 →](01-cpu.ja.md)

