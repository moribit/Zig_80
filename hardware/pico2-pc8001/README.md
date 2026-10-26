# PC-8001 / Pico 2 serial validation

[PC-8001: 100-byte bootstrap / 初回導入の小型化](../../docs/pc8001-bootstrap.md)

Experimental, 300 baud, 8N1, inverted UART on GP0 (TX) / GP1 (RX).
**Physical strings have now passed in both directions; PC-8001 binary/loader deployment remains unverified.**
TERM still shows `*` around host transmissions while TX is Hi-Z; the electrical cause
has not been measured. See the dated [validation record](../../docs/pc8001-serial-validation.md).
Disconnect all PC-8001 signal wires before the first firmware flash or Pico-only loopback.
An inline 1 kΩ resistor is not a voltage converter. Never connect S10 pins 11/13/15
to GPIO. See the [measurement and staged validation procedure](../../docs/pc8001-serial-validation.md)
before connecting or enabling an output.

## Build (never flashes)

Firmware 0.1.1 adds read-only USB HEALTH (command 11): uptime, main-loop count,
largest observed loop interval, watchdog reboot and watchdog-timeout reboot flags.
`zig80 serial health --port PATH` reads them with UART disabled. The flags are
captured before watchdog initialization and survive USB open/close within a boot.
`serial probe` records HEALTH once per second on 0.1.1. Boot Hi-Z, 250 ms watchdog,
one-second TX lease, UART framing and USB framing are unchanged. This is diagnostic
instrumentation, not a confirmed fix for the observed USB re-enumerations.

0.1.2 additionally retains the main-loop phase in watchdog scratch[0] and reports
it after watchdog reboot. HEALTH appends a little-endian uint32 phase (31 bytes
including status); hosts still accept the 0.1.1 reply. Values are 0=unknown/init,
1=USB task, 2=safety/tick, 3=USB commands, 4=RX, 5=TX, 6=USB flush, 7=sleep.
SDK scratch[4..7], all deadlines and the loop wait implementation are unchanged.

0.1.3 changes only the short loop delay from `sleep_us(50)` to
`busy_wait_us_32(50)`, following a physical watchdog-timeout reproduction whose
retained phase was 7 (sleep). This avoids the alarm/WFE sleep path without
disabling interrupts or extending the watchdog/lease. It uses CPU polling during
the 50 us delay. SDK-internal fault location remains unproven; physical stability
of this fix must be measured separately from the native protocol tests.
UF2 program metadata now derives its version from BRIDGE_VERSION as well.

0.1.4 runs the RX state machine at 16 cycles per bit (4800 Hz at 300 baud),
while TX stays at 8 cycles per bit (2400 Hz). RX samples at bit centers as before,
but can rearm during a single stop bit before the next frame starts. A regression
using 256 back-to-back bytes, both polarities, four asynchronous phases and peer
bit periods from -2% to +2% failed on the old RX and passes on this version.
The CONFIG divider field remains the TX divider for USB compatibility; at
150 MHz its Q8 value is 16,000,000, and RX uses 8,000,000. Both remain 300 baud.
The model is not an electrical measurement or proof that the observed PC-8001
framing fault is resolved. Physical PC roundtrip validation is still required.

日本語：0.1.1は起動経過時間・ループ間隔・watchdog再起動フラグの取得を追加した診断版です。
USB切断原因を直した版とは扱いません。PC-8001の電源OFF・信号線切り離し後にのみ書き込みます。

Install CMake, Ninja, an ARM bare-metal GCC toolchain and picotool. Pin the SDK:

```sh
git clone https://github.com/raspberrypi/pico-sdk.git .zig-cache/pico-sdk
git -C .zig-cache/pico-sdk checkout 98a542c1a62fb549ffb5d66a3e5892b06276b670
git -C .zig-cache/pico-sdk submodule update --init --recursive
export PICO_SDK_PATH="$PWD/.zig-cache/pico-sdk"
# Set PICO_TOOLCHAIN_PATH to the directory containing arm-none-eabi-gcc if needed.
sh hardware/pico2-pc8001/build.sh
```

Outputs: `zig-out/pc8001/pico2_pc8001.{uf2,elf}`. SDK 2.3.0 and its TinyUSB commit
are checked by the script. The validated compiler and archive checksum are in
[toolchain-lock.json](toolchain-lock.json). Host code uses Zig 0.17.0; firmware is C11
and the Pico SDK, with no RTOS or heap-based queues. CMake may use installed
picotool or fetch the SDK-selected version if absent; preinstall it for offline builds.
Record the compiler/CMake/Ninja/picotool versions when reproducing a build.

## Test without hardware

```sh
ZIG=/path/to/zig-0.17.0/zig sh hardware/pico2-pc8001/test.sh
```

Requires a native C compiler and Python 3. Runs the ASan/UBSan bridge tests,
PIO instruction-subset simulation, the normal Zig suite, assembly artifact generation,
and six real CLI ↔ PTY ↔ C protocol-core mock tests. It never opens a physical port.
The suite also builds the optional C bridge + existing Z80 loader fixture and runs
eleven deploy PTY integration tests. The PIO simulator does not establish pad voltages, oscillator accuracy, USB electrical
behavior, or communication with a real 8251.

## Explicit operations

```sh
zig build run -- serial --help
zig build run -- serial build-examples
zig-out/bin/zig80 serial list
zig-out/bin/zig80 serial info --port /dev/cu.usbmodemXXXX
zig-out/bin/zig80 serial monitor --port /dev/cu.usbmodemXXXX --log receive.jsonl
```

Every connection starts disarmed. GPIO output requires **both** `--enable-tx` and
`--voltage-confirmed`, followed by a firmware ARM command. These flags are a human
assertion of measurements, not a measurement or an electrical interlock. Do not add
them until the appropriate staged procedure has passed. The firmware revokes output
on DTR loss, disconnect/suspend, malformed commands, timeout or lease expiration.
Boot and disarm disable output, pulls and the input buffer on GP0 (including the
RP2350 A2 E9 leakage mitigation). Hardware isolation is needed for a stronger
power-off or arbitrary-fault guarantee.

日本語の接続・測定・N-BASIC・初回ロード・Phase A〜Eの手順は
[検証手順書](../../docs/pc8001-serial-validation.md)を参照してください。
