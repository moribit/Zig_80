# Handheld development / ハンドヘルド開発

This is a provisional software validation target for future Z80 handheld hardware.
No board, transport, Noritake model, controller protocol or physical connector is
specified or implemented. Classic remains the default environment.

```sh
zig build
zig-out/bin/zig80 asm examples/handheld/pixel.asm -o /tmp/pixel.bin
zig-out/bin/zig80 run /tmp/pixel.bin --profile handheld --export-frame /tmp/pixel.pbm --snapshot /tmp/pixel.json
zig-out/bin/zig80 tui examples/handheld/interrupt.asm --profile handheld
```

[VM](virtual-machine.md), [display](display.md), [input](input.md),
[banking](memory-banking.md), [hardware boundary](hardware-debugging.md).

日本語: Mac上で同じCoreを使ってソース編集・実行・Debug・Snapshot比較を行うための仮想対象です。
実機の通信や回路設計は含みません。将来同一バイナリを実機で動かすには、暫定PortとBank方式を
実機仕様に合わせて確定する必要があります。
