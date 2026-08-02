# 09 Reference

[← 前: Project](08-projects.ja.md) | [目次](README.ja.md) | [English](09-reference.md)

この章は暗記せず、Example作成中に必要な項目を探すために使います。

## CLI Command

| Command | 用途 |
|---|---|
| `asm source.asm -o program.bin` | 2 Pass AssembleとSymbol表示 |
| `disasm program.bin` | Address、Bytes、Instruction表示 |
| `run program.bin` | HALTまたは上限まで実行 |
| `debug program.bin` | Step、Memory、Breakpoint、InputのREPL |
| `test program.bin` | 100,000命令以内のHALTを簡易検証 |
| `explain source.asm` | Source各命令のEncodeを表示 |
| `tui [source.asm]` | Zig_80 IDE |

```console
zig build run -- asm my.asm -o zig-out/my.bin
zig build run -- disasm zig-out/my.bin
zig build run -- run zig-out/my.bin --max-instructions 100000 --max-cycles 1000000 --screen
zig build run -- debug zig-out/my.bin
zig build run -- test zig-out/my.bin
zig build run -- tui my.asm
```

意図的な無限Loopは`test`にPassしません。`test`はHALTのみを検証します。

## Debugger Command

```text
step / s
continue / c
registers / r
memory / m <address> <length>
disasm <address> <count>
break <address>
delete <address>
input <value>
screen
reset
quit / q
```

Debugger数値は10進または小文字Prefixの`0x`付き16進です。

## Number、Symbol、Expression

```asm
42
0x2A
0b101010
'A'
$
VRAM + 64
end - start
```

現在は単純な`+`/`-`式を再帰評価します。算術括弧の優先順位、乗除算、一般Bit演算はありません。Symbol参照は大文字小文字を区別しません。

## Directive

```asm
org 0x0000
db 1,2,0xFF
db "HELLO",0
dw 0x1234,start
VALUE equ 42
```

`org`は論理PCを変えますが出力FileをPaddingしません。`dw`はLittle Endianです。

## 対応命令形式

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

Editor補完はより広いZ80語彙を提示しますが、LDI、IX/IY、Prefix命令、Interrupt、I/O命令などは未実装です。

## Diagnostic

| Error | 確認 |
|---|---|
| Invalid mnemonic | Spell、対応命令一覧 |
| Invalid operand | Register組合せ、Comma、括弧 |
| Undefined symbol | Label Spellと定義 |
| Duplicate symbol | 同名Label/`equ` |
| Value out of range | 8 bitは0〜255、16 bitは0〜65535 |
| JR out of range | JPへ変更、Codeを近づける |
| Invalid expression | 空Operand、未対応Operator |
| Unterminated string | `db "..."`の閉じQuote |
| Invalid character literal | 正確な`'A'`形式 |

Assemblerは現在最初のErrorで停止します。

## Hardwareへ進む前の注意

現在はSoftware Virtual Machineです。実Z80、Breadboard、PCB、MCU Chipsetは[Vision](../vision.ja.md)の将来構想です。実機ではVoltage、Current、Ground、Clock/Reset Timing、Tri-state、Chip Select、Signal Integrity、DecouplingをData Sheetで確認してください。5 V Z80と3.3 V MCUを直接接続できるとは限りません。論理Waveformを配線図や電気Timing保証に使わないでください。

## 現在の制限

- 完全命令Set、Prefix、IX/IY、Interrupt、I/O命令は未対応
- cycle-accurate、周波数同期、実時間Inputではない
- Busは等幅Logical Event
- CLI TestはHALTのみ
- TUIはmacOS/Linux向け。Windows、Mouse、Clipboard、複数Fileは未対応
- Program領域は書込み保護されない

## 用語集

| 用語 | 意味 |
|---|---|
| Mnemonic / Operand | 操作名 / 命令が使うRegister・値・Address |
| Opcode | 命令種別を表すbyte |
| PC / SP | Program Counter / Stack Pointer |
| Flag | ZeroやCarryなど演算結果を記録するbit |
| RAM / ROM / VRAM | 作業Memory / Program Memory / Display Memory |
| Bus | Component間でAddress、Data、Controlを運ぶ接続 |
| T-state | Z80 Timingの基本Clock単位 |
| Little Endian | 下位byteを低Addressへ置く形式 |
| Stack | 戻り先や一時値を置くLIFO領域 |
| Immediate | 命令byteへ直接埋め込まれた値 |
| 1bpp | 1 Pixelを1 bitで表す形式 |

[← 前: Project](08-projects.ja.md) | [目次](README.ja.md)

