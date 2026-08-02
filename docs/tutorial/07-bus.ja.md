# 07 Logic Analyzer: 論理Bus Eventを読む

[← 前: Display](06-display.ja.md) | [目次](README.ja.md) | [English](07-bus.md) | [次: Project →](08-projects.ja.md)

## この章で見る画面

- **Bus Instruction Card**: 選択命令とEvent Group
- **Logic Analyzer**: 時間軸、Signal、Time Cursor
- **Source/Instruction**: Eventを生成した命令
- CPUとDisplayはCross Highlightを確認する時だけ見ます

## この章のゴール

- Opcode Fetch、Operand Read、Memory Writeを区別する
- Address、Data、Event Slot、Time Cursorを読む
- 論理Event表示と実機Logic Analyzerの差を説明する

## Busとは

BusはCPU、Memory、Peripheralの間で情報を運びます。

- **Address**: どこへAccessするか
- **Data**: 何を読む/書くか
- **Control**: ReadかWriteか、MemoryかI/Oか
- **Event**: Zig_80が観測した1回の論理Access

`examples/pixel.asm`をResetし、最初の2命令をStepしてから`Ctrl+4`でBusを開きます。

## 1. Opcode Fetch

CPUが命令を知るため、PCのAddressからOpcodeを読みます。

```text
Event type      Opcode Fetch
Address         0000
Data            21
Meaning         LD HL,n16のOpcodeを取得
Signals         M1 asserted, /MREQ low, /RD low
```

M1は命令先頭のOpcode Fetchを示す論理Signalです。

## 2. Operand Read

`LD HL,C000`は3 byteなので、Opcode後の`00 C0`を読みます。

```text
Event 0  Opcode Fetch   ADDR 0000  DATA 21
Event 1  Operand Read   ADDR 0001  DATA 00
Event 2  Operand Read   ADDR 0002  DATA C0
```

2 byte OperandをLittle Endianで組み合わせ、HL=`C000`になります。Instruction Cardではこれらが同じInstruction番号にGroup化されます。

## 3. Memory Write

`LD (HL),01`をStepすると、命令byteを読むEventに加え、VRAMへのWriteが記録されます。

```text
Type            Memory Write
Address         C000
Data            01
Signals         /MREQ low, /WR low
Result          VRAM byte and pixel change
```

Write Eventを選択するとSource、Instruction、保存済みCPU Snapshot、Display Inspectorが同じ命令へ同期します。

## Logic Analyzerの読み順

1. 上部の`Time →`で左から右がEvent順序と確認
2. `Instruction #`境界を見る
3. 選択Eventを貫く細い`│` Time Cursorを見る
4. M1、`/MREQ`、`/RD`、`/WR`のHigh/LowとTransitionを見る
5. ADDRの`[0000]`、DATAの`[21]`を見る
6. TYPEと末尾DetailでEvent種別、PC、Dataを確認

Slash付きSignalはActive Lowです。Low PulseがAssertを表します。`┐`/`└`や`┌`/`┘`が立下り・立上りを示します。

> Bus Waveformは、命令実行中に観測された論理的なバスアクセスを等幅イベントとして可視化したものです。実Z80の電気的タイミングや各T-stateの長さを再現するものではありません。

### Column: 実機Logic Analyzerとの違い

実機ではSignalを一定Sample Rateで測定し、Pulse幅、Setup/Hold、Clockとの位置関係を時間単位で読みます。Zig_80では全Eventを等幅Slotにしています。

- 横幅はns、µs、Clock数ではなくEvent順序
- `t_state_start`はAccess時刻ではなく命令開始時のCPU総T-state
- `t_state_count = 0`は未計測の論理Model
- Pulse幅から実Hardware Timingを推測できない
- Refresh、Interrupt、I/O Eventは現在生成されない

Zig_80のAnalyzerは「命令がどの論理Accessを起こしたか」を学ぶ表示です。配線、Voltage、Signal Integrity、cycle-accurate Timingの検証Toolではありません。

## IDE Tips

- `[` / `]`: 前/次Eventを選択。
- End: 最新Event追従へ戻る。
- Enter: EventのSourceへ移動。
- `+` / `-`: 1x、2x、4x Zoom。
- `f`: 全SequenceをFit。
- `<` / `>`: Time Cursorと独立してPan。
- Command Palette: 全EventまたはMemory Write Filter。

## Challenge: Eventを分類する

`examples/pixel.asm`を最初から3回Stepし、各Eventを次の表へ記録します。

| Instruction | Event index | Type | Address | Data |
|---|---:|---|---:|---:|
| LD HL,C000 | 0 | Opcode Fetch | 0000 | 21 |
| ... | ... | ... | ... | ... |

Opcode/Operand/Writeがそれぞれ何件あるか数え、Memory Write Filterで結果を確認します。

[← 前](06-display.ja.md) | [目次](README.ja.md) | [次: Project →](08-projects.ja.md)

