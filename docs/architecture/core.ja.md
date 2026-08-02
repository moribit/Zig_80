# Core責務境界

[目次](README.ja.md) | [English](core.md)

```text
Assembler ── bytes/symbols/source map ──┐
                                         ▼
CLI / TUI ── DebugSession ── Machine ── CPU
                              │
                              ├─ Bus / TraceSink
                              └─ Memory-mapped devices
```

- CPUは命令SemanticsとTiming総数を担当し、FileやUIを扱いません。
- BusはAddress空間と任意のLogical Eventを担当します。
- MachineはCPU、Bus、Device同期を統合します。
- AssemblerはFrontend挙動を持たずbyteとSource Metadataを生成します。
- Disassemblerは実行せずbyteをDecodeします。
- DebugSessionは共有実行Stateを保存し、Frontend Policyを持ち込みません。
- CLI/TUIはCore APIを直接呼び、互いを子Process起動しません。

Tutorial進行、Quiz、Terminal Key、Hardware固有の電気挙動はCPU/Machineへ入れません。

