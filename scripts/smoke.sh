#!/bin/sh
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir/.."
binary=${ZIG80:-./zig-out/bin/zig80}
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/zig80-smoke.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
"$binary" --help >/dev/null
"$binary" asm examples/pixel.asm -o "$work_dir/classic.bin"
"$binary" test "$work_dir/classic.bin"
result=$("$binary" run "$work_dir/classic.bin")
case "$result" in *'instructions=3, T-states=24, PC=0x0006'*) ;; *) printf '%s\n' "$result"; exit 1 ;; esac
"$binary" disasm "$work_dir/classic.bin"
for name in pixel moving buttons timer interrupt banking; do
    "$binary" asm "examples/handheld/$name.asm" -o "$work_dir/$name.bin"
    "$binary" run "$work_dir/$name.bin" --profile handheld --max-instructions 100000 --snapshot "$work_dir/$name.json" --export-frame "$work_dir/$name.pbm"
done
"$binary" run "$work_dir/buttons.bin" --profile handheld --input-script examples/handheld/buttons.input --snapshot "$work_dir/replay1.json"
"$binary" run "$work_dir/buttons.bin" --profile handheld --input-script examples/handheld/buttons.input --snapshot "$work_dir/replay2.json"
cmp "$work_dir/replay1.json" "$work_dir/replay2.json"
printf 'ld (ix+0),0x42\nhalt\n' > "$work_dir/indexed.asm"
"$binary" asm "$work_dir/indexed.asm" -o "$work_dir/indexed.bin"
result=$("$binary" disasm "$work_dir/indexed.bin")
case "$result" in *'DD 36 00 42'*) ;; *) printf '%s\n' "$result"; exit 1 ;; esac
printf '%s\n' 'CLI smoke, samples, four-byte disassembly and replay comparison passed.'
