#!/bin/sh
# Build only: never discovers, flashes, resets, or opens a hardware device.
set -eu
cd "$(dirname "$0")/../.."
: "${PICO_SDK_PATH:?Set PICO_SDK_PATH to Pico SDK 2.3.0}"
sdk_commit=98a542c1a62fb549ffb5d66a3e5892b06276b670
usb_commit=86ad6e56c1700e85f1c5678607a762cfe3aa2f47
test "$(git -C "$PICO_SDK_PATH" rev-parse HEAD)" = "$sdk_commit" || {
  echo "Wrong SDK revision; expected $sdk_commit" >&2; exit 1;
}
test "$(git -C "$PICO_SDK_PATH/lib/tinyusb" rev-parse HEAD)" = "$usb_commit" || {
  echo "Wrong TinyUSB revision; initialize the pinned SDK submodules" >&2; exit 1;
}
build_dir=.zig-cache/pc8001/firmware
if test -n "${PICO_TOOLCHAIN_PATH:-}"; then
  cmake -S hardware/pico2-pc8001/firmware -B "$build_dir" -G Ninja \
    -DPICO_SDK_PATH="$PICO_SDK_PATH" -DPICO_TOOLCHAIN_PATH="$PICO_TOOLCHAIN_PATH" \
    -DCMAKE_BUILD_TYPE=Release
else
  cmake -S hardware/pico2-pc8001/firmware -B "$build_dir" -G Ninja \
    -DPICO_SDK_PATH="$PICO_SDK_PATH" -DCMAKE_BUILD_TYPE=Release
fi
cmake --build "$build_dir" --parallel "${JOBS:-4}"
mkdir -p zig-out/pc8001
cp "$build_dir/pico2_pc8001.uf2" "$build_dir/pico2_pc8001.elf" zig-out/pc8001/
echo 'Built zig-out/pc8001/pico2_pc8001.uf2 (NOT flashed; disconnect PC-8001 before flashing)'
