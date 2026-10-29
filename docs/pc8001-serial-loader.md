# Zig_80 → PC-8001 Serial Deploy

新しい初回導入は [100バイトStage 0手順](pc8001-bootstrap.md) を参照してください。
以下の333バイトStage 0という名称は旧CLIの互換名です。新構成では中継Stage 1として維持します。
以下の旧bootstrap表示コマンドでは `--bootstrap legacy` を追加してください。

## 現状と構成

既存のアセンブラ、Z80 CPU、Port Device、Pico SDK 2.3.0のPIO/USBブリッジを再利用します。
ホストはZig 0.17、ランタイム依存の追加なし。PicoのStage 0/1専用化、別アセンブラ、別CPUエミュレータはありません。
実装前コミットは `1e6d86806fbdc0669a6fd92f31348e5590086b6a`、既存105テストでした。
旧CLIは1回の最大256byte送信には使えましたが、長い転送中の応答待ち・再送・READY同期・RAM検証・実行ABIはありませんでした。

Stage 0は最初だけ手入力し、Stage 1を受信・検証して起動します。一度Stage 1が常駐すれば、
アプリのRET/JP D803を経由して次のアプリを再転送できます。電源断・リセット・ローダー破壊後はStage 0の再導入が必要です。

**0.1.4では両方向の文字列に加え、mini→333byte中継、256byte PC往復、常駐ローダー導入とCRC照合を実機確認済みです。
helloのRAMデプロイ・実行・画面表示と常駐への復帰も確認済みです。その他アプリは未確認です。** 最新の実測は [bootstrap記録](pc8001-bootstrap.md) を参照してください。
ソフトウェアテストの成功で自動的に実機へバイナリを流しません。
電気的な前提と未解決の `*` は [検証手順](pc8001-serial-validation.md) を参照してください。

## サイズと手入力

| 項目 | 生成結果 |
| --- | --- |
| Stage 0標準版 | **333byte**、E400–E54C |
| Stage 0モニタ入力 | 666桁の16進数、16byte×20行＋13byte×1行 |
| モニタの主要入力キー数 | **813**（S＋4桁アドレス＋RETURN、データ、行末RETURN。CLEAR/MON/照合/USRは別） |
| Stage 0 BASIC | **1,420byteのASCIIテキスト**（32行、CRLF含む）。RETURNを1キーとすると1,388キー＋RUN/RETURN |
| Stage 1 | **1,257byteのコード**、固定**1,280byte**へゼロ埋め |

30–120byteのStage 0目標には収まっていません。有限待機、8251の完全初期化、CRC16、READY、
TxEMPTY、BASICのレジスタ/スタック復元、同じ初回導入コードを使う256byte非実行試験を優先しました。
データは16byteごとのHEX文字列DATAにし、長い10進DATAの入力を減らしています。
CRC16はBASICのPOKE後にもRAMから再計算し、不一致ならUSRを定義せず停止します。
文字数は実生成ファイルから確認し、サイズ削減だけのために検証を省略しません。

初期化済みTERM状態を使う超小型版も検討しました。しかしCTRL+B後の状態、port30、RXエラー、
USRスタック、アイドル/READY同期への依存が増えます。初期化だけを除いても約30byteの削減に留まり、
標準の信頼性を維持したまま60byte級にはできないため、今回は別の実機経路として提供していません。
初期化省略・無検証ジャンプを通常のdeployへ混ぜていません。

## ビルド・生成

リポジトリルートで実行します。通常のdeploy（既存Stage 1へ）はASMソースのある作業ディレクトリを必要としませんが、
bootstrap生成と `--loader stage0` のStage 1生成は、この版ではリポジトリルートが必要です。

```sh
zig version # 0.17.0
zig build
zig build test --summary all
zig build loader-mock -Doptimize=ReleaseSafe
python3 scripts/test_deploy.py
zig80 deploy bootstrap --target pc8001 --format files
# 未インストールなら zig-out/bin/zig80 または zig build run -- を使う
zig80 deploy bootstrap --target pc8001 --format monitor
zig80 deploy bootstrap --target pc8001 --format basic
```

既定の `zig-out/pc8001/loader/` に次を作ります。`--out-dir DIR` で変更できます。

```
stage0.bin  stage0.hex  stage0.bas  stage0-monitor.txt  stage1.bin
```

bootstrapはポートを開かず、実機に送信も実行もしません。Stage 1はその場で同じソースから生成しCRCを算出します。
PicoファームウェアのUSBプロトコル・SDK・PIO・Hi-Z/E9対策は変更していません。今回のホストを使うための再フラッシュは不要です。

## 初回：Stage 0の入力

1. 既存のBASICを必要なら保存し、PCでCTRL+BによりTERMを終了する。`OK` を確認する。
2. `NEW` 後、stage0.basの全行を入力する。`RUN` はCLEAR、WIDTH、POKE、CRC確認とDEFUSRだけ。
   **このRUNでは機械語を実行しない。** `CRC ERROR` やBASICエラーなら先へ進まない。
   USRの数値戻り値を成功判定にせず、ホストの応答とE806の結果で判断する。
3. `CRC OK. HOST FIRST; THEN R=USR0(0)` を確認する。まだUSRは実行しない。

モニタ入力を使う場合は、先に `CLEAR 300,&HCFFF`、`WIDTH 80,25`、`MON`。
NECのモニタは `Sxxxx` がメモリ変更、`Dxxxx,yyyy` が表示です。Mコマンドではありません。
各グループはSアドレス＋RETURN、続く2桁ずつのHEX（自動で次アドレス）、最後にRETURN。
生成テキストの `<RETURN>`、説明、余分な空白をそのまま打たないでください。
全byteをDコマンドで照合し、CTRL+Bで戻ります。起動はDEFUSR0/USR0を使用し、Gへ直接ジャンプしません。
根拠：[NECのモニタ仕様](https://oldcrap.org/wp-content/uploads/2024/07/nec-pc8001b-users-manual.pdf)。
所有機ROMでのモニタ入力自体は、実際の入力結果で確認する必要があります。

## Stage 1前の256byte試験

Stage 0には、00..FFを受信→CRC確認→全byte返送してBASICへ戻るTモードがあります。
転送データを実行しないため、Stage 1を導入する前の確認に使えます。

```sh
zig80 deploy test --target pc8001 --loader stage0 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --log preflight.jsonl
```

ホストの `TX idle established. Waiting for Stage 0 READY` を見てからPCで `R=USR0(0)`。
これでホスト先行→PC初期化→READY→ホスト送信の順になります。
正常ならホストに `256/256 missing=0 extra=0 mismatch=0 CRC16=OK ... no jump`、PCはBASICへ戻ります。
Picoの新規FE/overflow/timeout/lease失効等があれば最終成功になりません。
PCの受信中PE/OE/FEや待機失敗は、Stage 0が成功Oを返さず停止するため成功判定を阻止します。
ただしStage 0は返送中の全ポーリングでRXエラーを検査する設計ではありません。
T試験終了後のBASICで `PRINT HEX$(INP(&H21))` を読み、`AND &H38` が0であることも確認して記録してください。
この最終PCステータス確認まで、ホスト表示だけで「PC側FE/PE/OEすべて0」と判定しません。
実機成功は実機の結果が得られた場合のみ記録します。C/CPUモックの同じ表示は実機証明ではありません。

従来の独立試験も `serial build-examples` の `binary_ready_test.bas` と
`deploy test --loader preflight` で使えます（BP準備通知とOK終了通知）。Stage 0のTモードなら追加手入力は不要です。

## Stage 1を導入する

```sh
zig80 deploy stage1 --target pc8001 --loader stage0 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --log stage1.jsonl
```

同じくホストのREADY待ち表示後にPCで `R=USR0(0)` を実行します。
Stage 0はGを受けて1,280byteとCRCを受信し、O完送後にだけD800へ移ります。
さらにホストはStage 1のHELLOと常駐CRCを照合します。Stage 0のOだけで導入完了にはしません。
PC側は機械語ローダーの待受け中になるため、BASICのOKには戻りません。

Stage 0はユーザー待ちを無限には行いません。先にUSRを起動して期限を切らした場合、
ホストを止め、E806/ステータスを確認し、ホスト先行でUSRをやり直してください。
急いで手入力する必要があるときは `--ready-timeout 300000` でホストの待ち時間を延ばせます。

Stage 1導入後の00..FF試験:

```sh
zig80 deploy test --target pc8001 --loader stage1 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --log resident-test.jsonl
```

これは64byte×4フレームのECHOです。全byte一致、余分/欠落なし、再送なし、Picoとターゲットの新規UARTエラーなしを要求します。

## 最初のアプリと再デプロイ

```sh
zig80 asm examples/pc8001/hello.asm -o zig-out/pc8001/hello.bin
zig80 deploy zig-out/pc8001/hello.bin --target pc8001 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --wait-return --log hello.jsonl

zig80 asm examples/pc8001/memory_test.asm -o zig-out/pc8001/memory_test.bin
zig80 deploy zig-out/pc8001/memory_test.bin --target pc8001 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --wait-return
```

helloは現在の40/80文字モードに合わせて画面左上へ `HELLO FROM ZIG_80` を書き、RETでローダーへ戻ります。
ROMやUART/表示設定を変更せず、復帰A=0は40文字、A=1は80文字です。
memory_testはD700–D70Fへ00..0Fを書いて照合し、D710へ0（成功）/1（失敗）を残して復帰します。
ホストが復帰Aを表示することとmemory_testのRAM結果は別です。RAM確認には既知の16byteファイルを
`--load-address 0xd700 --entry 0xd700 --verify-only` で比較できます。VERIFY-onlyは書き込み/EXECをしません。
`return_to_loader.asm` はJP D803のABI、`serial_echo.asm` はアプリによるUART所有権を示します。

```sh
zig80 asm examples/pc8001/serial_echo.asm -o zig-out/pc8001/serial_echo.bin
zig80 deploy zig-out/pc8001/serial_echo.bin --target pc8001 --port /dev/cu.usbmodemXXXX \
  --enable-tx --voltage-confirmed --app-echo
```

`--app-echo` は同一のARM/リース内で17byteを送受信比較し、ローダー復帰通知も待ちます。
任意アプリへ自動でこの文字列を送るわけではありません。UARTを使わないアプリには指定しません。
アプリがローダーを破壊しなければ、次回deploy時にStage 0の再入力もUSRも不要です。

### CLIオプション

グラフィックの有限時間デモは [ORBITAL RINGS](pc8001-demos.md) を参照してください。
現在の表示設定を保持し、終了時に属性を復元して常駐へ戻ります。
キーボード操作で遊べる [Mini Invaders](pc8001-invaders.md) は開始時に全画面をクリアし、ESC/STOPで常駐へ戻ります。
対話ゲームは通常 `--wait-return` なしで起動します。

`--target pc8001` と `--port PATH` は必須。候補が複数でも自動選択しません。
既定load/entryはD000（entryの省略時はload）。`--load-address`/`--entry`は0x形式または10進。
`--no-exec` は転送・検証まで、`--verify-only` は既存RAM比較のみ。
`--timeout MS`、`--ready-timeout MS`、`--retries N`、`--log FILE` は [プロトコル仕様](pc8001-serial-protocol.md) を参照。
`--loader` の既定はstage1。stage0はREADYを確認するまでイメージを送らず、stage1はHELLO応答を確認するまでBEGIN/DATAを送りません。
古い版/不明な領域/応答なしなら停止し、成功ログを捏造しません。

## 中断と復旧

- Ctrl-Cでホストを終了。DISARM/RX停止を短い上限で試し、DTRを落としてtermiosを復元する。
  macOSの切断時ENXIOはcleanupの想定内。残るUSB応答をcanonical入力として再解釈しないようTCSAFLUSHを使う。
- Stage 0途中失敗：BASICへ戻るまで待ち、`PRINT PEEK(&HE806)`（1失敗）、
  `PRINT PEEK(&HE805)`（1受信待ち期限/2USARTエラー）、`PRINT HEX$(PEEK(&HE804))` を記録。
  Stage 0のRAM CRCを確認して、ホスト先行でUSRを再実行する。途中から再開しない。
- Stage 1途中失敗：アプリは実行されない。次のdeployはHELLOで新規転送とする。
  明示中断は `zig80 deploy abort --target pc8001 --port PATH --enable-tx --voltage-confirmed`。
- USB抜き差しでARM/転送を自動復元しない。Pico給電を失う前にPCからの信号を停止・切り離す。
- アプリ暴走・スタック破壊・HALT：任意コードからの復帰を保証しない。PCをリセットしStage 0から再導入する。
- `*` の対処として無確認のプルダウンやGPIO常時駆動を追加しない。実回路の入力閾値/電流、アイドル/過渡波形を測定する。

## テストと転送時間

`zig build test` 113件。Stage 0のREADY/初期化/CRC/欠落/期限/非実行テスト、Stage 1の全コマンド、
欠落/順序/重複/範囲/entry/CRC/実RAM破損/ACK完送/RET/再デプロイを既存CPUで確認します。
`scripts/test_deploy.py` 11件は実CLI→PTY→実C bridge→機能的8251→既存CPU→ASMを接続します。
Stage 0からのStage 1導入、1KB転送、verify-only、複数アプリ、00..FF、アプリUART、CRC破損、
DATA/EXEC ACK消失、古い復帰通知と新しいHALTアプリ、バージョン違い、リース失効、再接続、切断、未起動、SIGINT、ログ/TTYを検証します。
通常ビルドにCやPico SDKは追加しません。Cを使うfixtureは `zig build loader-mock` の任意テスト専用です。
Pythonモックは加速実行であり、300bps波形や物理層の成功・速度を証明しません。

実装コミット `37e156f08aea40a0763ff89bd47b4784aeeafd09` の
[Linux/macOS × Zig 0.16/0.17 CI](https://github.com/moribit/Zig_80/actions/runs/40296312537) は全4ジョブ成功。
0.17ジョブで従来PTY 6件、Deploy統合11件、C ASan/UBSan、PIO 4件も実行しています。
Debug/ReleaseSafeの113テスト、ReleaseFastビルド、既存CLI/TUI検証を通過しました。
実機のStage 0 DATA/POKEとCRC表示、PC 256byte往復、Stage 1導入、アプリ実行はユーザー操作待ちです。
このCI結果を物理通信の成功として代用しません。

| 転送 | UART byte数の例 | 300bps 8N1の理論最短 |
| --- | --- | --- |
| Stage 0手入力 | シリアル転送なし | 未測定（人の入力時間） |
| Stage 1導入 | READY5＋G1＋1280＋CRC2＋O1=1289 | 約43.0秒（続くHELLOは別） |
| Stage 0 256byte往復 | READY5＋T1＋256＋CRC2＋256＋O1=521 | 約17.4秒 |
| 1KBアプリ、64byte DATA×16 | HELLO32＋BEGIN41＋DATA1536＋VERIFY32＋EXEC32=1673 | 約55.8秒 |
| 1KBアプリ＋復帰通知 | 上記＋24=1697 | 約56.6秒 |
| DATA 64byteの1再送 | 要求72＋応答24=96（期限待ち別） | 約3.2秒＋待ち時間 |

1KBの上記オーバーヘッドは649byte（アプリ比約63.4%、復帰通知別）。
実値はPIOのフレーム間隔、USB、CRC処理、再送待ちが加わります。実機Stage 0/Stage 1/1KB転送時間、
実効速度、再送コストは**未測定**です。CLI/JSONLのelapsed_usで実際の測定を保存してください。
従来のPico単体試験の28byte/sをPCデプロイ速度として転記しません。600/1200bps対応は含みません。
Stage 1転送の専用elapsedはREADY受信後からO受信まで、Completedのelapsedは
ARM後の処理全体（Stage 0の場合USR待ちも含む）です。人の待ち時間をペイロード速度へ混ぜないでください。

English: enter the CRC-checked Stage 0 once, start the host first, then invoke USR.
First run its non-executing binary preflight; then install Stage 1. Subsequent
deploys need no cassette or manual USR while the resident loader survives. Upload,
RAM CRC verification and explicit EXEC are separate. Applications can RET or use
D803 to re-enter the loader. All software tests are distinct from physical loader
validation, which requires the operator's confirmed bootstrap and actual results.

## Resident receive progress / 常駐ローダーの受信進捗（2026-10-29）

The resident now contains 1,257 code bytes, still padded to 1,280 bytes at
D800–DCFF. Its padded CRC16 is **6068**; the earlier **6BF1** records remain
historical validation of the 1,134-byte resident. Mini Stage 0 (100 bytes) and
the relay (333 bytes), their entry addresses and protocols are unchanged.
No new RAM state is allocated; 23 bytes remain as padding.

PC-8001の表示上の19行目（0始まり、20行画面の最下段）に次の形式で表示します。

```text
LOAD [########........]
```

16区画は `floor(OFFSET * 16 / IMAGE_SIZE)`。有効なBEGINで初期化し、CRCと範囲・
シーケンスを検証してRAMへ書き込んだDATAだけで更新します。同じブロックの再送、
不正CRC・順序違反は進捗を増やしません。verify-onlyでは既存RAMの範囲がロード済み
なので最初から満杯です。**満杯は全体CRC検証やEXEC成功を意味しません。**
VERIFY/EXECの条件は従来どおりで、ホスト側の成功表示を確認してください。

On each new, validated BEGIN, all 25 rows of character data are cleared,
including hidden character slots in 40-column mode. Attribute bytes are skipped.
This removes old BASIC/monitor text and function-key labels, without changing
video mode or writing display/UART registers. Duplicate BEGIN never clears again.
DATA updates only visible cells on row 19, using the existing 40/80 stride from
EA66h; other rows and hidden slots are preserved during these updates. Rendering
runs before ACK between frames, never for each incoming byte.
Applications may overwrite the row normally after EXEC. No automatic screen
restoration or new keyboard command is introduced.

導入には、現在のアプリを終了後、RESETでBASICへ戻り、E300–E363の100バイトを
照合してDEFUSR0を定義します。ホストで `deploy resident --loader mini` を先に
起動し、受信待ち表示の後でUSRを実行します。常駐導入そのものはmini/中継側が
担当するため、この新バーはまだ表示しません。導入後のhelloやchatの転送で確認します。
更新版を導入するまで、既にRAM上で動作している旧ローダーの表示は変わりません。

Automated checks cover all width/color combinations, short and maximum 2KB
images, partial blocks, retransmission/rejection, existing-RAM verification,
VRAM attributes/skipped cells, resident-code integrity and EXEC/RET. The initial 1,234-byte progress revision (CRC 4D58) installed and executed hello
successfully on the physical PC. The operator reported that its retained BASIC
text and function-key labels overlapped the output. This 1,257-byte revision
adds a once-per-BEGIN clear; physical validation of the correction is pending.
See the [initial progress record](pc8001-validation-records/2026-10-29-resident-progress-014.json).
