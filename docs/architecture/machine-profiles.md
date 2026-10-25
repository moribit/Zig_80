# Machine profiles / Machine Profile

`Machine.init(Config)` validates the clock, frame rate, bank counts and unique
8-bit port assignments. Default `.classic` preserves the original 64 KiB map,
128×64 page display and writable program region. `.handheld` selects banked
ROM/RAM and independent 256×64 display/controller, buttons and timer.
CPU uses Bus only; device advancement belongs to `Machine.step()`. CLI, debugger,
TUI and headless runner all use that entry point. Calling `Cpu.step()` directly
is appropriate for CPU tests, but intentionally does not tick Machine peripherals.

`Machine.load` performs power-on reset while retaining configuration/trace/port
attachments. `reset` preserves ROM banks, clears RAM and restores mappings and
peripherals. `resetCpu` preserves all device state; `resetPeripherals` leaves CPU,
ROM, RAM and bank mapping intact. `loadRomBank` clears the selected physical ROM
bank before copying, without resetting CPU. Invalid loads/maps have no side effects.
See [reset table](../development/quality-improvements.md).

日本語: Classicを既定として既存マップを保持します。Handheldは固定容量のBank、独立画面、
入力、Timerを追加します。周辺機器を進める場合はCPU直接呼出しではなく `Machine.step()` を
使用します。ResetはROMを保持し、RAM・Mapping・周辺状態を初期化します。
このProfileは仮想検証用であり、実機仕様の確定を意味しません。
