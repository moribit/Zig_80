# Buttons and replay / ボタンとReplay

Default bits: Up=0, Down=1, Left=2, Right=3, A=4, B=5, Start=6; bit 7 is reserved.
The shared State supports simultaneous press/release. Classic reads C400;
handheld polls port 10. Optional input-change IRQ is enabled via port 11 bit 0;
any changed bit latches pending, including release, acknowledged with bit 7.
The layout/port boundary can change without changing CPU code.

Script lines are `instruction press|release button`, decimal unsigned instruction
index. Blank/comment (#) lines are allowed. Equal timestamps preserve file order.
The initial mask is zero. Replay.reset rewinds state; backwards advance rewinds
implicitly. See [quality contracts](../development/quality-improvements.md).
TUI Game Input uses the established keymap and records instruction-indexed events.
Interactive key release timeouts are frontend wall-clock behavior; the resulting
recorded timeline replays deterministically. Native key-up remains unavailable.

日本語: 同時押し・明示Release・命令番号Replayを共通モデルで扱います。HandheldはPollingまたは
入力変化IRQを選べます。Keymapは既存TUIを維持し、CPUは入力配置を知りません。
命令番号のScriptはHALT待機中に先へ進まないため、Timerなどの復帰源を使用してください。
