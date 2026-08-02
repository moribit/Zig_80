# 命令セットリファレンス

[目次](README.ja.md) | [English](instructions.md)

現在実装されているSubsetです。`r`はB/C/D/E/H/L/A、`n`/`nn`は8/16 bit即値です。

| Family | 実装形式 |
|---|---|
| 制御 | NOP、HALT |
| Load | LD r,n、LD rr,nn、LD r,r、LD r,(HL)、LD (HL),r、LD (HL),n、絶対AddressのA/HL Read/Write |
| 算術 | ADD A,r/n、SUB r/n、CP r/n、INC/DEC rとHL |
| 論理 | AND、XOR、ORのr/(HL)/n |
| 分岐 | JP、JP Z/NZ、JR、JR Z/NZ、CALL、RET |
| Stack | PUSH/POP AF/BC/DE/HL |

論理演算のOpcodeはAND `A0-A7/E6`、XOR `A8-AF/EE`、OR `B0-B7/F6`です。Register形式4 T-state、`(HL)`形式7、即値形式7です。ANDはHをSet、XOR/ORはHをClearし、全て結果からS/Zと偶数ParityのP/Vを設定しN/CをClearします。非Document Flag BitはModel化しません。

一般LDのRegister CodeはB=0、C=1、D=2、E=3、H=4、L=5、(HL)=6、A=7です。Register間は4 T-state、片方が`(HL)`なら7です。`76`はHALTなので`LD (HL),(HL)`は不正です。

ADC、SBC、INC/DEC (HL)、16 bit ADD、DJNZ、CB Bit/Rotate/Shift、IX/IY、Interrupt、I/Oは未実装です。

