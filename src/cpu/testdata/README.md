# Golden contract / Goldenの前提

`store.asm` starts with all registers zero except SP=FFFF, zero-filled memory,
PC=0000, no input, no devices advanced. Trace is **logical**, not cycle-accurate.
`store.golden` is a manually reviewed expected encoding, disassembly, CPU state
after each instruction, ordered bus accesses and final memory/result.
It covers LD A,n; ADD A,n signed overflow/half carry; LD (nn),A; HALT.
Flags compare documented S/Z/H/PV/N/C only. This is a small integration golden,
not evidence of complete instruction compatibility. Update it only after reviewing
the architectural change; tests never regenerate expectations.

日本語: 全レジスタ0（SPのみFFFF）、メモリ0、PC=0000から開始します。
命令エンコード、逆アセンブル、各命令後のCPU、メモリ書込み、論理バス順、
最終結果を手動確認した固定データと比較します。サイクル精密性は検証しません。
