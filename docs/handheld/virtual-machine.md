# Virtual machine / 仮想マシン

Use `--profile handheld` for CLI run or TUI. `--clock-hz N` changes the emulated
clock used for frame scheduling. The default is 4 MHz, 60 frames/sec, timer period
40,000 T-states (disabled at reset). API users configure all values/ports through
`profile.Config`; frame_hz must be nonzero and no greater than clock_hz.

| Low-byte port | Read | Write |
|---|---|---|
| 10 | pressed button bitmask | ignored |
| 11 | input IRQ enable bit 0, pending bit 7 | bit 0 enable; bit 7 acknowledge |
| 20 / 21 | ROM / RAM bank index | select bank for slot 1 / 2 |
| 30 | timer enable bit 0, pending bit 7 | bit 0 enable; bit 7 acknowledge |
| 31 / 32 | timer count low / high | ignored |
| 33 / 34 | timer period low / high | set period; zero result ignored |
| 40 / 41 | FF | display address low / high |
| 42 | display byte, then increment | display byte, then increment |
| 43 | FF | bit 0 clear display and address |

Timer count is a wrapping 16-bit value; reading halves is not latched. A program
requiring a coherent concurrent read should repeat high/low/high. Disabling timer
clears its phase; acknowledging IRQ does not clear count. IM1 timer/input IRQ use
RST 38; source status is read/acknowledged by the handler. Ports are configurable.

Samples: pixel, moving, buttons, timer, interrupt, banking. All run in headless
unit tests with memory/display assertions. `buttons.input` demonstrates simultaneous
presses. `--max-instructions` and `--max-cycles` bound CLI execution.

日本語: Port表は確定した実機仕様ではなく、変更可能な仮想仕様です。TimerのIRQはACKまで保持し、
16bitカウンタはラッチしません。サンプル6本はすべてHeadlessで結果を検証します。
