# Instruction Set Reference

[Index](README.md) | [日本語](instructions.ja.md)

This is the implemented subset. `r` means B/C/D/E/H/L/A, `rr` means BC/DE/HL/SP where the shown form permits it, and `n`/`nn` are 8/16-bit immediates.

| Family | Implemented forms |
|---|---|
| Control | NOP, HALT |
| Load | LD r,n; LD rr,nn; LD r,r; LD r,(HL); LD (HL),r; LD (HL),n; LD A,(nn); LD (nn),A; LD HL,(nn); LD (nn),HL |
| Arithmetic | ADD A,r/n; SUB r/n; CP r/n; INC/DEC r and HL |
| Logic | AND r/(HL)/n; XOR r/(HL)/n; OR r/(HL)/n |
| Branch | JP, JP Z/NZ; JR, JR Z/NZ; CALL; RET |
| Stack | PUSH/POP AF/BC/DE/HL |

Logic opcodes are AND `A0-A7/E6`, XOR `A8-AF/EE`, and OR `B0-B7/F6`. Register forms take 4 T-states, `(HL)` forms 7, and immediate forms 7. AND sets H; XOR/OR clear H; all set S/Z and even parity P/V from the result and clear N/C. Undocumented flag bits are not modeled.

General register LD uses Z80 codes B=0, C=1, D=2, E=3, H=4, L=5, (HL)=6, A=7. Register-to-register forms take 4 T-states; forms with one `(HL)` operand take 7. Encoding `76` remains HALT, so `LD (HL),(HL)` is invalid.

ADC, SBC, INC/DEC (HL), 16-bit ADD, DJNZ, CB bit/rotate/shift families, IX/IY, interrupts, and I/O remain unimplemented.

