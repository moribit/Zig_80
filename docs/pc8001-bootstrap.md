# PC-8001: small first bootstrap / 初回導入の小型化

音声入力ケーブルがない現在の推奨は、**100バイトのmini Stage 0をMONで入力**する方法です。
従来の333バイトDATA文を新たに入力する必要はありません。0.1.4でminiから常駐導入、hello転送・実行・画面表示・復帰まで実機確認済みです。

## 構成と互換性

| 役割 | ソース／生成名 | 実サイズ・配置 |
| --- | --- | --- |
| 新Stage 0 | mini_stage0.asm / mini-stage0.* | 100 B、E300–E363 |
| 中継Stage 1 | stage0.asm / relay-stage1.* | 333 B、E400–E54C |
| 常駐ローダー | stage1.asm / stage1.bin | 1,134 B、転送時1,280 B、D800–DCFF |

互換性のため旧ファイル名と `--loader stage0`（333 B）、`--loader stage1`（常駐）は維持します。
333 BのSHA-256は `914b95198822e10778dbc96a3af25ee9dd5f3c606140f58da79c7db071285258` のままです。
新経路は `--loader mini` を明示指定します。通常の再デプロイは従来どおり常駐ローダーを使用します。

miniは8251を初期化し、READY **37h**を送ります。ホストはこの受信前にデータを送りません。
続いて333 Bと1 Bの加算チェックサムを受信します。payloadと末尾の和がmod 256で0の場合のみE400へ移ります。
これはCRC16より弱く、相殺する複数バイト破損や順序交換を検出できません。
333 Bの中継コードが返す既存READY（5 B）を待ってから、従来のCRC16付き常駐ローダー転送に進みます。
常駐コードのHELLOとCRC照合、その後のアプリ転送・VERIFY・明示EXECの契約は変更しません。

各バイトは最大65,536回の有限ポーリング。PE/OE/FE、未完了、チェックサム不一致ではDI状態の停止ループとなり、
部分受信コードは実行しません。**mini失敗時はBASICへ戻りません。リセットして再導入してください。**
TERM初期化状態には依存しません。初期化省略版より再現性を優先しました。

## RAMとスタック

`CLEAR 300,&HCFFF` でBASIC使用範囲を制限します。miniはBASICのUSR呼出スタックを使い、追加最大12 Bを使用、
成功時にレジスタとSPを復元して中継コードへ移ります。E300のminiとE400の333 Bは重なりません。
既存のE600通信バッファ、E700–E7FF専用スタック、E800以降の状態領域も変更しません。
アプリ書込許可はD000–D7FFのみ。E900以降のシステムワーク／VRAMは引き続き保護します。
これは対象N-BASICの既存配置契約に従うもので、任意のROM版・拡張機器での利用可能性を保証しません。

## 生成と入力負担の実測

```sh
zig build
zig-out/bin/zig80 deploy bootstrap --target pc8001 --format files
```

出力は `zig-out/pc8001/loader/`。mini-stage0とrelay-stage1のそれぞれについて
`.bin`、`.hex`、`.bas`、`-monitor.txt`、`.cmt`、`.wav` を生成します。
従来のstage0.*とstage1.binも維持します。旧表示は `--bootstrap legacy` で選択できます。

| 方法 | 機械語 | DATA行数 | 総入力文字数 |
| --- | ---: | ---: | ---: |
| 新mini MON | 100 B | — | **319** |
| 新mini BASIC | 100 B | 7 | 757 |
| 従来333 B MON | 333 B | — | 883 |
| 従来333 B BASIC | 333 B | 21 | 1,406 |
| カセットMON L（ケーブルがある場合） | 100 / 333 B | — | 72 |

RETURN、CTRL+Bは各1文字。CLEAR/WIDTH、入力、Dによる全バイト確認、DEFUSR/USRまでを含みます。
画面の応答、修飾キー、ホスト操作は含みません。`input-counts.json` と独立テストで再計算します。
MONのコード入力だけならmini249文字、旧813文字です。BASICファイルそのものはCRLF込み757 / 1,420 Bです。
MONは少ない入力、BASICは入力後RAM CRC16の自動検査という利点があります。
MONでは必ず全バイトを照合してください。mini CRC16は7B73hです。

## 現在の実機での操作順

1. PCをBASICのOKにし、生成した `mini-stage0-monitor.txt` のCLEAR/WIDTH/MONとS入力を実施します。
   NECモニターのSは2桁ごとに次アドレスへ進みます。説明や `<RETURN>` は文字として入力しません。
2. 指示されたD範囲で100 Bすべてを照合し、CTRL+B、DEFUSR0まで実施します。**まだUSRを実行しません。**
   BASIC方式ならmini-stage0.basをNEW後に入力・RUNし、CRC OKを確認するところまでです。
3. まず非実行256 B試験を開始します。

```sh
zig-out/bin/zig80 deploy test --target pc8001 --loader mini \
  --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed --log mini-test.jsonl
```

4. ホストのTX idle／READY待ちを確認してからPCで `R=USR0(0)`。mini→333 B中継→256 B往復試験となり、BASICへ戻ります。
   全バイト一致とPicoエラーなしを確認し、PCの `PRINT HEX$(INP(&H21))` のPE/OE/FEも記録します。
5. 成功後、同じminiをもう一度USRから起動し、常駐ローダーを導入します。

```sh
zig-out/bin/zig80 deploy resident --target pc8001 --loader mini \
  --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed --log resident.jsonl
```

再びホスト待ち表示後にUSRを実行します。導入後はBASIC OKへ戻らず常駐待機になります。
以降のアプリ転送とRET復帰は [既存手順](pc8001-serial-loader.md#最初のアプリと再デプロイ) を使用します。
電源断・リセット後はminiを再導入します。ホストが準備できる前のUSR実行は避けてください。
USB接続、TX明示許可、リース更新、切断時Hi-Z、安全な解放は維持し、ファームウェア変更・再書込は不要です。
未解決のHi-Z時 `*` を直ったとは扱いません。

## カセット出力と調査

音声ケーブルが用意できれば、333 B中継を直接MONのLでロードする方法が最少入力です。
**現在ケーブルがないため、この経路は実機で実行しません。** CLOADはBASIC用であり、機械語MON Lと混同しません。
ロード後Dで全バイト確認、CTRL+B、DEFUSR0 E400、ホスト `--loader stage0` 待ち後USRという順序です。
生成メディアは自動実行しません。対応したカセット入力用ケーブルが必要で、S10やGPIOへ音声出力を接続しません。

CMTは3A＋開始アドレス上位/下位＋加算チェックサム、最大255 Bの長さ付きデータブロック、末尾3A0000です。
各ブロックの加算和は0。WAVは48 kHz / mono / signed 16-bit PCM、600 baud、1200/2400 Hz FSK、
start＋8 bit LSB first＋3 mark bits。S10の300 baudとは独立です。mini CMT110 B、WAV801,644 B（8.35秒）、
中継CMT346 B、WAV1,254,764 B（13.07秒）。再生音量や実機ロード成功は未測定です。

既存リポジトリには逆方向のCMT→WAV生成器がなかったため、標準ライブラリだけで追加しました。
仕様を [CHOS CMT実装](https://github.com/yamori813/CHOS/blob/c81166c5a9a6d9699f4502d760d46e67fc07d7a4/CMT.asm)、
[ihex2monl](https://github.com/yamori813/ihex2monl)、
[NECマニュアル](https://oldcrap.org/wp-content/uploads/2024/07/nec-pc8001b-users-manual.pdf) と照合しました。
外部ソースは同梱せず、実装コードもコピーしません。ihex2monlには明示ライセンスを確認できないため通常依存にしません。
任意の独立比較では、別途取得したクリーンなcommit `d14199c538c61bf09c366184c8af91a8aec9f39e` を使います。

```sh
python3 scripts/check_bootstrap_reference.py --source-dir /path/to/ihex2monl --zig zig
```

実施結果：mini・中継ともCMTが独立ツールと全バイト一致。WAVは独立DFT復調テストでCMTへの一致を確認しました。
外部ツールとのWAV PCM一致や物理テープロードは主張しません。

## 検証範囲 / English

今回のローカル結果：Zig 0.17 Debug/ReleaseSafeおよび0.16 Debugで117/117件成功。
Deploy PTY統合12件、既存Serial PTY6件、メディア3件、PIOモデル4件、C ASan/UBSan成功。
0.17 ReleaseFastビルド、aarch64 Linuxクロスビルド、CLI smoke成功。
書式は既存CIに合わせZig 0.16の `fmt --check .` で検証します（0.17 formatterには既存ファイルの差分があります）。

Zigテストはサイズ・非重複・元333 BのSHA・全受信・チェックサム・途中停止・USARTエラー・SP/レジスタ保存を検証します。
PTY統合は実CLI→実Cブリッジ→既存Z80→mini→中継→常駐→アプリ実行/復帰と非実行256 Bを検証します。
メディアの独立テストはCMTチェックサム、WAV復調、BASIC/MONのバイト一致と入力数を検証します。
**mini・333 B中継・256 B往復・常駐導入・helloの転送/表示/復帰は0.1.4で実機検証済みです。memory_test、serial_echo、カセットロードは未実施です。**

### 実機試行の記録（2026-10-26）

ユーザーがMON入力後の100 B一致、RESET後の保持を確認しました。
USR試行2回はREADY観測前にホスト→PicoのKEEPALIVE応答Timeoutで終了し、
中継コード受信・256 B往復の成功は確認できていません。
PCを停止させたままの追加試験でも、約20.6秒後（sequence 132）に同じUSB応答Timeoutを再現しました。
従ってUSR実行が原因とは断定できません。直後のTX無効診断ではUSB応答あり、累積エラー項目は0でした。
この0だけで、ファームウェア再起動やUSB障害を否定できません。
DeployのJSONLにはusb_request/usb_reply/usb_errorの時刻・sequence・部分受信数を追加しました。
安全条件、リース期限、UARTプロトコルは変更せず、切り分け完了前の再転送は行いません。

続くTX/RX両方無効の試験でも、USB STATS sequence 51への応答が500 ms以内に来ずTimeoutとなりました。
要求開始から約8秒で、試験前後のMac IOUSBHostDevice registry IDも変わっていました。
これはUSB再認識の観測であり、Picoのwatchdog再起動・電源・アダプター・OS等のどれが原因かは未確定です。
Macの接続ツリーに中間ハブは表示されず、ユーザーはUSB-C変換アダプターを使用しています。
新しい `serial probe` はTX/RXを停止してUSB状態取得を繰り返し、UARTペイロードを送らずJSONLへ記録します。

```sh
zig80 serial probe --port /dev/cu.usbmodemXXXX --duration-ms 30000 --timeout-ms 500 --log usb-probe.jsonl
```

この診断は送信許可を受け付けず、既存のリース期限を緩めません。PTYで無送信とtermios復元を検証しています。
次の実機切り分けはPC電源OFF後にS10信号線を切り離し、同じアダプターでPico単体のUSB probeを行う段階です。

ユーザーがPC電源OFF・GP0/GP1の信号線切り離しを実施した後も、Pico単体のUSB probeで再現しました。
0.1.0でSTATS sequence 155（試験開始から約25秒）の応答がTimeoutとなりました。
PCローダーやUART信号を必要としない再現条件が得られましたが、根本原因は未確定です。
診断版0.1.1はUSB HEALTH=11で uptime_us、loop_count、max_loop_us、watchdog_reboot、
watchdog_timeout_rebootを返します。各整数は64-bit little endian、最後の2フラグは各1 B、status込み27 Bです。
watchdogフラグは起動時にSDKのwatchdog_caused_reboot/watchdog_enable_caused_rebootから採取します。
`serial health` と0.1.1の `serial probe` で観測できます。旧0.1.0のprobeは引き続きSTATSだけを使用します。
安全制御やメインループ待機方式、watchdog/リース期限を変更していません。修正効果を主張する版ではありません。
UF2ビルドとC ASan/UBSan、Zig117件、Deploy12件、メディア3件、PIO4件の自動検証を通過しました。
診断版の書き込みとwatchdog実測は次の実機操作待ちです。

0.1.1をPicoへpicotoolで書き込み・フラッシュ照合しました（UF2 SHA-256
`9d01b1099aeecbd5472360b009041109d6e0e56129315a021021d42e09ac7759`）。
最初の30秒probeは179応答、最大応答1,611 us、正常終了しました。
続くHEALTHではuptimeが約70秒から約14秒へ減り、watchdog_reboot=1／watchdog_timeout_reboot=1を観測しました。
その後の2分probeも約52秒でTimeout（STATS sequence 368）となり、再度watchdog再起動を確認しました。
PC信号線なし・UART無効でも発生する、実測によるwatchdog期限超過です。停止する関数までは未確定です。

0.1.2は停止直前の処理区間をwatchdog scratch[0]に記録し、次回起動のHEALTHへboot_phaseを追加します。
SDKが利用するscratch[4..7]やタイムアウト値を変更しません。
HEALTHの既存26 Bの後にuint32 LEのphaseを追加し、status込み31 Bです（0.1.1の27 Bもホストは読めます）。
phase: 0不明/初期化、1USB task、2接続/安全/tick、3USBコマンド、4RX、5TX、6USB flush、7sleep。
0.1.2はUF2生成と自動検証まで。まだ実機へ書き込んでおらず、修正効果を主張する版ではありません。

続いて0.1.2を書き込み照合（UF2 SHA-256
`4a2d336d36fdac676d1e70764fc4b244c8c0a2e662169f9fa080cdcc5d0c5592`）し、同じ単体USB試験で再現しました。
再起動後はwatchdog_reboot=1、watchdog_timeout_reboot=1、**previous_watchdog_phase=7**でした。
phase 7はループ末尾のsleep_us(50)区間です。SDK内部のどの命令／割り込みが停止したかまでは特定していません。
0.1.3はこの短い待機だけをbusy_wait_us_32(50)へ置き換え、アラーム/WFE起床経路を避けます。
割り込みは無効にせず、watchdog 250 ms／TXリース1秒／Hi-Z／PIOの条件は維持します。
低消費電力スリープを使わなくなるため、この50 usの間はCPUがタイマーをポーリングします。
バージョン表示の食い違いも修正し、UF2のpicotoolメタデータをBRIDGE_VERSIONから生成します。
修正版UF2生成・自動テストと、修正版での実USB安定性試験は別に記録します。

0.1.3を実Pico 2へ書き込み、picotoolのフラッシュ照合と起動後のidentity/TX無効を確認しました。
UF2 SHA-256は `aa6c8900998f089efb5b4d1fbc50a701ff1be8dd2e272f7d7117a948db72bb30`。
同じUSB-C変換アダプター、PC電源OFF・信号線切り離し、UART TX/RX無効で120秒probeが正常終了しました。
STATS応答714回、最大応答866 us、elapsed 120,015,542 us、最大メインループ間隔223 us。
HEALTHのuptimeは単調増加し、watchdog_reboot/watchdog_timeout_rebootは全観測で0でした。
ログは `/tmp/zig80-usb-health-013-long.jsonl`。これはUSB単体での改善の実測であり、
256 BのPIO往復やPCローダー／デプロイの成功を意味しません。長時間での再発がないことまでは保証しません。
試験終了後もUSB要求を止めて待機し、次のHEALTHでuptime 219,337,577 us、watchdog両フラグ0を確認しました。
修正コミット48f99d0のLinux/macOS × Zig 0.16/0.17 CIも全4構成成功です：
https://github.com/moribit/Zig_80/actions/runs/40327658556

続いてユーザーがPico単体のGP0–GP1ジャンパ接続を実施し、0.1.3／反転300 bps 8N1で実PIOループバックを確認しました。
`serial test` は0x00–0xFFを送信し、256 B受信、256 B送信完了、mismatches=0、gaps=0で正常終了。
フレーミング、RX overflow、PIO overrun、TX timeout、protocol、USB drop、lease expiration、TX abort、RX timeoutは全て0。
経過9,023,635 us、ホスト基準28 B/s。JSONLを別途読み、256レコード・順序00..FF・余分/欠落なし・flags全0も照合しました。
ログは `/tmp/zig80-loopback-013-inverted.jsonl`。終了後のinfoでtx_enabled=0、
HEALTHでuptime 423,342,713 us、watchdog両フラグ0、max_loop_us=259を確認しました。
これはPico単体の物理PIO試験です。PC-8001での256 B往復やローダー実行は引き続き未確認です。

### PCへの再接続と連続フレーム試験

0.1.3でPCに再接続した最初の試行はREADY未受信でした。ユーザーがTX/RXの取り違えを報告・修正しました。
修正後、PCの100 B一致・DEFUSRを確認し、mini READY=37h、333 B＋SUM8転送、
中継READY=5A30010005の実受信まで確認できました（中継READYまで11,859,108 us）。
**miniから既存333 B中継コードへの導入・起動は実機で確認済み**です。
続くT非実行試験では返送00–B8の185 Bは完全一致、次の期待B9に対し6Eh／framing flag=1を観測し中断しました。
ログは `/tmp/zig80-mini-preflight-013-corrected.jsonl`。PCはBASICへ復帰し、ユーザー報告は
E806=0、E805=255、E804=85h。E806は正常終了、保存statusのPE/OE/FEは0です。
E805は受信失敗時だけ更新する領域なので、255を新しいエラーコードと解釈しません。
PCの全送信byteがMacへ正しく届いたとは言えず、256 B往復は失敗のままです。

実PIOソースを使うシミュレーションに、隙間なし1-stopフレーム、独立クロック±2%、
4種類の非同期位相、両極性で00–FFを流す回帰テストを追加しました。
変更前のRX 8-cycle方式では、相手のビット周期が1–2%短い16ケースが失敗しました。
Pico TXはフレーム間に追加idleがあるため、従来の単体ループバックだけではこの条件を覆えていませんでした。
0.1.4ではRXだけ16-cycle方式へ変更し、次フレーム開始待ちに余裕を設けます。
RXの半ビット検査・データ/stop中央サンプルは維持、TX 8-cycle・300 baud・8N1・極性・USB形式・安全期限は維持します。
40条件すべてで256 B一致、stop flag正常となり、元のPIOテストも通過しました。
これは境界条件のソフトウェア再現と修正です。実機のB9位置のエラーとの因果関係や修正効果はまだ未確認です。
CONFIGのdividerは互換性のためTX値のまま。150 MHz時はTX Q8=16,000,000、RX Q8=8,000,000です。

0.1.4のUF2（SHA-256 `522dd17b961b5736c40f8565fdbc26bd7469685bb18d01795648efe8b12af711`）を
書き込み・照合し、ユーザーがPC再接続・100 B一致・DEFUSRを確認後、同じmini経由の試験を実施しました。
**PC-8001実機の256 B往復が成功**：00–FF完全一致、missing=0、extra=0、mismatch=0、CRC16=OK、再送0。
mini READY＋中継READY＋256 B＋Oの263 UARTイベントはすべてflags=0、ホストも正常終了しTXを解放しました。
中継READYまで11,858,422 us、往復17,842,484 us、セッション38,266,301 us（ユーザー待ち込み）。
PCはBASICへ戻り、ユーザーがE806=0、保存status E804=85h、現在INP(21h)=85hを確認しました。
PCのPE/OE/FEもすべて0です。終了後PicoはTX無効、watchdog両フラグ0、max_loop_us=257でした。
記録：[実機256 B往復](pc8001-validation-records/2026-10-26-mini-preflight-014.json)。
ログは `/tmp/zig80-mini-preflight-014.jsonl`。これはT非実行試験であり、この時点では常駐ローダー・アプリを実行していません。
実装5990325の[Linux/macOS CI全4構成](https://github.com/moribit/Zig_80/actions/runs/40333571181)も成功しました。

### 常駐ローダー導入の実機成功

上記のPCステータス確認後、ユーザーの指示で `deploy resident --loader mini` を実行しました。
ホストREADY待ち後にUSRを起動し、mini→333 B中継→1,280 B常駐イメージ受信・CRC16検証・D800起動まで成功。
中継READYまで11,858,790 us、常駐イメージ転送44,940,866 us、セッション71,266,838 us（USR待ち込み）。
HELLO応答のフレームCRCも独立照合し、protocol=1、RAM D000–D7FF、resident_crc=6BF1を確認しました。
再送0、すべての受信UART flags=0、USBエラーなし、ホスト正常終了とTX無効を確認しました。
終了後Picoはuptime 624,486,077 us、watchdog両フラグ0、max_loop_us=257でした。
記録：[常駐導入](pc8001-validation-records/2026-10-26-resident-014.json)。ログは `/tmp/zig80-resident-014.jsonl`。
PCは常駐ローダー待ちのまま保持します。再度USRを呼ぶ必要はありません。電源断・RESETでは再導入が必要です。
この段階でアプリの転送やEXECは行っていません。

### helloの転送・表示・常駐への復帰

常駐導入後、手入力・RESET・ブートストラップの再導入なしでhelloを転送しました。
最初の29 B版はCRC6283一致、EXEC ACKと復帰通知まで成功したものの、ユーザーが表示の不一致を報告しました。
この版はWIDTH 80を仮定して連続VRAMセルに書いていました。40文字モードでは偶数セルだけが表示されるため、
既存CPUで40/80モードの表示セル・属性保持を検証する回帰テストを先に追加し、40モードの失敗を再現しました。
根拠：[MAME初代PC-8001表示処理とport30 bit0](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc8001.cpp)。

修正版helloはEA66のport30保存値bit0（ローダーのuart_initも使う値）を読み、
80文字なら1 B間隔、40文字なら2 B間隔でF300以降の文字セルだけに書きます。
属性・スキップセル・UART/表示の設定値を変更せず、ROMルーチンも呼びません。
戻り値Aは0=40文字、1=80文字。修正版は44 B、CRC ADC1です。
再転送でRAM CRC一致・EXEC ACK・ローダー復帰を確認し、A=00で40文字モードの使用を確認しました。
**ユーザーが画面左上のHELLO FROM ZIG_80完全一致を確認しました。**
再送0、経過約8.46秒、HELLO/BEGIN/DATA/VERIFY/EXEC/RETURNの6応答フレームCRCも独立照合済み。
全UART flags=0、終了時TX無効、watchdog両フラグ0でした。
記録：[hello実機結果](pc8001-validation-records/2026-10-26-hello-014.json)。
ログは `/tmp/zig80-hello-014-adaptive.jsonl`。最初の試行は `/tmp/zig80-hello-014.jsonl`。
これは常駐を保持してアプリを差し替え・実行・復帰できた実測です。任意アプリや未実施サンプルの動作保証とは区別します。
回帰テストを含むZig 118件成功、既存Deploy PTY 12件も通過しました。

続いて [ORBITAL RINGS](pc8001-demos.md) の582 Bを同じ常駐へ転送し、CRC A9DB一致、EXEC ACK、
A=52hでの復帰を確認しました。ユーザーがリングのアニメーションと終了表示も確認済みです。
Picoやブートストラップを書き換えず、画面デモを追加・実行できました。
この追加後はZig119件、Deploy PTY13件です。詳しい実測・メモリ使用はデモ文書を参照してください。

The new 100-byte Stage 0 receives the unchanged 333-byte relay using a bounded
receive loop and an additive checksum. It never jumps after incomplete or failed
reception; failure latches until reset. The existing CRC16 resident protocol and
Pico safety controls remain intact. Without an audio cable, use the generated
mini monitor transcript (319 total input characters). With a suitable cable,
the generated machine-code CMT/WAV can reduce typing further; physical loading
is unverified. Start the host before invoking USR. Subsequent deploys reuse the
resident loader and require no bootstrap typing while its RAM remains intact.
