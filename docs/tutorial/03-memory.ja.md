# 03 MemoryとAddress: CPUの外へ値を置く

[← 前: Register](02-register.ja.md) | [目次](README.ja.md) | [English](03-memory.md) | [次: 分岐 →](04-branch.ja.md)

## この章で見る画面

- **Source**: 括弧付き`LD`
- **CPU**: Addressを保持するHL
- **Memory**: Addressごとのbyte
- **Bus**: Memory Read / Write

## この章のゴール

- 値とAddressを区別する
- 括弧がMemory Accessを意味することを理解する
- 16 bit値のLittle Endian配置を見る
- Zig_80固有のMemory Mapを読む

## Z80の仕組み

メモリはCPU外部のAddress付きbyte列です。括弧付きOperandはMemory Accessを要求します。Z80のwordは下位byteを低いAddressへ置きます。

### メモリは番号付きbyte列

```text
Address   8000  8001  8002  8003
Value       2A    00    FF    10
```

```asm
ld hl,0x8000     ; HLというRegisterへ8000を入れる
ld (hl),0x2A     ; HLをAddressとしてMemoryへ2Aを書く
ld a,(hl)        ; HLをAddressとしてMemoryからAへ読む
```

括弧の有無で意味が変わります。

## CLIで試す

次を`memory.asm`として保存します。

```asm
org 0x0000
start:
    ld hl,0x8000
    ld (hl),0x2A
    ld a,(hl)
    halt
```

```console
zig build run -- asm memory.asm -o zig-out/memory.bin
zig build run -- debug zig-out/memory.bin
```

Debuggerで`memory 0x8000 2`を使います。

## TUIで観察する

```console
zig build run -- tui memory.asm
```

### 3命令をStepする

```text
Step 1
PC          0000 → 0003
HL          0000 → 8000
Bus         Opcode + two Operand Reads
Memory      unchanged

Step 2
PC          0003 → 0005
HL          remains 8000
Bus         Memory Write [8000] ← 2A
Memory      8000: 00 → 2A

Step 3
PC          0005 → 0006
A           00 → 2A
Bus         Memory Read [8000] = 2A
```

Memory Paneで`g`を押し、`8000`を入力してEnterすると対象Addressへ移動できます。Escapeで入力をCancelします。

## Little EndianをStepで確認する

```asm
ld hl,0x1234
ld (0x8000),hl
halt
```

2命令目の後、Memoryは次になります。

```text
8000: 34    low byte
8001: 12    high byte
```

Z80は多byte値の下位byteを低いAddressへ置きます。Debuggerなら`memory 0x8000 2`でも確認できます。

## Zig_80 MachineのMemory Map

| Address | 用途 |
|---|---|
| `0000-7FFF` | Program領域 |
| `8000-BFFF` | General RAM |
| `C000-C3FF` | Video RAM |
| `C400` | Input状態 |
| `C401-C402` | Frame Counter、Little Endian |
| `C403` | Pseudo-random値 |
| `C404-FFFF` | Reserved RAM |

これはZig_80独自のMachine仕様です。Memory MapはZ80 CPU自身ではなくMachine設計者が決めます。現在はProgram領域も書込み保護されていません。

## 現在使えるMemory形式

```asm
ld a,(hl)           ; indirect read
ld (hl),a           ; indirect write
ld (hl),42          ; indirect immediate write
ld a,(0x8000)       ; absolute read
ld (0x8000),a       ; absolute write
ld hl,(0x8000)      ; little-endian word read
ld (0x8000),hl      ; little-endian word write
```

## IDE Tips

- `Ctrl+3`: Memory Viewへ切替。
- Memoryで`g`: `Go to address: 0x____`。
- MemoryでHome/End: PC/HLへ移動。
- Bus FilterをMemory Writeだけにすると書込みを追いやすくなります。
- `Ctrl+T`: Write命令だけを実行してMemory差分を見る。

## Challenge: Addressと値を変える

Write先を`0x8010`、値を`0x7F`へ変更します。Step前に次を予想してください。

- HLの値
- Memory Write EventのAddress/Data
- Memory Paneで変わるCell
- Displayが変化するか（RAMなので変化しません）

[← 前](02-register.ja.md) | [目次](README.ja.md) | [次: 分岐 →](04-branch.ja.md)
