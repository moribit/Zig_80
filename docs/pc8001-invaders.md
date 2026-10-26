# PC-8001 Mini Invaders / ミニインベーダー

`examples/pc8001/invaders.asm` は、常駐ローダーから起動する2列×5体の小型インベーダーゲームです。
現在の40/80文字・モノクロ/カラー設定を保持し、80×64のセミグラフィック領域へ描画します。
ゲーム開始・リトライ時にVRAM F300–FEB7の全25行を空白と標準テキスト属性で初期化するため、以前のデモの文字や属性を残しません。
画面上部に得点・残機、下部に操作と勝敗を表示します。

## 操作

| 操作 | キー |
| --- | --- |
| 右へ移動 | 右カーソル |
| 左へ移動 | 初代PC-8001ではShift＋右カーソル（同じキーの左矢印） |
| 予備の左右移動 | テンキー4 / 6 |
| 射撃 | スペース。押したままでも、自機弾が消えると次を発射 |
| 勝敗後の再挑戦 | スペースを一度離して押す |
| 終了・常駐へ戻る | ESCまたはSTOP |

左右入力と射撃は同時に扱います。左右の同時押しは停止、自機は画面端を越えません。
10体すべて撃破で勝利、残機0または敵の降下で敗北です。残機3、被弾後は短時間点滅して再被弾を防ぎます。
自機弾・敵弾は各1発、敵の動作は決定的です。音やROMサービス、割り込みには依存しません。
フレーム周期はCPU/DMA速度に依存します。

キーボードは初代の直接入力を読みます：port00 bit4/6がテンキー4/6、port08 bit2が右カーソル、bit6がShift、
port09 bit6がSPACE、bit7がESC、bit0がSTOP。押下はactive-lowです。
根拠：[MAME PC-8001キーマトリクス](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc88_kbd.cpp)、
[直接読み取りの反転](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc88_kbd.h)。
PC-8801用の独立した左カーソル行を初代へ流用しません。

## ビルド・転送

```sh
zig80 asm examples/pc8001/invaders.asm -o zig-out/pc8001/invaders.bin
zig80 deploy zig-out/pc8001/invaders.bin --target pc8001 \
  --port /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed --log invaders.jsonl
```

既存の常駐ローダーが動いている状態で使います。通常は`--wait-return`を指定せず、転送とEXEC ACKの後にUSB/TXを解放します。
`Completed`は起動要求の完了で、ゲーム終了の確認ではありません。ゲームはPCのキーボードで動作を続けます。
ESC/STOPで画面を標準テキスト属性へクリアし、`LOADER READY - INVADERS CLOSED`を表示してRETします（A=49h）。
終了後はRESETやUSRなしで次のdeployが可能です。ゲーム実行中には別のdeployを開始しないでください。
元の画面内容の保存は行わず、画面を新しく使う契約です。

コードと固定データはD000からD6FFまでに収め、状態はD700–D729とD7E0–D7E4です。
現在の生成物は1,361 B（D000–D550）、CRC16=382Fhです。
すべてアプリ許可範囲D000–D7FF内にあり、常駐コード・ローダースタック・BASICワークと重なりません。
Picoファームウェア、USART/CRTC設定、ローダープロトコルは変更しません。

## 検証

既存Z80で、4表示モードの全画面初期化、最初の描画フレーム、全画面終了処理、許可領域外のRAM保持を検証します。
直接キーマトリクスを与え、左右とShift、端の制限、同時押し、SPACE連射、命中/得点、勝利、
リトライのrelease条件、残機/点滅、敵降下、ESC/STOP復帰、SP/常駐保持も確認します。
実CLI→Cブリッジ→Z80のPTY試験で、対話ゲームの起動後のTX解放と、入力スクリプトのESCによる復帰・次のhello転送を検証します。
これらのモデル検証と、実機の表示・キー操作の確認は分けて記録します。
Zig 0.17 Debug/ReleaseSafeで123件、Deploy PTYで14件が成功しています。

English: ten invaders, cursor movement and simultaneous SPACE fire, score,
three lives, victory/defeat and restart. The original PC-8001 left cursor uses
Shift+Right; keypad 4/6 are alternatives. Startup and restart fully clear all
25 video rows and attributes. ESC/STOP clears back to text and returns to the
resident loader. Normal deployment releases TX after EXEC while the interactive
game continues; it does not claim the game has returned. No new firmware or ROM
entry point is required.
