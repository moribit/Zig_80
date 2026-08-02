# Profilerガイド（計画）

[目次](README.ja.md) | [English](profiling.md)

現在`profile` Commandはありません。当面はRun結果、TUIの命令/T-state Counter、Trace Buffer Metricを粗い調査に使います。Host経過時間をZ80性能として解釈しないでください。

将来のProfilerはAddress/Label別命令・T-state、Call、Branch結果、Memory/VRAM/I/O Access、Hot Loopを集計する構想です。CLI APIとAccounting Testを先行し、TUI Viewはその後です。Roadmap Phase 5を参照してください。

