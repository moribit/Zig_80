#!/bin/sh
set -eu

usage() {
    printf '%s\n' 'Usage: install.sh [--prefix DIR]' \
        'Build and install zig80 into DIR/bin (default: $HOME/.local).' \
        'Requires Zig 0.16 or a compatible version on PATH; set ZIG to override.'
}

prefix=${HOME:?HOME must be set}/.local
while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                printf '%s\n' 'error: --prefix requires a directory' >&2
                exit 1
            fi
            prefix=$2
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done

# Resolve relative prefixes before changing to the source directory.
case "$prefix" in
    /*) ;;
    *) prefix=$PWD/$prefix ;;
esac
zig=${ZIG:-zig}
if ! command -v "$zig" >/dev/null 2>&1; then
    printf 'error: Zig compiler not found: %s\n' "$zig" >&2
    exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$script_dir/.."
"$zig" build -Doptimize=ReleaseFast
mkdir -p "$prefix/bin"
install -m 755 zig-out/bin/zig80 "$prefix/bin/zig80"
printf 'Installed zig80 to %s/bin/zig80\n' "$prefix"
case ":${PATH:-}:" in
    *":$prefix/bin:"*) ;;
    *) printf 'Add %s/bin to your PATH to run zig80.\n' "$prefix" ;;
esac
