# PC-8001 / Pico 2 serial validation

Experimental, 300 baud, 8N1, inverted UART on GP0 (TX) / GP1 (RX).
**No PC-8001 electrical measurements or physical communication have been performed.**
Disconnect all PC-8001 signal wires before the first firmware flash or Pico-only loopback.
An inline 1 kΩ resistor is not a voltage converter. Never connect S10 pins 11/13/15
to GPIO. See the [measurement and staged validation procedure](../../docs/pc8001-serial-validation.md)
before connecting or enabling an output.

## Build (never flashes)

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
The PIO simulator does not establish pad voltages, oscillator accuracy, USB electrical
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
