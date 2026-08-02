# ゲーム開発ガイド

[目次](README.ja.md) | [English](game-development.md)

最初は決定的なState更新、VRAM 1 byte描画、HALTだけを作り、Stepで検証してから継続Loopへ進みます。

```asm
org 0
STATE equ 0x8000
VRAM equ 0xC000
start:
    ld sp,0xBFFF
    ld a,1
    ld (STATE),a
loop:
    ld hl,VRAM + 64
    ld (hl),0x18
    halt
    ; jp loop
```

Game StateはGeneral RAM、現在AddressはHL、有限LoopはCounter、描画は完成したVRAM byte Patternを使います。Assemble、Disassemble、Step、Memory/Display確認を行い、最後にHALTをJPへ変更します。

Pinponは継続LoopとGame Inputによる方向変更、Game of Lifeは交互Patternの例です。Project Manifestは未実装です。
