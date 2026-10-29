# PC-8001 serial loader memory profile v1

100 Bの新Stage 0（E300–E363）、333 B中継、既存常駐ローダーの接続仕様・初回手順は [bootstrap補足](pc8001-bootstrap.md) を参照してください。

対象は初代PC-8001、N-BASIC、RAMに余裕を予約した開発用構成です。PC-8801/mkIIのバンクや
ROMルーチンを流用しません。`CLEAR 300,&HCFFF` が成功すること、E400hへのDATA/POKEと
読み戻しCRCが成功することが実機での開始条件です。RAM増設量やROM版を自動検出したとは扱いません。

根拠は [NEC PC-8001B User's Manualのメモリマップとモニタ説明](https://oldcrap.org/wp-content/uploads/2024/07/nec-pc8001b-users-manual.pdf)、
[初代PC-8001シリアル実装作者の調査](https://kuninet.org/2021/04/27/pc-8001%E5%86%85%E8%94%B5%E3%82%B7%E3%83%AA%E3%82%A2%E3%83%AB%E3%81%A7%E3%83%91%E3%82%BD%E3%82%B3%E3%83%B3%E3%81%A8%E9%80%9A%E4%BF%A1/)です。
後者はEA66hのport30保存値と、CLEARによる機械語領域予約を使用しています。
NEC資料のBモデルと所有機の差異は実機で確認し、配置の自動互換性を保証しません。

| アドレス（両端含む） | 用途・契約 |
| --- | --- |
| 0000–5FFF | BASIC ROM。転送禁止 |
| 6000–7FFF | 拡張ROM領域。転送禁止 |
| RAM開始位置–CFFF | N-BASICプログラム・文字列・USR呼出し元スタック。転送禁止 |
| **D000–D7FF** | **アプリ転送許可範囲、最大2,048byte** |
| D800–DCFF | Stage 1固定イメージ1,280byte（コード1,234byte＋ゼロ埋め） |
| DD00–E3FF | 予約。現在は転送許可しない |
| E400–E5FF | Stage 0予約512byte。実コード333byte、末尾E54C |
| E600–E64F | 受信フレーム80byte |
| E650–E69F | 前回受理した要求のコピー80byte |
| E6A0–E6EF | 前回の応答キャッシュ80byte |
| E6F0–E6FF | 予約 |
| E700–E7FF | ローダーのプライベートスタック256byte。SP初期値E800 |
| E800–E83F | 保存SP、port30、診断、転送メタデータ |
| E840–E84F | 予約 |
| E850–E89F | NAK/復帰通知作成中の応答キャッシュ退避80byte |
| E8A0–E8FF | 予約 |
| **E900–FFFF** | **全域転送禁止。BASICワーク・表示・scratchpadを保守的に保護** |
| EA66 | N-BASICのport30保存値。読み取りのみ |
| F300–FEB7 | 標準テキストVRAM（NEC資料）。ローダーからの転送は禁止 |

最初の案だった「Stage 0=E900、Stage 1=D000」は採用していません。E900以上を保守的に除外し、
D000をサンプルアプリの既定配置に残しています。どのアプリも任意のRAM全域へ置けるわけではありません。
4KB/8KBアプリは現プロファイルでは拒否します。拡大は所有機のRAM・BASICワークを調査して別プロファイルで行います。

転送前にホストとZ80の両方が `size>0`、`load>=D000`、`load+size<=D800`、
加算のラップなし、`load<=entry<load+size` を確認します。DATAはさらに受信済みoffsetとlengthを検証します。
VERIFYは転送時の累積値だけでなく、**配置済みRAMをもう一度読みCRCを再計算**します。
Stage 0は固定範囲D800–DCFFにしか書きません。境界・予約領域は既存CPUを使うテストで確認します。
定数は `examples/pc8001/loader/layout.inc` と `src/serial/loader_protocol.zig` にあり、
HELLOの領域情報・固定長・実イメージサイズをテストとCLIで照合します。

## 開発アプリABI

- 初期SPはE800付近のローダー専用スタック、マスク可能割り込みはDI。レジスタ値は未規定。
- 通常は `RET` でStage 1へ戻る。専用の復帰ベクタ `JP D803h` はSPとUARTを再初期化する。
- アプリのスタック消費は256byte以内、上記のローダーコード/バッファ/状態を変更しない。
- BASICは稼働していない。ROMの推測アドレスを呼ばない。helloはport30保存値EA66のbit0に応じて
  F300hから80文字モードで1byte、40文字モードで2byte間隔の文字セルへ直接書き、属性領域は変更しない。
  表示モードとUART設定は保持する。復帰Aは0=40文字、1=80文字。
- memory_testのD700–D710はアプリ用スクラッチ。D710は結果（0=一致）。
- orbital_ringsはD4E0–D4E5を状態、D500–D77Fを画面属性の保存に使う。
  これらはアプリ所有RAMで、常駐コードとは重ならない。描画属性は復帰前に元へ戻す。
- invadersはD700–D729とD7E0–D7E4を状態として使う。開始/リトライ時はVRAM全25行を初期化し、
  ESC/STOP終了時は標準テキスト属性と終了表示にする。元の画面内容の復元は行わない。
- UARTはEXECの最終ACK/停止ビット完了後からアプリが所有し、RET/JP D803でローダーへ戻る。
  serial_echoは17byteをエコーし有限待機で復帰する。ホストは同じリースセッションでデータを渡す。
- 復帰時にSP/UARTを復元し、復帰通知を送る。アプリがRAMを変更した可能性があるためverifiedを解除する。
  再実行には再VERIFYが必要。次のdeployのHELLOは転送状態を新規にする。

これはMMUや実行時サンドボックスではありません。ローダーは転送先を保護しますが、
実行したアプリ自身がローダー・ワーク・スタックを破壊したりHALTした場合の復帰は保証しません。
EI、ROM、BASICサービスを使うアプリには別途機種固有の契約が必要です。

English: profile v1 permits payload writes only to D000–D7FF. Stage 1, Stage 0,
buffers and a private stack occupy reserved RAM below E900. Both endpoints validate
range, length and entry, and the resident loader re-reads RAM for CRC verification.
Applications return via RET or JP D803, with interrupts disabled. This is a transfer
boundary, not hardware isolation from arbitrary running Z80 code.
