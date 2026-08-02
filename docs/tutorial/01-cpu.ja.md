# 01 CPUと命令: Sourceから実行まで

[← 前: はじめに](00-introduction.ja.md) | [目次](README.ja.md) | [English](01-cpu.md) | [次: Register →](02-register.ja.md)

## この章で見る画面

- **Source**: Addressと生成Bytes
- **Instruction**: Mnemonic、Opcode、Length、Timing
- **CPU**: PC
- **Bus**: Opcode FetchとOperand Read

## この章のゴール

- Source、Machine Code、Instructionを対応付ける
- Fetch→Decode→ExecuteをIDE上で追う
- 命令長に応じてPCが進むことを確認する

## 1. SourceをMachine Codeへ変換する

```console
zig build run -- asm examples/add.asm -o zig-out/add.bin
zig build run -- disasm zig-out/add.bin
zig build run -- tui examples/add.asm
```

Source Gutterで最初の命令を見ます。

```text
ADDR  BYTES     SOURCE
0000  3E 0A     ld a,10
0002  06 14     ld b,20
0004  80        add a,b
0005  76        halt
```

Mnemonicは操作名、Operandは対象です。`LD A,10`では`LD`がMnemonic、`A`と`10`がOperandです。最初のbyte`3E`がOpcode、次の`0A`が即値Operandです。

## 2. LD A,10をStepする

`Ctrl+T`を1回押します。

```text
Step 1
Source          LD A,10 at address 0000
PC              0000 → 0002
Instruction     opcode 3E, length 2 bytes
Register        A: 00 → 0A
Bus             Fetch [0000]=3E, Operand [0001]=0A
Display         no change
```

PCが2進んだのは、Opcodeと1 byte Operandで命令長が2 byteだからです。

## 3. LD B,20をStepする

```text
Step 2
Source          LD B,20 at address 0002
PC              0002 → 0004
Instruction     opcode 06, length 2 bytes
Register        B: 00 → 14
Bus             Fetch [0002]=06, Operand [0003]=14
```

Sourceには10進の20、Machine Codeには16進の`14`が表示されます。同じ値を異なる表記で見ています。

## 4. ADDとHALTをStepする

```text
Step 3
PC              0004 → 0005
Instruction     ADD A,B, opcode 80, length 1
Register        A: 0A → 1E
Bus             Fetch [0004]=80

Step 4
PC              0005 → 0006
Instruction     HALT, opcode 76
CPU             HALTED
```

`ADD A,B`はRegister BをOpcode自身で指定するため追加Operand byteがなく、1 byteです。

## Fetch、Decode、Execute

1. **Fetch**: PCのAddressからOpcodeを読む
2. **Decode**: Opcodeから命令とOperand形式を判定する
3. **Execute**: RegisterやMemoryを変更する
4. **Advance/Branch**: PCを次へ進めるか分岐先へ変える

Zig_80のStepはこの一連を1命令単位で実行します。Instruction CardのTimingは命令全体のT-state数です。

## IDE Tips

- `Ctrl+R`: 保存せずMemory上のSourceをAssemble。
- SourceのADDR/BYTES: 最後に成功したAssemble結果。Dirty時は古い場合があります。
- CursorをMnemonicへ置く: PCを動かさずInstruction Cardを確認できます。
- `Ctrl+R`: 再AssembleとLoadを行い、最初から観察し直します。`Ctrl+E`はReset後すぐRunします。

## Challenge: 即値を変える

10を15、20を3へ変更し、結果を予想します。`Ctrl+R`でAssembleし、Runせず4回Stepしてください。

確認項目:

- 即値byteは何になったか
- PCの進み方は変わったか
- Aの最終値はいくつか

[← 前](00-introduction.ja.md) | [目次](README.ja.md) | [次: Register →](02-register.ja.md)
