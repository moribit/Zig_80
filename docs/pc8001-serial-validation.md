# PC-8001初代 × Pico 2：S10シリアル検証

本実装は、通信検証用のソフトウェアとUF2生成、ホスト上のモック検証まで完了した状態です。
**S10の電圧測定、Picoへの書き込み、実USB CDC接続、PC-8001との通信は未実施です。**
配線済みでも安全性確認済みではありません。現在のPC-8001との信号線を外し、Phase Aから開始してください。
各Phaseの成功を記録してから次へ進みます。送信許可フラグを自動化スクリプトへ常設しないでください。

English build/safety summary: [firmware README](../hardware/pico2-pc8001/README.md).
CLI and binary protocol: [serial-test](../tools/serial-test/README.md).

## 調査結果と実装境界

調査対象コミットは `3b13537c8f2f48bd2b3e4829f7f0e8f97d2dffd6`、既存テストは100件でした。
既存の2パスアセンブラ（include/incbin、Source Mapあり）、Z80 CPU、Port Device APIを再利用しました。
独立したリンカ、PC-8001全機種エミュレータ、PC-8001ターゲット、Intel HEX/CMT/WAV出力はありませんでした。
今回、専用サンプルのBIN/Intel HEX/N-BASIC DATA出力を追加しました。CMT/WAVエンコーダは追加していません。
ホストはZig 0.17.0の標準ライブラリのみ。Pico SDKは通常の `zig build` の依存にはしません。

構成は `zig80 serial` → CRC付きUSBフレーム → Cの固定容量ブリッジ → PIO UARTです。
PIOは通常/反転それぞれのRX/TXプログラムを持ち、一組だけをロードします。Z80プログラムは8251をポーリングします。
制御フレームとZ80のバイト列を分離し、将来のローダーがUSB制御コマンドを誤受信しない構成です。
USBプロトコルのCRCは、PC-8001までの転送内容を保証するものではありません。

Pico SDK 2.3.0（commit `98a542c1a62fb549ffb5d66a3e5892b06276b670`）と
TinyUSB `86ad6e56c1700e85f1c5678607a762cfe3aa2f47` を固定しました。
[MicroZigのRP2xxx実装・リリース](https://github.com/ZigEmbeddedGroup/microzig/releases)にもUSB/PIO対応はありますが、
コンパイラ版との結合やUSB関連の継続的な変更があります。今回は既存SDKのUSB/PIOとCMakeで検証可能な経路を採用しました。
直接Zigファームウェアの品質を比較測定したわけではありません。SDK/TinyUSBは各配布物のライセンスに従う開発依存で、ソースをこのリポジトリへコピーしていません。
Z80ルーチンは下記公開実装を調査して独自に記述しました。

## S10と電気的条件：接続前の確認

次表は [PC8001-TTL232Cの公開回路図](https://github.com/kuninet/PC8001-TTL232C) に基づく**候補**です。
NEC原本の回路図との照合、実機基板の向き・改造有無・番号の確認は未完了です。
コネクタを単純な一列の番号とみなさず、基板のPin 1表示と資料の視点を確認してください。
別機種（mkII/PC-8801等）の資料を代用しないでください。

| S10 pin | 公開回路図の信号 | 今回の候補接続 |
| --- | --- | --- |
| 1 | GND | Pico GND（物理Pin 3） |
| 2 | /TXD | Pico GP1（物理Pin 2）、PC→Pico |
| 3 | /RXD | Pico GP0（物理Pin 1）、Pico→PC、Phase Cまで外す |
| 4 | RTS | 未接続。ハンドシェイクは別途確認 |
| 5 | CTS | 同上 |
| 6 | DSR | 同上 |
| 7 | CD | 同上 |
| 8 | DTR | 同上 |
| 9, 10, 12, 14, 16 | GND | 番号を実機資料で確認 |
| **11** | **+5 V** | **GPIOへ接続禁止** |
| **13** | **+12 V** | **GPIOへ接続禁止** |
| **15** | **−12 V** | **GPIOへ接続禁止** |

S10は通常のRS-232電圧ではなく、TTLレベルの反転信号として公開回路で扱われています。
[作者の実機記事](https://kuninet.org/2021/04/27/pc-8001%E5%86%85%E8%94%B5%E3%82%B7%E3%83%AA%E3%82%A2%E3%83%AB%E3%81%A7%E3%83%91%E3%82%BD%E3%82%B3%E3%83%B3%E3%81%A8%E9%80%9A%E4%BF%A1/)
ではLS04による反転と300bpsが説明されています。実機のS10出力Highの最大値は未測定です。
反転8N1ではアイドルLow、スタートHighになります。PIO内で極性を処理し、外部の反転回路と二重反転しないようにします。

[RP2350データシートの5V耐性条件・E9](https://datasheets.raspberrypi.com/rp2350/rp2350-datasheet.pdf)を必ず参照してください。
GP0/GP1のFT入力は、**IOVDDが3.3 Vで給電されている条件**では5.5 Vまで扱えます。
IOVDDへ5 Vを与えてよいという意味ではありません。IOVDD未給電時は5 V入力を許容しません
（データシートの未給電時3.63 V条件と区別する）。PC-8001だけを先に動かしたままPicoを無給電にしないでください。
直列1 kΩはレベル変換や電源順序の保証にはなりません。TTL入力電流によるLow電圧上昇も測定対象です。

RP2350 A2のE9は入力中間電位での漏れ電流に関係します。内部プルダウンだけで対処済みとしません。
ファームウェアのHi-Z処理は、出力OE強制無効・プル無効・入力バッファ無効を行います。
RXを有効にすると入力バッファは必要になるため、実際の駆動インピーダンスと電圧を確認してください。
外付けプル抵抗の値を全機に一律適用しません。[A4の公式説明](https://www.raspberrypi.com/news/rp2350-a4-rp2354-and-a-new-hacking-challenge/)と合わせ、使用チップのステッピングを記録してください。

PC側の受信部品が実際にLS TTLである場合、[SN74LS04仕様](https://www.ti.com/lit/ds/symlink/sn74ls04.pdf)の
VIH最小2.0 V/VIL最大0.8 Vが判断材料になります。3.3 V出力がHighになるかは、実装部品、負荷、GND差、
抵抗を含めた実測で確定します。CMOSや改造された入力へ同じ判断を流用しません。
条件が確認できなければ、適切なレベル変換・反転・出力許可を持つ外部回路を先に用意してください。

公開アダプタはハンドシェイクも処理します。3本接続だけでPCから送れるとは断定できません。
8251のTxRDYステータスはCTSと独立でも、送信自体はCTSで阻止され得ます。
S10と8251の間の反転を確認せずにCTS/DSRをGNDや電源へ直結しないでください。
未確認なら既知のアダプタ回路とPC実機資料を照合し、Phase Bを保留します。

### 電源順序と測定表

1. 両機を停止し信号線を外す。S10の番号、GND、電源端子を確認する。
2. 非接続状態でPCのS10送信端子とPicoの電源を個別に測定する。短絡しないプローブを使用する。
3. 信号をつなぐ前に共通GNDとGND間電位差を確認し、Pico IOVDD=3.3 Vの給電状態を確保する。
4. 初回はPC→PicoのRX線だけ。PC向けTX線は物理的にも外す。
5. 終了時はPCからの駆動を停止して信号線を外し、それからPicoの給電を止める。
   電源順序を維持できない構成には外部の絶縁/バッファを使う。

| 項目 | 合格条件/確認内容 | 実測値・日時・機材 |
| --- | --- | --- |
| 実機型番/基板/Pin 1の向き | 初代PC-8001資料と一致 | 未確認 |
| RP2350ステッピング | A2/A3/A4等を特定 | 未確認 |
| Pico IOVDD | 通電中3.3 V、接続中に喪失しない | 未測定 |
| GND間電位差 | 安全に共通化可能 | 未測定 |
| S10 pin 2 idle/active High/Low | FT定格内、Low/High認識余裕あり | 未測定 |
| S10 pin 3入力回路と閾値 | 部品・負荷・反転を確認 | 未確認 |
| GP0の負荷接続時High/Low | PC入力閾値に余裕、抵抗でLowが上がり過ぎない | 未測定 |
| CTS/DSR等 | 送受信許可条件を実回路で確認 | 未確認 |
| TxC/RxC | x16で300bpsなら4800 Hz | 未測定 |
| ビット周期/極性/8N1 | 約3.333 ms/bit、反転idle Low | 未測定 |
| 給電/切断時の波形 | 逆給電・不要な送信なし | 未測定 |

テスターの平均値だけではビット幅や停止ビットを検証できません。波形確認は定格に適合する
オシロスコープ/ロジックアナライザを使用します。未測定欄を推測で埋めないでください。

## ビルドとソフトウェア検証

```sh
zig version                        # 0.17.0
zig build
zig build test --summary all
ZIG=/path/to/zig-0.17.0/zig sh hardware/pico2-pc8001/test.sh
zig build run -- serial build-examples
```

SDKの取得とUF2生成は[ビルド手順](../hardware/pico2-pc8001/README.md#build-never-flashes)を使用します。
ビルドスクリプトはフラッシュ、ポート探索、TX有効化をしません。
検証時はmacOS ARM64、Zig 0.17.0、xPack ARM GCC 15.2.1-1.1、SDK 2.3.0でした。
UF2は `zig-out/pc8001/pico2_pc8001.uf2`（52,224 bytes）、
SHA256 `2154e3e67c88de1dd8ad9df3baf3d41e4fd1772ab501a94d443acd70b684a5b3`。
`picotool info zig-out/pc8001/pico2_pc8001.uf2` でRP2350 ARM Secure、version 0.1.0を確認しました。
このコマンドはファイル検査です。

| 自動検証 | 結果・限界 |
| --- | --- |
| Zigテスト | 105件成功（従来100件を含む） |
| Cブリッジ | ASan/UBSan成功。CRC/不正長/全256値/バッファ境界/リース/切断再接続/溢れ/タイムアウト |
| PIOシミュレーション | 4件成功。実PIOソースの命令サブセットを実行、通常/反転の全256値、連続、偽スタート、不正ストップ、stuck line |
| CLI PTYモック | 6件成功。送信拒否、情報/RXのみ、全バイトRaw/ログ、比較、SIGINT復元、切断 |
| 既存CLI/TUI | サンプルsmoke/replay比較と、両Profileの端末復元テスト成功 |
| ビルド互換性 | 0.17.0 Debug/ReleaseSafe/ReleaseFast、0.16.0ビルド、aarch64-linux-muslクロスビルド成功 |
| ReleaseSafeテスト | 105件成功 |
| CI | 実装コミット `c8a934a` のLinux/macOS × Zig 0.16/0.17、全4ジョブ成功。[実行ログ](https://github.com/moribit/Zig_80/actions/runs/40186895044)。0.17では追加のモック検証も成功 |
| Z80機能モデル | 4サンプルの初期化、送受信、CTS待ち、最終TxEMPTY、タイムアウト、PE/OE/FE、比較、SP/保存レジスタ/境界を検証 |
| 物理USB/PIO/S10 | 未実施。モデルはUSB PHYや8251のビット精度を再現しない |

PIOは1bitあたり8クロック、150 MHzでは分周62500（Q8=16000000）で公称300bps、計算上の分周誤差0ppmです。
125 MHzの場合も量子化誤差は1ppm未満です。水晶・実機クロックの誤差は未測定です。
RXは停止ビットを検査し、50 ms以上の連続activeを回線タイムアウトとして記録します。
USB未接続時にもループは停止せず、TXは無効です。起動、DTR落下、切断/suspend、無効コマンド、
1秒リース失効、送信完了待ち250 ms超過でTXを無効化します。ハング時は250 ms watchdogで再起動します。
任意のCPU故障や電源喪失時の瞬時Hi-Zをソフトウェアだけで保証するものではありません。

## Phase A：Pico 2単体

PC-8001との**全信号線を外して**行います。

1. BOOTSELを押してPico 2をUSB接続し、RP2350のBOOTSELドライブへUF2を手動コピーする。
   実際のマウント名を確認する。書き込みスクリプトによる自動コピーはありません。
2. `zig-out/bin/zig80 serial list` で候補を確認。複数候補を勝手に選びません。
3. 明示ポートで `info`。下の出力と一致し、TXが無効なことを確認する。

```sh
zig-out/bin/zig80 serial info --port /dev/cu.usbmodemXXXX
# Linuxは例: --port /dev/ttyACM0
zig-out/bin/zig80 serial monitor --port /dev/cu.usbmodemXXXX --duration-ms 1000
```

期待する設定例（**実機取得ログではありません**）:

```text
firmware=pico2-pc8001/0.1.0 port=/dev/cu.usbmodemXXXX
UART=300 8N1 inverted=1 RX=GP1 TX=GP0 tx_enabled=0
clock_hz=150000000 divider_q8=16000000 (...)
```

4. Pico単体でGP0↔GP1をジャンパ接続し、両端3.3 V系であることを測定する。
   この段階の電圧確認として人が明示的に許可した場合のみ次を実行する。

```sh
zig-out/bin/zig80 serial test --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed
zig-out/bin/zig80 serial test --port /dev/cu.usbmodemXXXX --normal --enable-tx --voltage-confirmed
```

全256値・mismatches=0・エラーなしを確認。通常UARTはidle High、反転UARTはidle Lowです。
接続を外した状態、Ctrl-C、USB抜き差し、再接続時のTX無効も確認します。
Pico単体ループバック成功はPC-8001側の安全性や通信成功を意味しません。

## Phase B：PC-8001からの受信のみ

測定表とハンドシェイク条件を確認後、GNDとS10 pin 2→GP1だけ接続します。
GP0→S10 pin 3は外したままにします。モニタはTXをARMしません。

```sh
zig-out/bin/zig80 serial monitor --port /dev/cu.usbmodemXXXX --duration-ms 60000 --log phase-b.jsonl
```

PC側は公開実機記事の初期設定例 `TERM A,0,1,0`（8bit/パリティなし/x16）を使用し、
キーボードで `HELLO FROM PC-8001` を送ります。PCのROM版・TERM構文は所有機のマニュアルでも照合します。
初期外部クロック4800 Hzという前提が確認できるまでは300 8N1は候補設定です。
TERM画面のローカルエコーだけを往復成功と判定しません。
必要なら次節の `tx_test` でCR/LF付き送信を行います。

## Z80プログラムの初回導入

出力は `zig-out/pc8001/{tx_test,rx_test,echo_test,pattern_test}.{bin,hex,bas}`。
エントリD000h、コードD000h〜D3FFh、受信バッファD400h〜D4FFh、報告D500h〜D50Bhを予約します。
サンプルはAF/BC/DE/HLを保存し呼び出し元スタックへ復帰します。BASIC割り込み状態は変更しません。
他のUSART利用ソフトと同時実行せず、RETできるUSR呼び出しで起動してください。

### N-BASIC DATA/POKE

生成した `.bas` をN-BASICへ入力します。別経路の入力手段がない場合は手入力です。
内容は `CLEAR 300,&HCFFF` でBASICから領域を予約し、DATAをREADしてD000hへPOKEします。
`RUN` はロードと `DEFUSR0=&HD000` までで終了します。転記誤りをBINと照合し、
対象Phaseの準備完了後に**人が** `R=USR0(0)` を入力して実行します。
生成DATAの全バイトが読み込まれたことを確認し、停止/エラー後の不完全ロードを実行しません。

### CMT/WAV

本リポジトリはPC-8001カセットのエンコードを実装していません。
PC-8001対応の外部変換ツール（例：DumpListEditor）で、Intel HEXをD000h配置の
**機械語カセット形式**へ変換してCMTを作成し、その形式に対応するツールでWAVへ変換します。
使用ツール名/版、開始・終了アドレス、WAV設定を記録し、対象機で認識できることを先に確認します。
BINをCMTへリネームしたものやBASIC用CLOAD形式を代用しません。
先にBASICで `CLEAR 300,&HCFFF` により領域を予約し、所有機のマニュアルに従い
`MON` → モニタの `L` で機械語をロードします。
モニタからBASICへ戻る操作（ROMにより要確認）後、DEFUSR設定を行い、USRで呼び出します。
参考：[PC-8001_SD開発元](https://github.com/yanataka60/PC-8001_SD)、
[MAMEのPC-8001実装](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc8001.cpp)。
モニタの実行ジャンプだけではRET先が保証されないので、本サンプルを無条件にGコマンドで起動しません。

どちらも初回導入経路が別途必要です。今回のブリッジだけで未導入のPCへ自動転送・実行できるようにはなりません。

## Phase C：Picoからの送信

Phase B成功、測定表完了、PC入力のHigh/Low条件が成立してから、電源を落として配線を変更し、
所定の給電順序でGP0→S10 pin 3を接続します。PCで `rx_test` を準備します。
ホスト送信の前にPCがUSRでRX待ちに入っている必要があります。
別端末で5秒遅延してから送信し、その間にPCで `R=USR0(0)` を実行する例:

```sh
sleep 5
zig-out/bin/zig80 serial send 'HELLO FROM PICO 2' --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed
```

受信バッファと件数を確認します。文字列は17byte、CR/LFを付けません。
コマンド成功はPicoの送信完了であり、PC側の受信確認は報告領域で別途行います。

## Phase D / E：エコーと連続通信

Phase Dでは `echo_test` をロードし、Phase Cと同じ17byteを送ります。
PCは受信した17byteを返し、ホストの診断イベントとPC側報告で一致を確認します。
`send` は最後のTX完了を観測してから200 ms以上受信を継続しますが、それより遅れる応答を必ず捕捉する保証はありません。
厳密な全バイト往復判定はPhase Eの `test` を使います。
Phase Eは `pattern_test` をロードし、PCがUSRで待機してから次を実行します。

```sh
zig-out/bin/zig80 serial test --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed --log phase-e.jsonl
```

00..FFの256byteを送受信し、欠落・余分・不一致・framing/gapを失敗とします。
300bps 8N1の理論上限は片方向30byte/s、256byteで約8.53秒です。実測速度ではありません。
ホストの `payload_rx_bytes_per_second` はホスト経過時間からの値で、USBや初期化の遅延を含みます。
N-BASIC TERMではNUL等を扱いにくいため、この試験には専用機械語を使います。

### PC側の結果

`PRINT PEEK(&HD500)` : 0正常、1タイムアウト、2 USARTエラー、3不一致。
各u16は下位アドレスがLow、`PEEK(addr)+256*PEEK(addr+1)` で読みます。

| アドレス | 内容 |
| --- | --- |
| D501h | TXデータレジスタへ書いたbyte数（相手の受領数ではない） |
| D503h | RX byte数 |
| D505h | データ不一致数 |
| D507h | ポーリングタイムアウト数 |
| D509h | USARTエラーを観測した回数（PE/OE/FE合計） |
| D50Bh | 最後のステータス。bit3 PE / bit4 OE / bit5 FE |

初期化は20hデータ、21h制御/ステータス、`00 00 00 40 4E 37`。
EA66hのport30シャドウを読み、外部シリアル選択に `(old & CFh) | 20h` を出力し、終了時に元へ戻します。
USARTの旧設定の完全復元はしません。実行後にTERMを使うならTERMで再初期化します。
TX最終バイトのTxEMPTYを待ってから無効化します。ポーリングは有限回ですが壁時計による厳密な秒タイムアウトではありません。
根拠：[PC-8001-Serial-Drv](https://github.com/kuninet/PC-8001-Serial-Drv)、
[Intel Peripheral Design Handbook / 8251](https://bitsavers.trailing-edge.com/components/intel/_dataBooks/1979_Intel_Peripheral_Design_Handbook.pdf)。

## 結果の保存と切り分け

成功時の**モック例**は `transport=pico2-pc8001/mock ... mismatches=0`。
実機ログではファームウェアidentity、日時、測定表、Phase、サンプル名/バイナリhash、全統計とPC報告を保存します。
USB CRC成功・モック成功・TERMローカルエコーはS10双方向成功の証明にしません。
現時点の物理送受信byte数、不一致数、FE、タイムアウト、FIFO溢れ、実効速度はすべて**未測定**です。

| 症状 | 確認順序 |
| --- | --- |
| USBポートが出ない | データ対応USBケーブル、UF2対象RP2350、OS権限、他アプリの占有 |
| identity不一致/CRCエラー | 通常ターミナルではなく専用CLI、別デバイス誤選択、版の不一致 |
| TXが無効のまま | 2フラグ/測定確認、DTR、1秒リース、KEEPALIVE応答、再接続による解除 |
| PCから何も届かない | 配線方向・GND・電圧、CTS/DSR、TERM設定、port30、TxC/RxC |
| 値が反転/化ける/FE | 二重反転、idle、300/x16クロック、8N1、入力閾値、E9・波形 |
| NULや後半が消える | TERMを避け専用テスト、RX512イベント容量、USB切断/バックプレッシャー、PIO overrun |
| 最後のbyteがない | 8251 TxRDYとTxEMPTYの違い、相手の起動前送信、ホスト取得期間 |

PIO overrunはsticky flagの観測回数であり失われたbyteの正確な個数ではありません。
PC側エラーとPico側エラーを別々に記録します。USB切断でキューは破棄し件数を記録します。
速度変更時はホストのUSB115200だけを変えてもPIO300は変わりません。
PIO分周、8251 modeのx倍率、実機TxC/RxC、タイムアウトを揃え、波形を再測定してPhase Aからやり直します。
現在の版には任意baud変更コマンドはありません。

## 残作業と将来のローダー

Phase A〜Eの物理試験はユーザー環境で実施する必要があります。自動テストは出力許可を与えません。
現在のエミュレーションは「CLI↔Cブリッジ」と「既存CPU↔機能的8251モデル」を別々に検証しており、
全層をビット精度で直列接続したモデルではありません。Linuxの物理TTYとPico実USBも未確認です。

Serial LoaderはPC側の初回常駐ローダーを別途導入した後に、バージョン、配置/実行アドレス、長さ、
CRC、ACK/NAK、sequence、再送の重複排除、使用可能RAM境界を持つ小さなプロトコルとして追加します。
USBのARMとZ80側の実行許可は別に扱い、転送直後に無条件ジャンプしない設計を推奨します。
ESP32/HTTPS/チャット、実機リセット、外部デバッグ回路は今回の実装に含みません。
