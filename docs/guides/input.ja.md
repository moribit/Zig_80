# 入力ガイド

[目次](README.ja.md) | [English](input.md)

実装済みInputは`C400`のMemory-mapped 1 byteです。bit 0〜6はUp、Down、Left、Right、A、B、Startです。CLI Debuggerで設定できます。

```text
input 0x11
memory 0xC400 1
```

Programは`LD A,(0xC400)`で読みます。同時Buttonは複数Bitで表すため、全byteを比較せず`AND`で対象Bitを分離します。

TUIでは`Ctrl+G`でGame Input Modeへ入ります。Arrowまたは小文字WASDが方向、J/KがA/B、SpaceがStartです。大文字WASD/J/Kは明示Releaseです。一般的なTerminalはnative Key-up Eventを送らないため、Arrowは短いRepeat Window後にReleaseされます。Escapeは全ButtonをReleaseしてModeを抜けます。Mode中はEditorを変更せず、Status Barへ現在maskを表示します。Command Paletteの`save input recording`は`zig80-input.txt`を書きます。

`zig80 run game.bin --input-script input.txt`で決定的なHeadless Replayを行えます。各行は`<instruction-index> press|release <button>`です。Wall Clockや偽のZ80 timingではなく実行命令順を使います。
