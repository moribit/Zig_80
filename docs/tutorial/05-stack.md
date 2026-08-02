# 05 Subroutines and the Stack: remember where to return

[← Previous](04-branch.md) | [Contents](README.md) | [日本語](05-stack.ja.md) | [Next: Display →](06-display.md)

## Panels to watch

- **Source** CALL, RET, PUSH, POP
- **CPU** PC and SP
- **Memory** bytes near SP
- **Bus** Stack reads and writes

## Goal

Explain why CALL changes both PC and SP, observe a downward-growing LIFO Stack, and save register pairs safely.

## How the Z80 works

CALL stores the return address on a memory Stack and replaces PC. RET restores that address. The Z80 Stack grows toward lower addresses.

## Try it with the CLI

Save the source below as `call.asm`, assemble it, then use `step` and `memory 0xBFF0 16`.

```console
zig build run -- asm call.asm -o zig-out/call.bin
zig build run -- debug zig-out/call.bin
```

## Observe it in the TUI

```console
zig build run -- tui call.asm
```

```asm
org 0x0000
start:
    ld sp,0xBFFF
    ld a,1
    call twice
    halt
twice:
    add a,a
    ret
```

## Step through the call

```text
LD SP,BFFF   SP FFFF→BFFF
LD A,1       A 00→01
CALL twice   PC→twice, SP BFFF→BFFD
             Bus writes the return address to BFFD/BFFE
ADD A,A      A 01→02
RET          Bus reads the address, SP BFFD→BFFF, PC→HALT
```

The Z80 Stack grows toward lower addresses. Initializing SP at the end of general RAM avoids casually colliding with VRAM or reserved devices. CALL pushes the following address; RET pops it into PC.

Register pairs can be preserved with `PUSH AF|BC|DE|HL` and restored in reverse order with POP. An unbalanced Stack can corrupt not only a register but also RET's address.

## IDE Tips

- Go to `BFF0` in Memory to watch the Stack.
- Step CALL and RET separately while watching PC and SP together.
- A Memory Write Bus filter exposes CALL's saves.
- Put a breakpoint at the subroutine entry.

## Challenge: preserve AF

Inside `twice`, PUSH AF, change A, then POP AF. Confirm that A returns and SP decreases and recovers.

[← Previous](04-branch.md) | [Contents](README.md) | [Next →](06-display.md)
