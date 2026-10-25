# Banking / Bank切替

The 64 KiB logical address is split into four 16 KiB windows. `Banks.slots` maps
logical slots to physical ROM/RAM banks; CPU sees only logical addresses. Counts
are 2–4 banks per kind, fixed capacity four (no heap). Default mapping and port
registers are in [memory map](../architecture/memory-map.md).

Program load accepts up to 32 KiB into ROM banks 0/1. Additional banks are loaded
through `Machine.loadRomBank(index, bytes)` or CLI `--rom-bank N FILE` (max 16 KiB
each). Loading clears that bank's unused tail. CPU cannot modify ROM. RAM bank
switching preserves each bank's data. Machine reset preserves all ROM, clears all
RAM and restores the initial map. Power-on/load clears all banks.

`Banks.snapshot` captures mapping/counts; versioned Machine snapshot additionally
exports every configured physical bank and the entire logical address space.
Boundary tests cover 3FFF/4000, switching and invalid maps; generic word accesses
wrap at FFFF. VRAM is independent and reached through display ports.

日本語: 論理アドレスと物理Bankを分離し、ROM/RAMをそれぞれ最大64KiB保持します。
追加ROMはAPIまたはCLIでロードでき、Snapshotには物理Bankも含めます。
実機のBankレジスタと窓サイズが確定するまでは暫定方式です。
