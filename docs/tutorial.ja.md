# Zig_80 入門チュートリアル

[English](tutorial.md)

このチュートリアルは、Z80、アセンブリ言語、CPUハードウェアの経験がないプログラマーを対象にしています。Zig_80を使い、短いプログラムを機械語へ変換し、CPU、メモリ、Bus、Displayの変化を観察するところまでを段階的に学びます。

Zig_80は現在も学習用MVPです。実Z80の完全な再現ではなく、対応命令も限定されています。本書では、現在のリポジトリで実行できる範囲を「現在のZig_80」、一般的なZ80や将来の実機構想を「実Z80」または「将来構想」と表記します。

## このチュートリアルでできるようになること

最後まで進むと、次の流れを自分で繰り返せるようになります。

```text
Assembly source (.asm)
        │ assemble
        ▼
Machine code ROM (.bin)
        │ load
        ▼
Virtual Machine
  CPU ── Bus ── Memory
               ├─ RAM
               ├─ VRAM ── Display
               └─ Input
        │ observe
        ▼
CLI debugger / Zig_80 IDE
```

- Z80のレジスタ、メモリ、PC、SP、フラグの役割を説明する
- `LD`、算術、比較、分岐、Call、Stackを使った小さなROMを書く
- CLIでassemble、disassemble、run、debug、testを使い分ける
- TUIでSource、CPU、Instruction、Bus、Displayを関連付けて読む
- 128×64、1bppのVRAMへPixelを描く
- 入力レジスタをDebuggerから操作する
- 無限Loopを安全にPauseし、Breakpointや実行上限を使う
- 「論理Bus Event」と実機の電気的・cycle-accurateな波形を区別する

## 1. 準備

### 必要なもの

- macOSまたはLinux
- Git
- Zig 0.16系
- ANSI/VT100互換Terminal（TUIには80×24以上を推奨）

外部ライブラリ、ncurses、Cライブラリは必要ありません。使用中のZigを確認します。

```console
zig version
```

出力が`0.16.x`でない場合は、Zig公式配布物または利用中のVersion Managerで0.16系へ切り替えてください。Zigは開発中の言語であり、異なるVersionでは標準Library APIやBuild APIが一致しない場合があります。

### BuildとTest

Repository直下で実行します。

```console
zig build
zig build test
zig build run -- --help
```

`zig build run --`の最初の`--`は、後続引数をBuild SystemではなくZig_80へ渡す区切りです。Build後は、同じ操作を生成済みBinaryへ直接渡すこともできます。

```console
./zig-out/bin/zig80 --help
```

本書では変更直後にも確実にBuildされる`zig build run -- ...`を基本表記にします。

## 2. CPUを初めて見る

### CPU、命令、機械語

CPUはMemoryから数値を読み、その数値を命令として解釈して実行します。例えばZ80では`0x76`が`HALT`です。人間が書く`halt`を、CPUが読む`0x76`へ変換するToolがAssemblerです。

```text
halt        Assembly instruction
  │ assembler
  ▼
76          Machine-code byte
```

1 byteは8 bitで、`00000000`から`11111111`、16進数では`00`から`FF`を表します。2 byteを組み合わせると16 bitとなり、`0000`から`FFFF`を表せます。Z80のAddress空間は16 bitなので、CPUから見えるMemoryは最大65,536 byteです。

### 最小のProgram

既存の`examples/halt.asm`を確認します。

```asm
org 0x0000
start:
    halt
```

- `org 0x0000`は、次の命令の論理Addressを`0000`にします。
- `start:`はAddressに名前を付けるLabelです。CPUにはLabel名は入りません。
- `halt`はCPUを停止状態にします。

Assembleします。

```console
zig build run -- asm examples/halt.asm -o zig-out/halt.bin
```

逆AssemblerでBinaryを読み戻します。

```console
zig build run -- disasm zig-out/halt.bin
```

実行します。

```console
zig build run -- run zig-out/halt.bin
```

停止理由、実行命令数、T-state、停止後のPCを確認してください。PCはProgram Counterで、次に読む命令のAddressを保持します。`HALT`は1 byteなので、開始時`0000`だったPCは`0001`へ進みます。

### Fetch、Decode、Execute

命令実行は概念的に次の順で進みます。

1. Fetch: PCが示すMemoryからOpcodeを読む
2. Decode: Opcodeがどの命令か判定する
3. Execute: RegisterやMemoryを変更する
4. PCを次の命令へ進める、または分岐先へ変更する

Zig_80のStepは命令単位です。返されるT-state数は命令Timingですが、Bus Viewerが表示する各Eventは実Z80の各T-stateへ分解した電気信号ではありません。

## 3. Registerで計算する

### Registerとは

RegisterはCPU内部にある小さく高速な保存場所です。現在のZig_80でよく使う8 bit Registerは`A B C D E H L F`、組にした16 bit Registerは`AF BC DE HL`です。

| Register | 主な用途の考え方 |
|---|---|
| `A` | Accumulator。算術や比較の中心 |
| `F` | Flags。直前の演算結果の性質 |
| `B`, `C` | Counterや一時値。組にすると`BC` |
| `D`, `E` | 一時値。組にすると`DE` |
| `H`, `L` | 組にした`HL`をMemory Addressとしてよく使う |
| `PC` | 次に実行する命令Address |
| `SP` | Stack先頭を示すStack Pointer |

Registerの用途は多くの場合Conventionであり、`B`を必ずCounterにしなければならないわけではありません。ただし命令によって使えるRegisterの組み合わせは決まっています。

### 加算Program

`examples/add.asm`は10と20を加算します。

```asm
org 0x0000
start:
    ld a, 10
    ld b, 20
    add a, b
    halt
```

`LD`はLoadです。ここではMemory Addressではなく即値をRegisterへ入れます。`ADD A,B`は`A ← A + B`です。

```console
zig build run -- asm examples/add.asm -o zig-out/add.bin
zig build run -- disasm zig-out/add.bin
zig build run -- debug zig-out/add.bin
```

Debuggerで次を試します。

```text
zig80> registers
zig80> step
zig80> step
zig80> step
zig80> registers
zig80> quit
```

3回目のStep後、`AF`の上位byte、つまり`A`が`1E`になっていることを確認します。`0x1E`は10進数の30です。

### Flagを読む

`F`の各bitは演算結果を記録します。Zig_80のCPU Panelでは次を個別表示します。

| Flag | 意味 | 初学者向けの読み方 |
|---|---|---|
| `S` | Sign | 結果の最上位bitが1 |
| `Z` | Zero | 結果が0 |
| `H` | Half Carry | 下位4 bitからCarry/Borrow |
| `PV` | Parity/Overflow | 命令に応じたParityまたは符号Overflow |
| `N` | Add/Subtract | 減算系なら1 |
| `C` | Carry | 8 bit/16 bitの範囲外へのCarry/Borrow |

最初は`Z`と`C`に注目すると理解しやすくなります。例えば`CP 4`はAを変更せず、内部的に`A - 4`相当のFlagだけを設定します。等しければ`Z=1`となり、`JR Z,label`が分岐します。

## 4. MemoryとAddress

### Memoryは番号付きのbyte列

Memoryを巨大なbyte配列と考えます。各byteにはAddressがあります。

```text
Address   8000  8001  8002  8003
Value       2A    00    FF    10
```

括弧は「Register値や数値そのもの」ではなく「その値をAddressとしてMemoryへAccessする」ことを表します。

```asm
ld hl, 0x8000    ; HLへ8000を入れる
ld (hl), 0x2A    ; Address 8000へ2Aを書く
ld a, (hl)       ; Address 8000からAへ読む
```

現在のAssemblerで使える代表的なMemory形式は次です。

```asm
ld a,(hl)
ld (hl),a
ld (hl),42
ld a,(0x8000)
ld (0x8000),a
ld hl,(0x8000)
ld (0x8000),hl
```

### Little Endian

Z80は16 bit値をMemoryへ置くとき下位byteを先に置きます。これをLittle Endianと呼びます。

```text
HL = 0x1234

Address 8000 = 34  low byte
Address 8001 = 12  high byte
```

Debuggerの`memory 0x8000 2`で、この並びを確認できます。

### Zig_80 MachineのMemory Map

| Address | 用途 |
|---|---|
| `0000-7FFF` | Program領域。Binaryを`0000`からLoad |
| `8000-BFFF` | General RAM |
| `C000-C3FF` | Video RAM (VRAM) |
| `C400` | Input状態 |
| `C401-C402` | Frame Counter、Little Endian |
| `C403` | Pseudo-random値 |
| `C404-FFFF` | Reserved RAM |

これはZig_80独自のMachine仕様です。市販されていた全てのZ80 Computerに共通するMapではありません。同じZ80 CPUでも、Memory MapはMachine設計者が決めます。

また、現在のMVPではProgram領域を書込み保護していません。「ROM」と呼ぶ場合も、仮想Machine上では書込み可能なMemoryです。

## 5. 比較、分岐、Loop

次のProgramを`counter.asm`として作成してみます。

```asm
org 0x0000

start:
    ld b,5
loop:
    dec b
    jr nz,loop
    halt
```

`DEC B`でBを1減らし、結果が0なら`Z=1`になります。`JR NZ,loop`はZeroでない間だけ戻ります。そのためLoopは有限です。

```console
zig build run -- asm counter.asm -o zig-out/counter.bin
zig build run -- debug zig-out/counter.bin
```

Debuggerで`step`と`registers`を交互に実行し、BとZの変化を観察します。

### JPとJRの違い

- `JP label`: 16 bitの絶対AddressへJump。現在のZig_80では無条件、Z、NZに対応
- `JR label`: 次の命令から-128〜+127 byte範囲の相対Jump。無条件、Z、NZに対応

近いLoopには短い`JR`、遠いLocationや範囲を気にしたくない場合は`JP`が使えます。`JR`範囲外ではAssemblerが行・列とHintを持つDiagnosticを返します。

### 無限Loop

```asm
forever:
    jp forever
```

CPUにとって無限Loopは異常ではありません。Game Loopや待機処理にも使います。一方、CLIの`run`が無制限だとShellへ戻れないため、Zig_80には命令数とT-stateの安全上限があります。

```console
zig build run -- run zig-out/counter.bin --max-instructions 1000 --max-cycles 10000
```

TUIは1 UI tickあたり最大500命令を協調実行し、EscapeでPauseできます。既定の総上限は10,000,000命令または100,000,000 T-stateです。

## 6. SubroutineとStack

### CALLとRET

繰り返し使う処理をSubroutineにできます。

```asm
org 0x0000

start:
    ld sp,0xBFFF
    ld a,1
    call twice
    halt

twice:
    add a,a
    ret
```

`CALL twice`は、戻り先AddressをStackへ保存して`twice`へJumpします。`RET`はStackから戻り先を取り出してPCへ戻します。

### SPを初期化する理由

StackはRAMの一部をLIFO（Last In, First Out）として使います。`SP`はStack先頭を指し、Z80 Stackは低いAddress方向へ伸びます。Zig_80のReset直後のSPは`FFFF`ですが、Subroutineを使うProgramではGeneral RAM末尾の`BFFF`などへ明示的に設定すると、VRAMやReserved領域との衝突を避けやすくなります。

```asm
ld sp,0xBFFF
```

### PUSHとPOP

Register Pairを一時保存できます。

```asm
push af
push hl
; AFやHLを使う処理
pop hl
pop af
```

後にPushしたものから逆順にPopします。現在対応するPairは`AF BC DE HL`です。PushとPopの数や順番を間違えると、`RET`が誤ったAddressへ戻る原因になります。

## 7. 最初のPixelを描く

`examples/pixel.asm`を使います。

```asm
org 0x0000
VRAM equ 0xC000
start:
    ld hl, VRAM
    ld (hl), 0x01
    halt
```

`equ`はSymbolへ定数値を割り当てます。`VRAM`という名前自体はBinaryへ残らず、Assemblerが`C000`へ置換します。

```console
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
```

画面左上にPixelが表示されます。Terminal Rendererは上下2 Pixelを1文字へまとめるため、上Pixelだけなら`▀`になります。

### VRAMのPage Layout

画面は128×64、1bppです。1 Pixelにつき1 byteではなく、1 byteの各bitが縦8 Pixelを表します。

```text
VRAM address = C000 + (y / 8) * 128 + x
bit          = y % 8
mask         = 1 << bit
```

例:

| Pixel | Address | Bit | 書く値 |
|---|---:|---:|---:|
| `(0,0)` | `C000` | 0 | `01` |
| `(0,1)` | `C000` | 1 | `02` |
| `(0,7)` | `C000` | 7 | `80` |
| `(0,8)` | `C080` | 0 | `01` |
| `(64,4)` | `C040` | 4 | `10` |

同じbyteに属する複数Pixelを保持するには、通常は既存値とBit MaskをORします。ただし現在のZig_80 Assembler/CPUは`OR`をまだ実装していません。教材Exampleでは完成したbyte Pattern（`0x18`や`0x38`）を直接書いています。

## 8. Zig_80 IDEで命令を追う

### 起動

```console
zig build run -- tui examples/pixel.asm
```

空でないSourceは起動時に自動Assembleされ、成功するとMachineへLoadされます。編集すると`Dirty`になりますが、毎Key入力では再Assembleしません。

### 最初の3 Step

1. `Ctrl+T`で`LD HL,VRAM`をStepする
2. CPUでHLが`0000 ↓ C000`となることを確認する
3. Source右側のExecution Overlayで`HL ← C000`を見る
4. 再び`Ctrl+T`で`LD (HL),01`を実行する
5. BusでMemory Write、Displayで変更Pixelを見る
6. もう一度`Ctrl+T`でHALTする

同じ命令を複数Paneから見ることが重要です。

```text
Source      どの命令を書いたか
Instruction Opcode、長さ、Timing、説明
CPU         RegisterとFlagがどう変わったか
Bus         どのAddressを論理的にRead/Writeしたか
Display     VRAM WriteがどのPixelになったか
```

### Source Pane

Gutterの記号は独立しています。

| Marker | 意味 |
|---|---|
| `┃` | 編集Cursor |
| `▶` | Current PC |
| `●` | Breakpoint |
| `!` | Diagnostic |
| `▲` | Last Executed |

AddressとBytesは最後に成功したAssemble結果です。編集後にDirtyな場合、表示されるMachineとSourceが一致しない可能性があります。`Ctrl+R`でMemory上のSourceを再Assemble、`Ctrl+S`で保存してから再Assembleします。

### 基本操作

| Key | Action |
|---|---|
| `Ctrl+R` | Assemble |
| `Ctrl+E` | ResetしてRun |
| `Ctrl+T` | 1命令Step |
| `Ctrl+Space` | Continue |
| `Esc` | PauseまたはInput modeをCancel |
| `Ctrl+B` | Source Breakpoint切替 |
| `Ctrl+P` | Command Palette |
| `Ctrl+S` | Save |
| `Ctrl+Q` | Quit |
| `Ctrl+1..5` | Source、CPU、Memory、Bus、Display |

未保存のSourceでQuitすると、誤操作防止のため2回目の`Ctrl+Q`が必要です。詳細なEditor、Memory、Bus、Display操作は[TUIガイド](tui.ja.md)を参照してください。

## 9. Breakpointを使う

`examples/add.asm`をTUIで開きます。

```console
zig build run -- tui examples/add.asm
```

1. Cursorを`add a,b`行へ置く
2. `Ctrl+B`でBreakpointを追加する
3. `Ctrl+E`でRunする
4. `BREAKPOINT`で停止したらAとBを確認する
5. `Ctrl+T`でAddだけをStepする

Breakpointは命令開始Addressに設定されます。Comment、空行、Labelだけの行には生成Addressがない場合があります。Sourceを再Assembleした後は、命令Addressが変わる可能性にも注意してください。

CLI Debuggerでは次のようにAddressを直接指定します。

```text
break 0x0004
continue
delete 0x0004
```

## 10. BusとLogic Analyzerを読む

BusはCPU、Memory、周辺機器の間でAddressやDataを運ぶ接続です。実機Z80にはAddress線、Data線、Control線があり、電圧のHigh/Lowが時間とともに変化します。

Zig_80は現在、命令実行中に観測した次の論理AccessをEventとして記録します。

- Opcode Fetch
- Operand Read
- Memory Read
- Memory Write
- 将来用のI/O Read/Write、Refresh種別

Bus Paneは命令単位のCardとLogic Analyzerを表示します。`[`と`]`でEvent選択、Endで最新Event追従、EnterでSourceへ移動します。`+`/`-`でZoom、`f`でFit、`<`/`>`でPanできます。

> Bus Waveformは、命令実行中に観測された論理的なバスアクセスを等幅イベントとして可視化したものです。実Z80の電気的タイミングや各T-stateの長さを再現するものではありません。

- 横軸は「Event順序」で、秒や実クロックではありません。
- `t_state_start`はEvent発生時刻ではなく命令開始時の総T-stateです。
- `t_state_count = 0`は未計測の論理Modelを意味します。
- `/MREQ`、`/RD`、`/WR`のSlashはActive Lowを表します。
- Pulse幅から実機Timingを推測してはいけません。

この区別は、将来Logic AnalyzerやOscilloscopeで実機を観測するときに重要です。

## 11. Inputを試す

Zig_80 Machineでは`C400`がInput Registerです。

| Bit | Mask | Input |
|---:|---:|---|
| 0 | `01` | Up |
| 1 | `02` | Down |
| 2 | `04` | Left |
| 3 | `08` | Right |
| 4 | `10` | A |
| 5 | `20` | B |
| 6 | `40` | Start |
| 7 | `80` | Reserved |

複数ButtonはMaskを足す（bitwise ORする）ことで同時指定できます。例えばUp+Aは`0x11`です。現在のCLI Debuggerでは次のように設定します。

```text
zig80> input 0x11
zig80> memory 0xC400 1
```

`examples/moving_pixel.asm`は`C400`を読み、値が`4`（Left）ならHLを減らします。ただしProgramは毎回同じ開始LocationからLoadされ、1回移動してHALTします。現在のTUIは実時間Game Key入力をまだ提供していないため、入力学習にはCLI Debuggerの`input`を使ってください。

## 12. 継続動作するProgramを見る

### Pinpon

```console
zig build run -- tui examples/pinpon.asm
```

`Ctrl+E`でRunし、`Ctrl+5`でDisplayを開きます。Ballが固定Paddle間を往復します。ProgramにはHALTがなく、Game Loopが継続します。EscapeでPauseし、`Ctrl+T`で個々の命令を確認できます。

### Game of Life Blinker

```console
zig build run -- tui examples/game_of_life.asm
```

このExampleは一般的なNeighbor計算を実装せず、縦と横の2 Patternを交互に書くことでBlinkerのGenerationを可視化します。これは現在の命令Subset内で継続動作とVRAM更新を学ぶ教材です。

### Delay LoopはClockではない

ExampleのDelayは`DEC`と`JR`を多数実行し、TUI上で変化を見やすくしています。しかしTUIのRunは「実Z80を特定MHzでリアルタイム再現する」Schedulerではありません。Host性能、UI tick、描画量で見かけの速度が変わります。3.5 MHzなどの実Clockを想定した時間保証はありません。

## 13. Assembler Syntax Reference

### Number、Symbol、Expression

```asm
42              ; decimal
0x2A            ; hexadecimal
0b101010        ; binary
'A'             ; one-byte character literal
$               ; current logical address
VRAM + 64       ; simple addition
end - start     ; simple subtraction
```

式は現在、単純な`+`または`-`を再帰的に評価します。括弧による算術優先順位、乗除算、一般的なBit演算はありません。16 bitを超える値や8 bit即値に`0x100`を使うと範囲Diagnosticになります。

LabelとSymbolは大文字小文字を区別せず参照できます。重複定義はErrorです。

```asm
start:
VRAM equ 0xC000
```

### Directive

```asm
org 0x0000
db 1,2,0xFF
db "HELLO",0
dw 0x1234,start
VALUE equ 42
```

- `org`は論理PCを変更しますが、出力FileをAddressまでPaddingしません。
- `db`はbyteを出力し、Stringも使用できます。
- `dw`は16 bit wordをLittle Endianで出力します。
- `equ`は定数Symbolを定義し、byteを出力しません。

複数の離れた`org` Segmentを1つのFlat Binaryへ配置するLinker形式ではありません。入門Programは`org 0x0000`から連続して配置してください。

### 現在対応する命令形式

```text
NOP                 HALT                RET
JP address          JP Z,address        JP NZ,address
JR address          JR Z,address        JR NZ,address
CALL address
PUSH AF|BC|DE|HL    POP AF|BC|DE|HL
INC A|B|C|D|E|H|L|HL
DEC A|B|C|D|E|H|L|HL
ADD A,r8            ADD A,n8
SUB r8              SUB n8
CP r8               CP n8
LD r8,n8            r8 = A|B|C|D|E|H|L
LD r16,n16          r16 = BC|DE|HL|SP
LD A,(HL)           LD (HL),A           LD (HL),n8
LD A,(address)      LD (address),A
LD HL,(address)     LD (address),HL
```

Source補完は学習用にこれより広いZ80語彙を提示する場合があります。`LDI`、`IX`、`IY`、prefix命令、interrupt、I/O命令などは現在未実装です。候補に表示されたことを実装済みの保証と考えず、上記一覧とAssembler Diagnosticを基準にしてください。

## 14. CLIを使い分ける

| Command | いつ使うか |
|---|---|
| `asm` | SourceからROM Binaryを作る |
| `disasm` | BinaryのAddress、Bytes、命令を確認する |
| `run` | HALTまたは上限まで高速に実行する |
| `debug` | REPLでStep、Memory、Breakpoint、Inputを操作する |
| `test` | 100,000命令以内にHALTすることを簡易確認する |
| `explain` | Source各命令のEncodeを短く確認する |
| `tui` | Source、CPU、Bus、Displayを同時観察・編集する |

標準的な反復は次です。

```console
zig build run -- asm my_program.asm -o zig-out/my_program.bin
zig build run -- disasm zig-out/my_program.bin
zig build run -- test zig-out/my_program.bin
zig build run -- tui my_program.asm
```

意図的な無限Loopは`test`に成功しません。これはProgramの失敗ではなく、`test`が「HALTするか」だけを検証するCommandだからです。継続ProgramにはTUIのPause、Breakpoint、実行上限を使います。

## 15. Diagnosticの読み方

Assembler Errorでは、File、Line、Column、対象Source、Caret、Hintが表示されます。

```text
game.asm:18:5: error: JR target is out of range

    jr game_loop
    ^^^^^^^^^^^^
```

よくある原因:

| Diagnostic | 確認すること |
|---|---|
| Invalid mnemonic | Spell、現在対応する命令一覧 |
| Invalid operand | Registerの組合せ、Comma、括弧 |
| Undefined symbol | Label Spell、定義Location |
| Duplicate symbol | 同名Labelまたは`equ`が2つないか |
| Value out of range | 8 bit値は0〜255、16 bit値は0〜65535 |
| JR out of range | `JP`への変更、Code配置 |
| Invalid expression | 未対応Operator、空のOperand |
| Unterminated string | `db "..."`の閉じQuote |
| Invalid character literal | 文字Literalが正確に`'A'`形式か |

TUIではDiagnostic Marker `!`とInline Messageを表示し、Diagnostic上のEnterで対象行へ移動できます。Assemblerは現在最初のErrorで停止するため、1件を直して再Assembleすると次のErrorが現れる場合があります。

## 16. 自分のProgramを始めるTemplate

```asm
; my_program.asm
org 0x0000

RAM   equ 0x8000
VRAM  equ 0xC000
INPUT equ 0xC400

start:
    ld sp,0xBFFF

    ; Initialize registers and memory here.

main_loop:
    ; Read input, update state, then draw.

    halt               ; 入門中は有限実行にする
    ; jp main_loop      ; 継続ProgramにするときHALTと置換
```

最初から大きなGameを書かず、次の順で増やします。

1. HALTだけをAssemble/Runする
2. Registerへ定数をLoadする
3. RAM 1 byteを書いてDebuggerで確認する
4. VRAM 1 byteを書いてDisplayを見る
5. 有限Loopを追加する
6. Subroutineを追加しSPを初期化する
7. 最後にMain Loopを無限化し、Breakpointを置く

各段階で`disasm`を実行すると、Sourceと生成byteの対応が崩れたLocationを早く見つけられます。

## 17. 演習

### 演習1: RegisterとFlag

`A=255`へ1を加え、A、Z、Cがどうなるか予想してからStepしてください。

Hint: `ld b,1`と`add a,b`を使えます。

### 演習2: RAMとLittle Endian

HLへ`0x1234`を入れ、`0x8000`へ保存してください。Debuggerで2 byteを表示し、`34 12`になることを確認します。

Hint: `ld (0x8000),hl`。

### 演習3: 条件分岐

Aを3から1ずつ減らし、0になったらHALTするProgramを書いてください。

Hint: `dec a`、`jr nz,label`。

### 演習4: Pixel座標

Pixel `(10,9)`のVRAM Address、bit、Maskを計算し、描画してください。

答えを確認する前に式へ代入してください。

```text
address = C000 + (9 / 8) * 128 + 10 = C08A
bit     = 9 % 8 = 1
mask    = 02
```

### 演習5: 命令の流れ

演習4をTUIでStepし、次を1つの表へ記録してください。

- Source Line
- PC
- Opcode Bytes
- HL before/after
- Memory Write Address/Data
- Changed Pixel

この記録が「Source→CPU→Bus→Display」を結び付ける基本です。

## 18. Hardwareへ進む前に

Zig_80の現在の実行環境はSoftware上のVirtual Machineです。本物のZ80、Breadboard、PCBはまだRepositoryの実装対象ではなく、[Vision](vision.ja.md)に記載された将来構想です。

実Hardwareでは、Software Modelにない次の問題が加わります。

- Voltage Level、Current、Power Supply、Ground
- Clock生成とReset Timing
- Address/Data Busの方向とTri-state
- MemoryやPeripheralのChip Select Logic
- Signal Integrity、Decoupling、配線長
- ROM書込みとDebug Interface

実Z80へ進む場合、使用するZ80 Variantと各部品のData Sheetを必ず確認してください。5 V部品と3.3 V MCUを直接接続できるとは限りません。電圧互換性、Bus競合、絶対最大定格を理解せずに配線すると部品を破損する可能性があります。Zig_80の論理Waveformを配線図や電気Timing保証として使用しないでください。

## 19. 現在の制限

- 完全なZ80命令Setではありません。
- CB/DD/ED/FD Prefix、IX/IY、Interrupt、I/O命令は未実装です。
- cycle-accurate、Clock周波数同期、実時間Inputはありません。
- Bus Waveformは等幅の論理Eventです。
- CLI `test`はHALTだけを検査し、Register/Memory Assertion形式はありません。
- TUIはmacOS/LinuxのTerminal向けで、Windows、Mouse、Clipboard、複数Fileは未対応です。
- Program領域は現在書込み保護されません。
- Frame CounterやPseudo-random RegisterはMachine Device更新時の簡易Modelで、実時間Timerではありません。

制限は学習上の境界でもあります。未対応命令へ遭遇したら、既存Subsetで書き換える、Issue/Feedbackとして記録する、Core拡張を別作業として検討する、のいずれかを選びます。

## 20. 利用フェーズでのFeedback

Toolを使いながら改善するため、問題を次の形式で残すと再現しやすくなります。

```text
Environment:
  OS / terminal / Zig version / terminal size

Goal:
  What program were you trying to write?

Steps:
  Exact command and keys

Expected:
  What should have happened?

Actual:
  Output, diagnostic, or restored terminal state

Artifact:
  Minimal .asm source and screenshot if relevant
```

「使いづらい」だけでなく、「どの命令を理解しようとしたとき、どのPane間の関係が読めなかったか」を記録すると、教材兼IDEとしてのUX改善へ直接つながります。

## 21. 次に読む資料

- [TUIガイド](tui.ja.md): Editor、Command Palette、Memory、Bus、Displayの全操作
- [VisionとArchitecture](vision.ja.md): Projectの思想と実機を含む将来像
- [`examples/pixel.asm`](../examples/pixel.asm): 最小Display Program
- [`examples/add.asm`](../examples/add.asm): Register算術
- [`examples/pinpon.asm`](../examples/pinpon.asm): 継続Game Loop
- [`examples/game_of_life.asm`](../examples/game_of_life.asm): 継続VRAM Animation

## 用語集

| 用語 | 意味 |
|---|---|
| Assembly | 人間が読めるMnemonicとOperandによる低Level言語 |
| Assembler | AssemblyをMachine Codeへ変換するTool |
| Opcode | 命令種別を表すbyte |
| Operand | 命令が使うRegister、値、Address |
| Register | CPU内部の保存場所 |
| PC | 次の命令Addressを保持するProgram Counter |
| SP | Stack先頭を保持するStack Pointer |
| Flag | 演算結果のZero、Carryなどを記録するbit |
| RAM | 読書きする作業Memory |
| ROM | 本来は読出し中心のProgram Memory。本書では生成Program BinaryもROMと呼ぶ |
| VRAM | Display内容を保持するVideo Memory |
| Bus | CPU、Memory、Peripheral間でAddress/Data/制御を運ぶ接続 |
| T-state | Z80 Timingを表す基本Clock単位 |
| Little Endian | 多byte値を下位byteから低Addressへ置く方式 |
| Stack | LIFO形式で戻り先や一時値を保存するMemory領域 |
| Label | Addressへ付けるSource上の名前 |
| Immediate | 命令byte列へ直接埋め込まれた値 |
| 1bpp | 1 Pixelを1 bitで表す形式 |

