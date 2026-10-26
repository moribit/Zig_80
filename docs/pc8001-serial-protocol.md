# PC-8001 Serial Deploy protocol v1

100 Bの新Stage 0（E300–E363）、333 B中継、既存常駐ローダーの接続仕様・初回手順は [bootstrap補足](pc8001-bootstrap.md) を参照してください。

## 層とセッション

```
Zig deploy ─ USB CRCフレーム ─ Pico C bridge ─ 300bps inverted 8N1 ─ Z80 loader
```

USB層は既存の [プロトコル](../tools/serial-test/README.md) のままです。
PicoはStage 0/1の内容を解釈しません。PIO、固定バッファ、エラー通知、明示ARM、リース、DTRを担当します。
ホストはレジスタポーリングやRAM書き込みをUSBコマンドとしてPicoへ移していません。

`deploy` は `--enable-tx --voltage-confirmed` を必須とします。ファイル読み込み・範囲検査・
Stage 1のアセンブルはARM前に完了させます。接続時DISARM→RX停止→反転設定→RX開始→ARMの順で、
**200msアイドルLowを維持してから**READYまたはローダー応答を扱います。startup中の既存RXエラーを
退避し、その後を統計の基準にします。転送後に過去のエラーを0だったと表示しません。

待機、送信キュー待ち、受信、再送中も150ms間隔でKEEPALIVE。USB応答の待ち上限は500ms、
ブリッジの許可リースは従来どおり1秒です。USBパケットは128byteずつ、pendingが128byte以下になるまで待ちます。
終了時はPIO送信完了を確認し、100msアイドルを置いてDISARM・RX停止・DTR解除・termios復元を行います。
SIGINT時も終了処理を実行します。SIGKILL/USB切断時はDTRとリース、ファームウェアハング時はwatchdogが停止経路です。
スケジューラ停止・ケーブル断などでリースを更新できなければ、転送の継続より停止を優先します。
再接続で自動ARMや途中再開をしません。ホストが動いている正常なセッション内では、ブロックごとにHi-Zへ戻しません。

## Stage 0

ホストを先に開始し、TXアイドル確立の表示後に人がUSRを実行します。
UART初期化後、PCは `5A 30 01 00 05`（Z0、version1、長さ0500h）を送ります。
ホストはこれを完全に確認するまでUARTペイロードを送信しません。
Stage 0は有限の待機・READY再通知を32回まで行います。期限超過はBASICへ戻り、再度USRが必要です。

| ホストの選択byte | 続くデータ | 成功時 |
| --- | --- | --- |
| `47h` / G | Stage 1固定1,280byte＋CRC16 Low/High | `4Fh` / Oを送信、TxEMPTY確認後D800へジャンプ |
| `54h` / T | 00..FFの256byte＋CRC16 Low/High | CRC一致後256byteをそのまま返信、O送信、BASIC復帰。**ジャンプしない** |

CRCは受信イメージの全byteが対象です。タイムアウト、FE/PE/OE、CRC不一致、送信/TxEMPTY待ち失敗なら
Stage 1を実行しません。E806=1を残し、保存したUSRスタック・AF/BC/DE/HL・port30を復元してBASICへ戻ります。
標準入口は割り込み有効のN-BASIC USRです。復帰でEIします。モニタGによる直接起動やDI状態からの入口は契約外です。
成功するT試験ではE806=0。G成功後はStage 1が独立スタックを使います。

Stage 0の固定長転送は途中再送しません。失敗後はホストを止め、必要ならPCをBASICへ復帰させ、
CRCを確認してホスト先行→USRで最初からやり直します。部分受信の続きを推測して送りません。
ホストはG成功のOに加え、Stage 1 HELLOが返す常駐コードCRCをローカルの固定イメージCRCと照合します。

## Stage 1フレーム

全数値はLittle Endian、ペイロード0–64byte、最大フレーム72byte。

```
A5 5A | version u8=1 | type u8 | sequence u8 | length u8 | payload | CRC16 u16
```

MAGICはCRC範囲外。versionからpayload末尾までがCRC対象です。ペイロード中のMAGICはエスケープしません。
lengthとCRCで境界を判断し、異常時は次のMAGICを探索します。ブロックはACK後に次へ進めます。

| type | 要求payload | 動作 |
| --- | --- | --- |
| 01 HELLO | なし | version/領域/常駐CRCを返し、active/verifiedを解除、新規セッション |
| 02 BEGIN | load u16, size u16, entry u16, image_crc u16, existing u8 | 範囲検査。existing=0はDATA待ち、1はRAMのverify-only |
| 03 DATA | 1–64byte | load+受信済みoffsetへ書き、offsetを返す |
| 04 VERIFY | なし | 長さ一致後、実RAMのCRCを再計算し、期待CRC一致ならverified |
| 05 EXEC | なし | activeかつverifiedの場合だけACKを完送してentryへ移る |
| 06 ABORT | なし | active/verifiedを解除し常駐を維持 |
| 08 ECHO | 0–64byte | 内容をそのまま88h応答。RAMアプリ領域へ書かない |
| 09 INFO | なし | 現状・offset・UART統計。HELLOのような転送リセットはしない |

ACK=80h、NAK=81h。両者のpayloadは16byteです。

| offset | 内容 |
| --- | --- |
| 0 | status：0成功、1 CRC、2 version、3 length、4 address/entry、5 sequence、6 state/欠落、7未知type |
| 1 | Stage番号=1 |
| 2–3 | 許可開始D000 |
| 4–5 | 許可終端D800（含まない） |
| 6–7 | HELLOは常駐イメージCRC、DATA/INFOはoffset、VERIFYは実RAM CRC、EXECはentry |
| 8 | flags：bit0 active、bit1 verified |
| 9 | 最大DATA=64 |
| 10–11 | FE/PE/OEを観測した回数（合計、u16） |
| 12–13 | 受信中フレームのタイムアウト回数（u16） |
| 14 | 最後の8251ステータス |
| 15 | 予約=0 |

ECHO応答88hは要求と同じpayload（statusを挿入しない）。
アプリのRET/JP D803後は82h、EXECと同じsequenceの16byte復帰通知を送ります。
通知のvalueは復帰時のA（Low byte）であり、アプリの正しさをローダーが検証したという意味ではありません。
アプリが復帰することを証明するには `--wait-return` を使います。EXEC ACKだけでは完走を表示しません。
ホストは現在のセッションで送ったEXECに対応する通知だけを復帰の証拠として受け付けます。
HELLO/BEGIN中に届いた前回セッションの遅延通知を、後のEXEC成功へ使い回しません。

### CRCの固定仕様

CRC-16/CCITT-FALSE：poly=1021h、init=FFFFh、RefIn=false、RefOut=false、XorOut=0000h。
送信順はLow→High。`123456789` の値は29B1h、wire bytes=B1 29。
Stage 0のイメージ、Stage 1フレーム、アプリ全体CRC、Stage 0 DATA/POKE後の読み戻しに同じ規則を使います。
Zig、Cブリッジ（USB層）、Z80 CRCルーチンをテストで照合します。8bit加算チェックサムは標準経路に採用していません。
CRCは伝送誤り検出であり、暗号学的な認証や悪意ある送信者への防御ではありません。

### 順序・再送・失敗

HELLOは通常sequence0、その後は受理した要求ごとに+1（u8）。現在のアプリ上限ではラップ前に完了します。
最後に受理した要求のheader/payloadを保存し、**同じsequenceかつ全内容一致**の再送には前回応答を返します。
DATAは二重書き込みせず、EXECはACK消失後も二重実行しません。同sequenceの異なる内容、順序違反、欠落は拒否します。
NAKや復帰通知を作る際も成功応答キャッシュを保持します。

ホストは応答なし/応答CRC不正/NAK CRCに対して同じフレームを再送します（既定2回、最大10回）。
version/範囲/state/sequence不一致は成功扱いせず停止。USBコマンドSENDの自動再送とは分離しています。
USB ACK不明時にUARTデータを重複投入しないため、USB応答失敗はセッション中断です。
デバイス切断やリース失効から自動復旧しません。次回HELLOで新規にBEGINします。

Z80の各ポーリングは65,536回まで。これはCPU/メモリ待ちによって変わる有限回数で、厳密な秒タイムアウトではありません。
フレーム途中のタイムアウトやUARTエラーは現在フレームを破棄しverifiedを解除、エラーをリセットして待ち受けへ戻ります。
受信データが一切ない通常のアイドル待ちはタイムアウト件数に含めません。
ホスト `--timeout MS`（既定3000）には別途300bpsの要求/応答バイト時間の余裕を加えます。
USR待ちは `--ready-timeout MS`（既定60000）。Stage 1が既に実行中のアプリにUARTを渡している場合、
ローダー検出を保証しません。アプリの契約に従って復帰するか、PCをリセットして再導入します。

English: the Pico remains an opaque USB/UART bridge. A single explicitly armed
session renews its 1 s lease while waiting, transmitting and retrying. UART protocol
v1 uses 64-byte stop-and-wait frames, CCITT-FALSE CRC16, strict RAM/entry bounds,
RAM re-verification, separate EXEC and an exact last-request/reply cache. Duplicate
EXEC replays its ACK without re-running code. Stage 0 never sends an incomplete or
CRC-invalid image to the CPU. Neither USB success nor an EXEC ACK proves the app
finished; the optional return notification supplies that evidence.
