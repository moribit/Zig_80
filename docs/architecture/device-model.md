# Devices and scheduling / デバイスとスケジューリング

Framebuffer, abstract display controller, Bus port adapter and frontend renderer
are separate modules. Banks and devices use fixed-capacity value state, with no
heap allocation in stepping. Cpu has no concrete device imports.

`Machine.step` presents pending device INT before executing/accepting one CPU
step, then advances devices by the returned T-states. Timer expiry during an
instruction becomes visible at the next instruction boundary. Frame phase adds
T×frame_hz and carries at clock_hz, preserving fractional periods. Timer phase
carries at a configurable nonzero 16-bit T-state period. Both counters wrap with
explicit arithmetic; IRQ remains latched until acknowledged. CPU reset does not
acknowledge it. Masked timers still progress. INT/NMI behavior is in the CPU contract.

Headless budgets use emulated instructions/T-states. HALT idle advances four T
without retiring an instruction. CLI/TUI continue HALT when an enabled interrupt
source can wake it; execution limits still apply. With no wake source, HALT ends
execution as before. Instruction-indexed input is applied before each step; equal
indices keep source order. Events scheduled after a halted instruction require an
interrupt to advance that timeline. No device reads OS wall time.

TUI runs cooperative batches and is not a real-time clock emulator. `clock.Pacer`
converts frontend-provided elapsed nanoseconds into T-state budgets with fractional
carry for future paced frontends. The caller supplies durations; deterministic
headless execution never uses it.

日本語: 命令完了後にT-stateでデバイスを進め、発生したIRQは次の命令境界で受理します。
Timer・Frameの位相は整数で保持し、OSの時刻に依存しません。HALT待機でもT-stateは進みます。
TUIの実行速度は協調バッチであり実時間同期ではありません。実時間の予算変換は独立したPacerで
行えます。入力Replayの基準は命令番号で、HALT中の将来イベントには割り込みによる復帰が必要です。
