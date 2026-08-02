# Assembler Reference

[Index](README.md) | [日本語](assembler.ja.md)

The two-pass assembler supports case-insensitive symbols, labels and forward references, and `;` comments.

```asm
org 0x0000
VRAM equ 0xC000
start:
    ld hl,VRAM + 64
    db "HELLO",0
    dw start,0x1234
```

Values may be decimal, `0x` hexadecimal, `0b` binary, a one-byte character such as `'A'`, a symbol, or current logical address `$`. Expressions support recursive `+` and `-` only. Arithmetic parentheses, multiplication, division, modulo, shifts, and bitwise operators are not implemented.

`org` changes the logical address but does not pad the output file. `db` emits bytes or strings, `dw` emits little-endian words, and `equ` defines a symbol. Includes, binary includes, sections, listings, and symbol/source-map files are not implemented.

The in-memory Result contains output bytes, label/value symbols, and source-line/address entries. Assembly stops at the first structured diagnostic.

