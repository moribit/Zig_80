# PC-8001: small first bootstrap / 初回導入の小型化

音声入力ケーブルがない現在の推奨は、**100バイトのmini Stage 0をMONで入力**する方法です。
従来の333バイトDATA文を新たに入力する必要はありません。実機では未検証です。

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
**新mini、333 B中継、常駐導入、アプリ実行、カセットロードの実機検証は未実施です。**

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

The new 100-byte Stage 0 receives the unchanged 333-byte relay using a bounded
receive loop and an additive checksum. It never jumps after incomplete or failed
reception; failure latches until reset. The existing CRC16 resident protocol and
Pico safety controls remain intact. Without an audio cable, use the generated
mini monitor transcript (319 total input characters). With a suitable cable,
the generated machine-code CMT/WAV can reduce typing further; physical loading
is unverified. Start the host before invoking USR. Subsequent deploys reuse the
resident loader and require no bootstrap typing while its RAM remains intact.
