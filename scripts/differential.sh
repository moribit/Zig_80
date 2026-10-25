#!/bin/sh
# Optional network-assisted development check; not part of normal build/test.
set -eu
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir/.."
cache_dir=${SST_CACHE_DIR:-.zig-cache/sst-z80}
mkdir -p "$cache_dir"
revision=ebe1875d48f374bcfd4b505d8eb8ee751568b5f7
base="https://raw.githubusercontent.com/SingleStepTests/z80/$revision"
curl -fsSL "$base/LICENSE" -o "$cache_dir/LICENSE"
set --
for name in 00 07 09 10 27 34 76 86 8e 96 9e be c4 c5 ed%2042 ed%204a ed%2057 ed%2067 ed%206f ed%20a0 ed%20b0 ed%20b1 dd%2021 dd%2036 dd%2066 dd%20cb%20__%2046 fd%2086; do
    path="$cache_dir/$revision-$name.json"
    if [ ! -f "$path" ]; then
        curl -fsSL "$base/v1/$name.json" -o "$path.tmp"
        mv "$path.tmp" "$path"
    fi
    set -- "$@" "$path"
done
"${ZIG:-zig}" build differential -- "$@"
