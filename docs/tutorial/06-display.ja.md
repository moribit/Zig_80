# 06 VRAMからPixelへ: 命令が画面になるまで

[← 前: Stack](05-stack.ja.md) | [目次](README.ja.md) | [English](06-display.md) | [次: Logic Analyzer →](07-bus.ja.md)

## この章で見る画面

- **Source**: VRAMへ書く`LD`
- **CPU**: VRAM Addressを保持するHL
- **Bus**: Memory WriteのAddressとData
- **Display**: Dirty Pixel Highlight
- **Pixel Inspector**: x/y、VRAM Address、Bit、Value、Writer

## この章のゴール

- `CPU → Bus → VRAM → Display`を1命令の流れとして追う
- Pixel座標からVRAM Address、Bit、Maskを計算する
- Pixel Inspectorで計算結果とWriter命令を検証する

## Z80の仕組み

CPUはAddressへ1 byteを書くだけです。MachineのMemory MapがそのAddressをVRAMとし、Display Layoutが各BitをPixelとして解釈します。

## CLIで試す

```console
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
```

## TUIで観察する

```console
zig build run -- tui examples/pixel.asm
```

```asm
org 0x0000
VRAM equ 0xC000
start:
    ld hl,VRAM
    ld (hl),0x01
    halt
```

### Step 1: Addressを準備する

`Ctrl+T`で`LD HL,VRAM`を実行します。

```text
Source          LD HL,VRAM
PC              0000 → 0003
Instruction     opcode 21 00 C0, length 3
CPU             HL 0000 → C000
Bus             Opcode Fetch + Operand Reads
VRAM            unchanged
Display         unchanged
Overlay         HL ← C000
```

Immediateの`C000`はMachine CodeではLittle Endianの`00 C0`になります。

### Step 2: VRAMへ書く

もう一度`Ctrl+T`で`LD (HL),01`を実行します。

```text
Source          LD (HL),01
PC              0003 → 0005
CPU             HL remains C000
Bus             Memory Write: address C000, data 01
VRAM            C000: 00 → 01
Display         pixel (0,0) changes 0 → 1
Pixel Inspector Addr C000, Bit 0, Value 1
Overlay         VRAM[C000] ← 01
```

同じ変化を5段階で見ています。

```text
CPU has C000 in HL
       ↓
Bus carries address C000 and data 01
       ↓
VRAM byte C000 becomes 01
       ↓
bit 0 maps to pixel (0,0)
       ↓
Display highlights the changed pixel
```

## VRAM Page Layout

Displayは128×64、1bppです。1 byteの8 bitが縦方向の8 Pixelを表します。

```text
address = C000 + (y / 8) * 128 + x
bit     = y % 8
mask    = 1 << bit
```

```text
C000 byte
bit 0 ─ pixel (0,0)
bit 1 ─ pixel (0,1)
 ...
bit 7 ─ pixel (0,7)

C080 byte
bit 0 ─ pixel (0,8)
```

| Pixel | Address | Bit | Mask/Data |
|---|---:|---:|---:|
| `(0,0)` | `C000` | 0 | `01` |
| `(0,1)` | `C000` | 1 | `02` |
| `(0,7)` | `C000` | 7 | `80` |
| `(0,8)` | `C080` | 0 | `01` |
| `(64,4)` | `C040` | 4 | `10` |

同じbyte内のPixelを複数残すには、`LD A,(HL)`、`OR mask`、`LD (HL),A`のRead-Modify-Writeを使えます。付属ExampleはDisplay Loopを短くするため完成Patternの`0x18`や`0x38`を直接書きます。特定BitだけをClearするには反転Maskも必要ですが、現在の式Syntaxに単項Bit反転はありません。

## Pixel Inspectorを使う

1. `Ctrl+5`でDisplayへ切替
2. Arrow KeyでPixel Cursorを移動
3. Inspectorのx/y、Addr、Bit、Valueを見る
4. GridはCommand Paletteの`display grid`
5. Scaleは1x、2x、4xから選ぶ（既定2x）

VRAM Write EventをBusで選ぶと、Display Inspectorもそのbyteへ同期します。Writer Instructionには最後に観測した書込み命令が表示されます。ただし過去Frameを復元するTime Travelではなく、値は現在のMachine Memoryです。

## IDE Tips

- `Ctrl+5`: Display View。
- `Ctrl+P`: Display Scale/Gridを変更。
- Arrow: Display Focus中のPixel Cursor。
- Changed Pixelは1 Frame、関連Paneは約300 ms強調。
- Display Titleの`*`/`●`: VRAM更新Indicator。
- Source右MarginのOverlay: Debuggerが観測した実行結果です。

## Challenge: Pixel (10,9)

式へ代入し、AddressとDataを求めてからProgramを変更します。

```text
address = C000 + (9 / 8) * 128 + 10 = C08A
bit     = 9 % 8 = 1
mask    = 02
```

`LD HL,C08A`、`LD (HL),02`をStepし、Bus Address/DataとPixel Inspectorが計算に一致することを確認してください。

[← 前](05-stack.ja.md) | [目次](README.ja.md) | [次: Logic Analyzer →](07-bus.ja.md)
