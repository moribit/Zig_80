#!/bin/sh
# Native mocks and software simulation only. No serial device is opened.
set -eu
cd "$(dirname "$0")/../.."
zig_bin=${ZIG:-zig}
cc_bin=${CC:-cc}
mkdir -p .zig-cache/pc8001
"$cc_bin" -std=c11 -Wall -Wextra -Werror -g -fsanitize=address,undefined \
  hardware/pico2-pc8001/firmware/bridge.c hardware/pico2-pc8001/tests/core_test.c \
  -o .zig-cache/pc8001/core_test
.zig-cache/pc8001/core_test
"$cc_bin" -std=c11 -Wall -Wextra -Werror -D_POSIX_C_SOURCE=200809L \
  hardware/pico2-pc8001/firmware/bridge.c hardware/pico2-pc8001/tests/protocol_mock.c \
  -o .zig-cache/pc8001/protocol_mock
python3 hardware/pico2-pc8001/tests/test_pio.py
"$zig_bin" build
"$zig_bin" build test --summary all
"$zig_bin" build run -- serial build-examples
python3 hardware/pico2-pc8001/tests/test_host.py
