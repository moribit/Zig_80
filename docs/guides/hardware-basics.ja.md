# Z80 Hardware基礎と将来のZig_80 Target

[目次](README.ja.md) | [English](hardware-basics.md)

ここで扱う実機Boardは将来構想であり、実装済みTargetではありません。現在のZig_80はSoftware Virtual Machineです。

## CPUとバス

実Z80は16 bitアドレスバス（Address Bus）、8 bit双方向データバス（Data Bus）、制御バス（Control Bus）を持ちます。Address線が対象、Data線が1 byte、Control線がTransfer種別を表します。

| Signal | 役割 |
|---|---|
| Clock | CPU内部動作を進める |
| `/MREQ` | Memory Request |
| `/IORQ` | Port I/O Request |
| `/RD` | CPUが選択DeviceからRead |
| `/WR` | CPUが選択DeviceへWrite |
| `/M1` | Opcode Fetchなど命令最初のMachine Cycle |
| `/RFSH` | Dynamic RAM Refresh用Address/Cycle |
| `/WAIT` | 外部DeviceがAccessを延長 |
| `/INT`、`/NMI` | Mask可能/不可能Interrupt Request |
| `/BUSREQ`、`/BUSACK` | 別Bus MasterへのBus要求/承認 |

SlashはActive Lowを表し、低いVoltage側がAssertです。Data SheetによってはOverbarや`_n`を使います。

## Logic Levelと安全な接続

Classic Z80は一般に5 V動作、RP2350 Class MCUは3.3 Vで、通常5 V Tolerantではありません。Logic “1”はVoltage範囲でありEmulatorのBooleanではありません。正確なVariantのData SheetでInput Threshold、Output Level、Current、Absolute Maximum、Power Sequenceを確認します。

将来設計ではDirection制御Level Shifterや5 V対応Bufferが必要になる可能性があります。双方向Data Busは単方向Address Busより複雑で、Directionを誤るとBus Contentionや部品破損につながります。Decoupling、Common Ground、Reset、Clock品質、Propagation Delay、Fan-out、Chip Select Decodeも独立した電気Reviewが必要です。

## RP2350 Bus Controller構想

```text
Real Z80
   │ address / data / control
   ▼
RP2350-class Bus Controller（将来のZig Firmware）
   ├─ RAM / ROM
   ├─ Video / Input
   ├─ Audio / Timer / Storage
   └─ USB Debug
```

決定的なBus応答、Level変換、安全なBus所有権、計測済みTiming、PCBが必要です。現在Repositoryには実装も電気検証もありません。

## Logical Traceと実波形

Zig_80 Traceは等幅の論理Accessです。実Logic AnalyzerはPinを実時間SampleしClock EdgeとPulse幅を測定します。`t_state_count=0`のEventからSetup/Hold、WAIT、Refresh Timing、Signal Integrityを証明できません。電気Timing根拠として使用しないでください。

## 共通Machine仕様

長期目標はCLI Emulatorと将来PCBがEntry Address、ROM/RAM/VRAM範囲、Display配置、Input Bit、I/O Port、Debug挙動のVersion付き仕様を共有することです。「同じROMが動く」にはConformance Testが必要で、現時点では設計目標です。

