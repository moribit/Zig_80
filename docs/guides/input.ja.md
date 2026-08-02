# 入力ガイド

[目次](README.ja.md) | [English](input.md)

実装済みInputは`C400`のMemory-mapped 1 byteです。bit 0〜6はUp、Down、Left、Right、A、B、Startです。CLI Debuggerで設定します。

```text
input 0x11
memory 0xC400 1
```

Programは`LD A,(0xC400)`で読みます。同時Buttonは複数Bitで表します。TUI Game Input Mode、Key Release、Recording/Replay、`--input-script`は未実装で、Roadmapの構文は現在のCLIでは使えません。

