# Displayプログラミングガイド

[目次](README.ja.md) | [English](display.md)

Default Displayは128×64、1bppで、VRAM 1 byteが縦8 Pixelを表します。

```text
address = C000 + (y / 8) * 128 + x
bit     = y % 8
mask    = 1 << bit
```

byteを計算してWriteし、Memory Write Eventを選び、Pixel Inspectorの座標、Address、Bit、Valueで確認します。PaletteのScale/GridはVRAM配置を変更しません。Dirty Highlightは直近Writeを示します。

現在は固定1bpp仕様だけです。Sprite、Tile、LCD、SSD1306、別Displayは将来のProfile/Asset作業です。

