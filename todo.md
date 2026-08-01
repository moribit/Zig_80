# Zig_80 初期実装依頼

Zigで、Z80を学習・開発するためのCLI統合環境「Zig_80」を新規実装してください。

本プロジェクトは、低レイヤープログラミングやZ80の経験が少ない開発者でも、CPUの状態や命令の動きを観察しながら、Z80アセンブリによるプログラムや簡単なゲームを開発できる環境を目指します。

単なるZ80エミュレーターではなく、以下を統合した教育・開発ツールとして設計してください。

- Zig製Z80エミュレーター
- Zig製Z80アセンブラ
- 逆アセンブラ
- ステップ実行可能なデバッガー
- ターミナル上の仮想ディスプレイ
- Z80プログラムの自動テスト環境
- 将来の実機Z80基板と互換性を持たせられる仮想マシン仕様

今回は全Z80命令を一度に実装するのではなく、拡張可能な設計を優先し、最小限の命令セットでプログラムをアセンブル・実行・描画できるMVPを完成させてください。

---

## 1. 使用技術

- Zig 0.16系
- 外部依存は原則として使用しない
- Zig標準ライブラリを利用する
- macOSおよびLinuxで動作するCLIツールとする
- `zig build`、`zig build test`、`zig build run`で操作できる構成にする
- メモリ管理は明示的に行い、不要な動的確保を避ける
- CPUコアは、将来的にライブラリとして独立利用できる構造にする

Zigのバージョン固有APIについては、実際に使用可能なAPIを確認して実装してください。古いZigの記法を推測で使用しないでください。

---

## 2. プロジェクト構成

責務を以下のように分離してください。

```text
src/
├── main.zig
├── cli/
│   ├── cli.zig
│   ├── asm_command.zig
│   ├── run_command.zig
│   ├── debug_command.zig
│   ├── disasm_command.zig
│   └── test_command.zig
├── cpu/
│   ├── cpu.zig
│   ├── registers.zig
│   ├── flags.zig
│   ├── instruction.zig
│   ├── decoder.zig
│   └── execute.zig
├── assembler/
│   ├── assembler.zig
│   ├── lexer.zig
│   ├── parser.zig
│   ├── expression.zig
│   ├── encoder.zig
│   ├── symbols.zig
│   └── diagnostics.zig
├── disassembler/
│   └── disassembler.zig
├── machine/
│   ├── machine.zig
│   ├── bus.zig
│   ├── memory.zig
│   ├── video.zig
│   ├── input.zig
│   └── timer.zig
├── debugger/
│   ├── debugger.zig
│   ├── breakpoint.zig
│   ├── trace.zig
│   └── tui.zig
├── testing/
│   └── runner.zig
└── tests/
```

この構成は必要に応じて改善して構いませんが、少なくとも以下の層は明確に分離してください。

```text
CPU
  Z80のレジスタ、フラグ、命令デコード、命令実行

Bus
  メモリおよびI/Oへのアクセス抽象化

Machine
  Zig_80仮想コンピューターのメモリマップと周辺機器

Frontend
  CLI、ターミナル描画、デバッガー
```

CPUコアから、ターミナル、ファイル、標準入出力を直接操作しないでください。

---

## 3. CLI仕様

単一バイナリのサブコマンド形式にしてください。

```console
zig80 asm examples/hello.asm -o build/hello.bin
zig80 run build/hello.bin
zig80 run build/hello.bin --max-cycles 100000
zig80 debug build/hello.bin
zig80 disasm build/hello.bin
zig80 test examples/tests/
zig80 explain examples/hello.asm
```

今回のMVPで必須とするコマンドは以下です。

```console
zig80 asm
zig80 run
zig80 debug
zig80 disasm
zig80 test
```

`explain`は可能なら初期実装に含め、難しい場合は設計とスタブを用意してください。

引数が不足している場合や不正な場合は、利用方法を分かりやすく表示してください。

---

## 4. Z80 CPUエミュレーター

### 4.1 レジスタ

最低限、以下を実装してください。

- A
- F
- B
- C
- D
- E
- H
- L
- AF
- BC
- DE
- HL
- PC
- SP

16ビットレジスタペアは、8ビットレジスタと常に整合する実装にしてください。

将来、以下を追加できる設計にしてください。

- IX
- IY
- I
- R
- AF'
- BC'
- DE'
- HL'
- IFF1
- IFF2
- 割り込みモード

### 4.2 フラグ

以下を個別に操作・参照できるようにしてください。

- S
- Z
- H
- P/V
- N
- C

未文書化フラグX/YはMVPでは不要ですが、後から追加できる構造にしてください。

フラグ計算は命令実装内へ重複して書かず、可能な範囲で共通関数へ分離してください。

### 4.3 初期対応命令

MVPでは以下の命令を実装してください。

#### 制御

```asm
NOP
HALT
JP nn
JP NZ,nn
JP Z,nn
JR e
JR NZ,e
JR Z,e
CALL nn
RET
```

#### ロード

```asm
LD A,n
LD B,n
LD C,n
LD D,n
LD E,n
LD H,n
LD L,n

LD BC,nn
LD DE,nn
LD HL,nn
LD SP,nn

LD A,(HL)
LD (HL),A
LD (HL),n

LD A,(nn)
LD (nn),A
LD HL,(nn)
LD (nn),HL
```

#### 算術・比較

```asm
INC A
INC B
INC C
INC D
INC E
INC H
INC L
INC HL

DEC A
DEC B
DEC C
DEC D
DEC E
DEC H
DEC L
DEC HL

ADD A,n
ADD A,r
SUB n
SUB r
CP n
CP r
```

#### スタック

```asm
PUSH AF
PUSH BC
PUSH DE
PUSH HL

POP AF
POP BC
POP DE
POP HL
```

命令は、巨大な単一の`switch`へ無秩序に追加するのではなく、命令情報と実行処理を整理して管理してください。

各命令の実行結果として、少なくとも以下を取得できるようにしてください。

```zig
pub const StepResult = struct {
    pc_before: u16,
    pc_after: u16,
    opcode: u8,
    t_states: u16,
    halted: bool,
};
```

MVPでは命令単位のエミュレーションで構いませんが、各命令が消費するT-stateを返してください。

### 4.4 CPU API

概ね以下のようなAPIを提供してください。

```zig
pub const Cpu = struct {
    registers: Registers,
    halted: bool,

    pub fn reset(self: *Cpu) void;
    pub fn step(self: *Cpu, bus: *Bus) CpuError!StepResult;
};
```

未知の命令を実行した場合は、黙ってNOPとして処理せず、PCとオペコードを含む明確なエラーを返してください。

---

## 5. BusとMemory

CPUからメモリへ直接配列アクセスせず、Busを介してください。

例：

```zig
pub const Bus = struct {
    pub fn read8(self: *Bus, address: u16) u8;
    pub fn write8(self: *Bus, address: u16, value: u8) void;
    pub fn read16(self: *Bus, address: u16) u16;
    pub fn write16(self: *Bus, address: u16, value: u16) void;
    pub fn input(self: *Bus, port: u16) u8;
    pub fn output(self: *Bus, port: u16, value: u8) void;
};
```

Z80の16ビット値はリトルエンディアンとして扱ってください。

64KBのアドレス空間を持たせてください。

---

## 6. Zig_80仮想マシン仕様

MVPでは以下のメモリマップを使用してください。

```text
0x0000–0x7FFF  Program ROM / Program area
0x8000–0xBFFF  General RAM
0xC000–0xC3FF  Video RAM
0xC400         Input state
0xC401         Frame counter low byte
0xC402         Frame counter high byte
0xC403         Pseudo random value
0xC404–0xFFFF  Reserved / RAM
```

初期プログラムは、指定されたバイナリを`0x0000`から読み込んで実行してください。

### 仮想ディスプレイ

以下の仕様で1bppディスプレイを実装してください。

```text
Resolution: 128 × 64
Pixel format: 1bpp
VRAM size: 1024 bytes
VRAM address: 0xC000–0xC3FF
```

VRAM配置は、SSD1306のページ形式に近い構成としてください。

```text
address = 0xC000 + page * 128 + x
bit = y % 8
page = y / 8
```

1ビットが1ピクセルを表します。

ターミナル上では、ANSIエスケープシーケンスを利用して画面を更新してください。

ターミナルの1文字を2×2ピクセルまたは2×4ピクセルとして表現するなど、画面全体を無理なく表示できる方法を採用してください。Unicodeブロック文字を使っても構いません。

非TTY環境では、画面制御文字を大量に出力しないようにしてください。

### 入力

`0xC400`を入力状態として使用してください。

ビット割り当ては以下とします。

```text
bit 0: Up
bit 1: Down
bit 2: Left
bit 3: Right
bit 4: A
bit 5: B
bit 6: Start
bit 7: Reserved
```

MVPではターミナルから最低限、矢印キーまたはWASDと、A/Bに対応するキーを入力できるようにしてください。

入力処理が複雑になる場合、最初はデバッガー上で入力値を直接設定できる実装でも構いません。ただし、設計上はターミナル入力へ拡張可能にしてください。

---

## 7. アセンブラ

Z80アセンブリを機械語へ変換する2パス方式のアセンブラを実装してください。

### 7.1 対応構文

最低限、以下へ対応してください。

- ラベル
- コメント
- 10進数
- 16進数
- 2進数
- 文字リテラル
- 現在アドレス
- 単純な加減算式

例：

```asm
org 0x0000

VRAM equ 0xC000

start:
    ld hl, VRAM
    ld (hl), 0x01

loop:
    jp loop
```

コメントは以下のいずれかに対応してください。

```asm
; comment
```

### 7.2 ディレクティブ

以下を実装してください。

```asm
org
db
dw
equ
```

`db`では文字列も利用できるようにしてください。

```asm
message:
    db "HELLO", 0
```

### 7.3 シンボル

前方参照を処理できる2パス方式にしてください。

重複ラベル、未定義ラベル、範囲外値はエラーにしてください。

アセンブル時に以下を生成できるようにしてください。

- `.bin`
- シンボル一覧
- ソース行とアドレスの対応情報

出力形式は内部的な独自形式でも構いませんが、デバッガーから利用できるようにしてください。

### 7.4 診断

診断メッセージは、現代的なコンパイラのように分かりやすくしてください。

例：

```text
examples/game.asm:18:5: error: JR target is out of range
    jr game_loop
    ^

current address: 0x0120
target address:  0x0204
required offset: +226
valid range:     -128...+127

suggestion: use `jp game_loop`
```

エラーには可能な限り以下を含めてください。

- ファイル名
- 行番号
- 列番号
- 問題のあるソース行
- 理由
- 修正候補

---

## 8. 逆アセンブラ

バイナリを読み込み、対応済み命令をアセンブリ表現へ変換してください。

```console
zig80 disasm build/example.bin
```

出力例：

```text
0000  21 00 C0    LD HL,0xC000
0003  36 01       LD (HL),0x01
0005  C3 05 00    JP 0x0005
```

未知のオペコードは、`.db`として表示してください。

```text
0008  DD           DB 0xDD
```

アセンブラと逆アセンブラで命令定義が重複しすぎないよう、可能な範囲で共通の命令情報を使用してください。

---

## 9. デバッガー

以下の機能を持つ対話型デバッガーを実装してください。

```console
zig80 debug build/game.bin
```

最低限のコマンド：

```text
step
s
continue
c
registers
r
memory <address> <length>
m <address> <length>
disasm <address> <count>
break <address>
delete <address>
input <value>
screen
reset
quit
q
help
```

表示例：

```text
PC=0003  SP=FFFE  AF=0000  BC=0000
DE=0000  HL=C000

0003  36 01       LD (HL),0x01
```

ステップ実行後は、変更された値を分かりやすく表示してください。

```text
HL: 0x0000 -> 0xC000
PC: 0x0000 -> 0x0003
T-states: 10
```

ブレークポイントと、特定アドレスへのメモリ書き込みを検知するウォッチポイントを将来追加できる構造にしてください。

TUIライブラリには依存せず、MVPでは行単位のREPL形式で構いません。

---

## 10. Explain機能

可能であれば、アセンブリ命令がどのように機械語へ変換されるかを説明する機能を実装してください。

```console
zig80 explain examples/example.asm
```

出力例：

```text
Line 4: LD A,42

Mnemonic:
  LD

Operands:
  destination: register A
  source:      immediate 8-bit value

Encoding:
  opcode:      0x3E
  immediate:   0x2A

Output:
  3E 2A

Size:
  2 bytes

Execution time:
  7 T-states
```

全命令への対応が難しい場合、MVPで対応する命令のみで構いません。

---

## 11. 自動テスト環境

Z80プログラムに対して、CPU状態やメモリ状態を検証できる仕組みを実装してください。

テスト定義形式は、扱いやすい簡潔な独自形式で構いません。

例：

```text
test "write pixel" {
    load "build/pixel.bin"
    run 100 cycles
    expect memory[0xC000] == 0x01
    expect register.HL == 0xC000
}
```

最低限、以下を指定できるようにしてください。

- バイナリのロード
- 初期レジスタ値
- 初期メモリ値
- 実行命令数またはT-state上限
- 最終レジスタ値
- 最終メモリ値
- HALTしたかどうか

CLI：

```console
zig80 test examples/tests/
```

出力例：

```text
PASS write pixel
PASS add values
FAIL copy memory

expected:
  memory[0x8100] = 0x42

actual:
  memory[0x8100] = 0x41
```

テスト用パーサーの実装がMVPに対して過大になる場合は、ZigのユニットテストからMachineを直接操作できるテストAPIを先に完成させ、独自テスト形式は次段階のTODOとしても構いません。

---

## 12. サンプルプログラム

以下のサンプルを用意してください。

### 12.1 HALT

```asm
org 0x0000

start:
    halt
```

### 12.2 レジスタ加算

```asm
org 0x0000

start:
    ld a, 10
    ld b, 20
    add a, b
    halt
```

### 12.3 1ピクセル描画

VRAMへ書き込み、画面上へ1ピクセルを表示するプログラムを作成してください。

### 12.4 横移動するピクセル

可能であれば、入力またはフレームカウンターを利用して、画面上のピクセルを左右へ移動させるサンプルを作成してください。

このサンプルを、MVPの最終的な動作確認として使用してください。

---

## 13. テスト要件

各モジュールにユニットテストを追加してください。

最低限、以下を検証してください。

### CPU

- 8ビットレジスタと16ビットペアの整合性
- PCの進行
- SPの動作
- LD命令
- 算術命令
- Zフラグ
- Cフラグ
- Hフラグ
- CALL/RET
- PUSH/POP
- JRの正負オフセット
- HALT
- 未知命令エラー

### Bus

- read8/write8
- read16/write16
- 0xFFFF付近の境界動作
- リトルエンディアン

### Assembler

- ラベル
- 前方参照
- `org`
- `db`
- `dw`
- `equ`
- 数値表現
- 重複シンボルエラー
- 未定義シンボルエラー
- JR範囲外エラー

### Disassembler

- 対応済み命令
- 即値
- 16ビット値
- 未知命令

### Machine

- ROMロード
- VRAM書き込み
- 入力レジスタ
- フレームカウンター

以下が成功する状態にしてください。

```console
zig fmt --check .
zig build
zig build test
```

---

## 14. 命令定義の設計

アセンブラ、逆アセンブラ、CPUデコーダーで、オペコード情報を別々に手書きしすぎないようにしてください。

たとえば、次のような共通メタデータを検討してください。

```zig
pub const InstructionDefinition = struct {
    mnemonic: Mnemonic,
    operand_pattern: OperandPattern,
    opcode: []const u8,
    size: u8,
    t_states: u16,
};
```

ただし、過度な抽象化や複雑なコード生成は避けてください。

初期段階では読みやすさ、デバッグしやすさ、教材として追いやすいことを優先してください。

Zigの`comptime`を使う場合も、仕組みをREADMEへ説明してください。

---

## 15. エラー処理

以下を明確なエラーとして扱ってください。

- 入力ファイルが存在しない
- 出力ファイルを書けない
- バイナリが64KBを超える
- 不正なアセンブリ構文
- 未定義ラベル
- 値の範囲外
- 未対応命令
- 未知オペコード
- 実行サイクル上限到達
- 不正なメモリアドレス指定
- テスト失敗

`catch unreachable`や無条件のpanicを通常の入力エラー処理に使用しないでください。

---

## 16. 実行停止条件

`run`コマンドは無限ループで終了不能にならないよう、以下を用意してください。

```console
zig80 run program.bin --max-instructions 1000000
zig80 run program.bin --max-cycles 10000000
```

上限へ到達した場合は、現在のCPU状態と停止理由を表示してください。

通常は以下のいずれかで終了します。

- HALT命令
- 命令数上限
- T-state上限
- 未知命令
- ユーザーによる中断
- 実行時エラー

---

## 17. README

READMEには以下を記載してください。

- Zig_80の目的
- 対応するZigバージョン
- ビルド方法
- CLIの使用方法
- サンプルの実行方法
- 仮想マシンのメモリマップ
- VRAM形式
- 入力ビット配置
- 対応済みZ80命令
- アセンブラ構文
- CPU、Bus、Machineの責務
- 新しい命令の追加方法
- 新しい仮想周辺機器の追加方法
- 現在の制限事項
- 今後のロードマップ

また、Z80命令が以下の順に処理される流れを説明してください。

```text
fetch
decode
execute
update registers / flags
return consumed T-states
```

アセンブラについても、以下の2パス処理を説明してください。

```text
Pass 1:
  parse source
  calculate addresses
  collect symbols

Pass 2:
  resolve symbols
  encode instructions
  emit bytes
```

---

## 18. 将来拡張

以下はMVPで完全実装する必要はありませんが、設計上の拡張ポイントとTODOを残してください。

- Z80全公開命令
- CB/DD/ED/FDプリフィックス
- IX/IY
- 代替レジスタ
- 割り込みIM 0/1/2
- I/Rレジスタ
- 未文書化命令
- 未文書化フラグ
- ZEXDOC/ZEXALLへの対応
- cycle-accurateエミュレーション
- WAIT/BUSREQ/BUSACK
- I/Oポート
- 仮想UART
- 仮想PSG
- 仮想SDカード
- タイムトラベルデバッガー
- ウォッチポイント
- VCD出力
- プロファイラー
- PNGから1bppへのアセット変換
- WebAssembly対応
- 将来の実Z80基板とのROM互換
- GDB Remote Serial Protocol対応
- Language Server Protocol対応

---

## 19. 実装の進め方

以下の順序で実装してください。

### Phase 1

- プロジェクト初期化
- CPUレジスタ
- Bus
- Memory
- NOP
- HALT
- LD
- PC/SP
- CPUユニットテスト

### Phase 2

- 算術命令
- フラグ
- JP/JR
- CALL/RET
- PUSH/POP
- 逆アセンブラ

### Phase 3

- アセンブラ
- ラベル
- 2パス処理
- `.bin`出力
- シンボル情報
- 診断表示

### Phase 4

- Machine
- 128×64 1bpp VRAM
- ターミナル描画
- 入力
- フレームカウンター

### Phase 5

- CLI統合
- デバッガー
- サンプル
- README
- 統合テスト

各Phase終了時に、ビルドとテストが成功する状態を維持してください。

---

## 20. 完了条件

以下がすべて可能になった時点を、今回のMVP完成とします。

1. Z80アセンブリを独自アセンブラでバイナリ化できる
2. 生成したバイナリを独自Z80エミュレーターで実行できる
3. レジスタ、メモリ、フラグが正しく更新される
4. 逆アセンブル結果を表示できる
5. デバッガーで1命令ずつ実行できる
6. VRAMへの書き込みをターミナル画面へ表示できる
7. 128×64画面に最低1ピクセルを描画できる
8. 自動テストでCPUとメモリ状態を検証できる
9. `zig build`と`zig build test`が成功する
10. READMEだけを読んでサンプルを実行できる

---

## 21. 実装時の注意

- まず既存リポジトリの状態を確認してください。
- 既存コードがある場合は、目的を理解してから変更してください。
- 不要な大規模リファクタリングは避けてください。
- 変更前後でテストを実行してください。
- 未完成機能を完成済みとしてREADMEへ記載しないでください。
- 推測でZ80のオペコードやフラグ動作を実装しないでください。
- 命令の仕様に不確実な点がある場合は、実装箇所へ根拠をコメントとして残してください。
- ターミナル依存処理とCPUコアを分離してください。
- 全命令対応を急ぐより、少数の命令を正しくテスト可能に実装してください。
- 一つの巨大ファイルへ全機能を詰め込まないでください。
- 後から実機基板へ移植できるよう、Machine固有処理とZ80 CPUコアを分離してください。

---

## 22. 作業完了時の報告

完了後、以下を報告してください。

1. 実装した機能
2. 未実装の機能
3. 主要な設計判断
4. 作成・変更したファイル
5. 実行したテスト
6. テスト結果
7. サンプルの実行方法
8. 現在の制限事項
9. 次に実装すべき機能
10. 実装中に発見した問題や仕様上の懸念

可能であれば、最後に以下のコマンドを実際に実行して結果を確認してください。

```console
zig fmt --check .
zig build
zig build test
zig build run -- --help
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- disasm zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --max-instructions 10000
```

最優先事項は、Z80全体を急いで網羅することではありません。

**小さくても、アセンブル、実行、観察、描画、テストという一連の開発体験が実際に機能する垂直スライスを完成させること**を優先してください。
