# 04 Compare, branch, and loop: choose the next PC

[← Previous](03-memory.md) | [Contents](README.md) | [日本語](04-branch.ja.md) | [Next: Stack →](05-stack.md)

## Panels to watch

- **Source** labels, DEC, CP, JR, JP
- **CPU** PC, counter register, Z
- **Bus** repeated instruction addresses
- **Breakpoint** state

## Goal

Connect labels to addresses, watch Z select the next PC, and safely control finite and infinite loops.

```asm
ld b,3
loop:
    dec b
    jr nz,loop
    halt
```

```text
Step 1  B=03
Step 2  DEC: B=02, Z=0
Step 3  JR NZ: PC returns to DEC
Step 4  DEC: B=01, Z=0
Step 5  JR NZ: returns
Step 6  DEC: B=00, Z=1
Step 7  JR NZ: not taken; PC advances
Step 8  HALT
```

JR tests the flag left by DEC, not B directly. JP uses a 16-bit absolute target; JR uses an offset from the following instruction and is limited to -128…+127 bytes. Both support unconditional, Z, and NZ forms in Zig_80.

To observe a loop, put the cursor on DEC, press `Ctrl+B`, and use `Ctrl+E`. At `[BREAKPOINT]`, inspect B, Step DEC, then Continue to the next visit.

An infinite game loop is valid. Escape pauses it. TUI defaults stop at 10,000,000 instructions or 100,000,000 T-states and execute at most 500 instructions per cooperative UI tick.

## IDE Tips

- `Ctrl+B`: toggle breakpoint.
- `Ctrl+Space`: continue; Escape: pause.
- `Ctrl+]` or Enter on a label: definition.
- Alt+Left/Right: jump history.
- `Ctrl+F`: search labels.

## Challenge: five iterations

Change the initial B to five. Predict the number of DEC and JR executions. Use the breakpoint and record B at each visit rather than running directly to HALT.

[← Previous](03-memory.md) | [Contents](README.md) | [Next →](05-stack.md)

