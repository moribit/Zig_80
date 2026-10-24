# 命令セットリファレンス

[目次](README.ja.md) | [English](instructions.md)

現在実装されているSubsetです。`r`はB/C/D/E/H/L/A、`n`/`nn`は8/16 bit即値です。

| Family | 実装形式 |
|---|---|
| 制御 | NOP、HALT |
| Load | LD r,n、LD rr,nn、LD r,r、LD r,(HL)、LD (HL),r、LD (HL),n、絶対AddressのA/HL Read/Write |
| 算術 | ADD A,r/n、ADC A,r/(HL)/n、SUB r/n、SBC A,r/(HL)/n、CP r/n、INC/DEC r/(HL)/HL、ADD HL,BC/DE/HL/SP |
| 論理 | AND、XOR、ORのr/(HL)/n |
| 分岐 | JP、JP Z/NZ、JR、JR Z/NZ、DJNZ、CALL、RET |
| Stack | PUSH/POP AF/BC/DE/HL |
| Bit/Rotate | BIT/SET/RES b,r/(HL)、RLC/RRC/RL/RR/SLA/SRA/SRL r/(HL) |

論理演算のOpcodeはAND `A0-A7/E6`、XOR `A8-AF/EE`、OR `B0-B7/F6`です。Register形式4 T-state、`(HL)`形式7、即値形式7です。ANDはHをSet、XOR/ORはHをClearし、全て結果からS/Zと偶数ParityのP/Vを設定しN/CをClearします。非Document Flag BitはModel化しません。

一般LDのRegister CodeはB=0、C=1、D=2、E=3、H=4、L=5、(HL)=6、A=7です。Register間は4 T-state、片方が`(HL)`なら7です。`76`はHALTなので`LD (HL),(HL)`は不正です。

ADC/SBCはRegister形式4 T-state、`(HL)`形式7、即値形式7です。`INC/DEC (HL)`は11、`ADD HL,rr`は11です。16 bit ADDはH/N/Cを変更しS/Z/PVを保存します。`DJNZ`は分岐時13、非分岐時8です。

CB PrefixのRegister操作は8 T-stateです。`BIT b,(HL)`は12、`(HL)`を変更する操作は15です。BITはCを保存、HをSet、NをClearし、対象BitからS/Z/PVを設定します。SET/RESはFlagを変更しません。Rotate/Shiftは結果からS/Z/PV/Cを設定してH/NをClearします。

上表は旧Subsetの説明です。現在の全対応形式・命令長・T-stateは[生成カバレッジ表](../development/cpu-coverage.md)を参照してください。IX/IY、ED、I/O、割り込みに対応しました。[CPU契約](../architecture/cpu.md)に制限を記載しています。SLLは未対応です。
