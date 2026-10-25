# Default Machine仕様

[目次](README.ja.md) | [English](machine.md)

| Address | 用途 |
|---|---|
| `0000-7FFF` | Program領域 |
| `8000-BFFF` | General RAM |
| `C000-C3FF` | 128×64、1bpp VRAM |
| `C400` | Input Bit |
| `C401-C402` | Little Endian Frame Counter |
| `C403` | Pseudo-random byte |
| `C404-FFFF` | Reserved RAM |

Input bit 0〜6はUp、Down、Left、Right、A、B、Startです。Pixel `(x,y)`は`C000 + (y / 8) * 128 + x`のbit `y % 8`です。ProgramはAddress 0へLoadされ最大32KBです。Program領域は書込み保護されません。Frame/Random DeviceはMachineの`tickFrame`を明示的に呼んだ時だけ進み、実時間Clockではありません。

このページは既定Classicの仕様です。[Machine Profile](../architecture/machine-profiles.md)にBank構成、Port I/O、Timer/Input IRQ、256×64画面を持つHandheldを追加しています。Reset/Loadの状態遷移は[Core契約](../development/quality-improvements.md)を参照してください。

