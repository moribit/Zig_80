# 02 RegisterとFlag: CPU内部の状態を見る

[← 前: CPU](01-cpu.ja.md) | [目次](README.ja.md) | [English](02-register.md) | [次: Memory →](03-memory.ja.md)

## この章で見る画面

- **Source**: `LD`、`ADD`、`SUB`、`CP`
- **CPU**: AF、BC、DE、HLとFlags
- **Instruction**: Flags affected
- BusとDisplayは補助的に見ます

## この章のゴール

- 8 bit Registerと16 bit Pairを区別する
- Register差分を読み取る
- ZとCを使って演算結果を説明する

## Z80の仕組み

レジスタはCPU内部に値を保持します。算術命令は結果の性質をFへ書き、後続の条件命令がそれを利用します。

### レジスタの地図

| Register | 最初の用途としての見方 |
|---|---|
| `A` | Accumulator。算術・比較の中心 |
| `F` | Flags。AFの下位byte |
| `B`,`C` | Counterや一時値。PairでBC |
| `D`,`E` | 一時値。PairでDE |
| `H`,`L` | PairのHLをMemory Addressによく使う |
| `PC` | 次の命令Address |
| `SP` | Stack先頭Address |

CPU Cardは16 bit Pairを中心に表示します。例えば`BC=1400`ならBが`14`、Cが`00`です。

## CLIで試す

```console
zig build run -- asm examples/add.asm -o zig-out/add.bin
zig build run -- debug zig-out/add.bin
```

Debuggerで`step`と`registers`を使います。

## TUIで観察する

```console
zig build run -- tui examples/add.asm
```

### ADDをStepしてAFを読む

`examples/add.asm`をResetし、3回Stepします。

```text
Step 1: LD A,10    AF 0000 → 0A00
Step 2: LD B,20    BC 0000 → 1400
Step 3: ADD A,B    AF 0A00 → 1E00
```

AF全体が表示されても、上位byte Aと下位byte Fに分けて考えます。3回目はAだけでなく演算に応じてFも更新されます。

### Flagを観察するProgram

Sourceを次へ変更してAssembleします。

```asm
org 0x0000
start:
    ld a,1
    sub 1
    cp 0
    halt
```

### Stepの観察

```text
Step 1  LD A,1
PC      0000 → 0002
A       00 → 01

Step 2  SUB 1
PC      0002 → 0004
A       01 → 00
Flags   Z=1, N=1

Step 3  CP 0
A       remains 00
Flags   comparison result is zero
```

`CP`はAを変更せず、`A - operand`相当のFlagsだけを設定します。

| Flag | 意味 |
|---|---|
| `S` | 結果の最上位bitが1 |
| `Z` | 結果が0 |
| `H` | bit 3境界のCarry/Borrow |
| `PV` | Parityまたは符号Overflow |
| `N` | 減算系Operation |
| `C` | 値幅の外へのCarry/Borrow |

初学者はまずZとCを追い、必要になった時に他のFlagを学びます。INC/DECは現在の実装でもCを保持します。

## IDE Tips

- 変更Registerは旧値`↓`新値で約300 ms表示されます。
- `Ctrl+2`: CPUを全面表示するView。
- `Ctrl+T`: 強調が消えたら次の1命令だけStep。
- `Ctrl+Z` / `Ctrl+Y`: Source編集のUndo / Redo。
- `Ctrl+F`: Registerを変更するMnemonicをSource内検索。

## Challenge: Overflowを予想する

Aへ255、Bへ1をLoadして`ADD A,B`をStepします。実行前にA、Z、Cを予想してください。

```asm
ld a,255
ld b,1
add a,b
halt
```

8 bitのAは`FF + 01`で`00`へWrapし、ZeroとCarryを観察できます。

[← 前](01-cpu.ja.md) | [目次](README.ja.md) | [次: Memory →](03-memory.ja.md)
