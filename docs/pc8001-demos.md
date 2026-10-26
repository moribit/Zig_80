# PC-8001 ORBITAL RINGS / グラフィックデモ

`examples/pc8001/orbital_rings.asm` は64×64のセミグラフィック領域に、位相を変えながら2本のリングを描く有限時間のデモです。
128フレーム（2周）で終了し、`COMPLETE - LOADER READY`を表示してRETで常駐ローダーへ戻ります。
終了時A=52h。実時間はCPU/DMAに依存し、フレーム同期やキーボード操作は使いません。

現在の40/80文字、モノクロ/カラー設定を保持し、ROMやCRTC/USARTの推測アドレスを呼びません。
VRAM F300からの120 B/行形式を使い、描画は2〜17行、タイトルは0行、終了案内は19行です。
描画行の40 B属性を各行保存し、グラフィック/テキスト区間を設定してから、終了時に640 Bすべてを復元します。
終了時には描画セルを空白にします。変更した文字セルの元の内容までは復元しません。
40文字モードでは偶数セルへ書き、属性・スキップセル以外の画面領域やUART選択を維持します。
セミグラフィックの2×4 bit構成・属性の根拠は
[MAME PC-8001表示処理](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc8001.cpp) と
[uPD3301属性展開](https://github.com/mamedev/mame/blob/master/src/devices/video/upd3301.cpp) です。
これらをビット精度の実機検証として代用しません。

コード/テーブルは582 B、D000–D245。状態はD4E0–D4E5、属性保存はD500–D77Fです。
いずれもアプリ許可範囲D000–D7FFに収まり、常駐コードD800以降・プライベートスタックとは重なりません。

```sh
zig80 asm examples/pc8001/orbital_rings.asm -o zig-out/pc8001/orbital_rings.bin
zig80 deploy zig-out/pc8001/orbital_rings.bin --target pc8001 \
  --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed \
  --wait-return --timeout 30000 --log orbital-rings.jsonl
```

常駐ローダーが既に動いている状態で実行します。USR、RESET、ブートストラップの再入力は不要です。
PCの画面を見ながら待ち、終了後も電源を維持すれば次のアプリを転送できます。
通常のアプリより復帰まで長いため、上記では30秒の復帰待ちを指定します。Picoの送信リースは短いまま定期更新します。

検証：既存Z80で4種類の文字/色モードを実行し、128フレームすべての進行、2時点の全512セルを
独立した三角関数の描画モデルと照合しています。全属性の復元、許可範囲外のRAM保持、SP、復帰通知も検証します。
実CLI→Cブリッジ→既存Z80のPTY試験では実行・復帰後にhelloを再デプロイして確認します。
Zig 0.17 Debug/ReleaseSafeの119件とDeploy PTY 13件が成功しました。

## 実機結果（2026-10-26）

Pico 0.1.4と既存のPC常駐ローダーを維持したまま、582 Bを転送・検証・実行しました。
CRC16 A9DB一致、再送0、15応答フレームのCRCを独立照合、全受信UART flags=0で正常終了。
復帰A=52h、TX無効、watchdog両フラグ0を確認しました。
**ユーザーが2本のリングの動きと、COMPLETE - LOADER READYの終了表示を確認しました。**
セッション全体51.406秒、EXEC ACK最終byteから復帰通知先頭byteまで14.277秒。
後者には復帰処理とUART通知時間も含み、純粋なアニメーションのCPU時間とは区別します。
ログは `/tmp/zig80-orbital-rings-014.jsonl`、永続記録は
[実機デモ結果](pc8001-validation-records/2026-10-26-orbital-rings-014.json) です。
属性の全byte復元と許可領域外メモリ保持はCPUモデルで検証し、実機では表示と復帰を確認しています。

English: a bounded 64×64 semigraphics animation renders two orbiting rings for
128 frames. It respects the current text width/color settings, restores all
changed row attributes, clears its canvas, and returns to the resident loader.
Only application-owned scratch RAM and documented video regions are written.
No additional firmware, ROM call, input operation or runtime dependency is used.
The operator confirmed both moving rings and the final completion text on the
physical PC-8001; upload CRC, execution ACK and return notification were verified.
