# 将来Hardware Target境界

[目次](README.ja.md) | [English](hardware-target.md)

将来Targetは、CPUから見えるMemory/I/O挙動のVersion付きMachine仕様を実装する方向を検討しています。Emulator DeviceとZig Firmwareの内部が異なっても共通Conformance Vectorを通す必要があります。Transfer/USB Debug ProtocolはCPU Semanticsの外側です。回路、Voltage互換、計測Timingは独立Review対象です。

現在、実機Target、Firmware、Protocol、PCBは未実装です。[Hardware Guide](../guides/hardware-basics.ja.md)を参照してください。

