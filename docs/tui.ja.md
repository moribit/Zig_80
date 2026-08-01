# Zig_80 ターミナルUI

[English](tui.md)

Zig_80 TUIは、既存Core APIを利用する追加フロントエンドです。ヘッドレスCLIを置き換えず、CLIコマンドを子プロセスとして起動しません。両フロントエンドはアセンブラ、CPU、Machine、逆アセンブラ、デバッグ状態、Traceの各APIを直接利用します。

## 起動

```console
zig build run -- tui
zig build run -- tui examples/pixel.asm
```

現在はmacOSとLinux上の対話的なANSI/VT100互換端末を対象としています。80×24以上を推奨し、それより小さい場合は単一パネルへ切り替わります。極端に小さい端末ではサイズ警告を表示します。stdinまたはstdoutが非TTYの場合は、raw modeやalternate screenを有効にする前に拒否します。

Terminal Sessionは元の`termios`を保存し、canonical入力、echo、signal、CR変換を無効化してからalternate screenへ入り、カーソルを隠します。Ctrl+CはアプリケーションのQuitとして解釈します。正常終了とエラー終了のどちらでも、deferされた後処理が端末属性、カーソル、通常画面、canonical mode、echoを復旧します。

Windowsコンソールは拡張モジュールを分離していますが、現在は未実装です。

## 画面構成

通常サイズでは、コマンドヘッダー、ソースエディター、CPU状態、下部パネル、ステータス行を表示します。ソースには行番号、PC、ブレークポイントを表示します。CPU領域にはレジスタ、フラグ、HALT状態、総T-state、現在命令を表示します。下部はBus、Memory、Display、Help、Diagnosticsを切り替えます。

小さい端末では、`Alt+1`から`Alt+5`でEditor、Debug、Memory、Bus、Displayを全面表示します。

描画には再利用可能な前後2枚のFrame Bufferを使用します。WidgetはCellだけを書き、ANSIを生成しません。Rendererが差分を比較し、一つのバッファへANSI更新を構築して変更セルだけを出力します。`NO_COLOR`と`TERM=dumb`では色を無効化します。ASCII枠とASCII画面表示を使うため、色やUnicodeだけに意味を依存させません。

## 基本キー

| キー | 操作 | 代替キー |
|---|---|---|
| `Ctrl+S` | 保存 | — |
| `Ctrl+Q` | 終了 | `Ctrl+C` |
| `F2` | アセンブル | `Ctrl+A` |
| `F5` | リセットして実行 | `Ctrl+G` |
| `F6` | 1命令ステップ | `Ctrl+N` |
| `F7` | 継続 | `Ctrl+E` |
| `F8` | 一時停止 | `Ctrl+P` |
| `F9` | ソースブレークポイント切替 | `Ctrl+B` |
| `Ctrl+R` | リセット | — |
| `Alt+1..5` | Editor、Debug、Memory、Bus、Display | — |
| `?` / `F1` | Help | — |

矢印、Home、End、Delete、Backspace、Page Up、Page Downは編集中のViewを操作します。未保存状態での終了には2回目の`Ctrl+Q`が必要です。保存または別操作を行うと確認状態を解除します。

Memoryでは矢印で開始アドレスを移動し、16進4桁の入力でアドレスを直接指定できます。HomeでPC、EndでHL、Page UpでSP、Page DownでVRAM `0xC000`へ移動します。Busではイベント選択、スクロール、最新イベントへの追従復帰、Enterによる対応ソースPCへの移動ができます。

## アセンブルとデバッグ

Assembleはメモリ上の編集内容に対して動作します。成功時は生成バイト、シンボル、ソース行／アドレス対応を保存し、CLI Coreと同じMachineへロードします。失敗時もテキストを保持し、診断パネルを表示します。現在のCore診断はエラー分類とヒントを提供しますが、すべての解析エラーについて正確なソース列を提供する段階にはありません。

Runは1 UI tickあたり最大500命令の協調スライスで実行するため、Z80プログラムが無限ループでも端末入力を占有し続けません。Pause、Continue、Step、Reset、ソースブレークポイントは再利用可能なDebugSessionを共有します。PCが出力命令の先頭アドレスと厳密に一致する場合だけソース行を強調し、それ以外は逆アセンブル表示を使用します。

Displayは既存の128×64、1bpp VRAMを、Machineで定義済みの画素配置から読みます。CPUやMachineへ端末描画処理は追加していません。

## Bus Traceの精度

> 現在のBus Traceは、命令実行時に発生する論理的なバスアクセスを可視化したものです。実Z80の各T-stateおよび電気的タイミングを完全に再現するcycle-accurate波形ではありません。

Coreの任意`TraceSink`はopcode fetch、即値operand read、memory read、memory writeを記録します。I/O、refresh、interruptは将来用のイベント種別だけを用意しています。イベントは固定4,096件のリングバッファを使用し、アクセスごとの動的確保はありません。満杯時は古いイベントから破棄します。イベント時間が0であることは、cycle時間をモデル化していないことを明示します。

一覧には命令番号、命令開始時の総T-state、種別、アドレス、データ、PC、モデル上の信号を表示します。将来的には近似的なデジタル信号行やVCD出力を検討できますが、意味のあるT-state単位波形にはcycle-accurate CPUモデルが先に必要です。

## 現在の制限

- 構文強調、補完、Undo/Redo、検索、マウス、複数ファイルには未対応です。
- UTF-8を壊さず保持・編集しますが、全角文字や結合文字の端末表示幅はモデル化しません。
- 複数readへ分割されたescape sequenceは、一部端末で解釈できない可能性があります。
- Command Palette、watchpoint、step over/out、time travel、非同期実行、実機USBデバッグはありません。
- Memoryにアドレス直接入力Dialogはまだありません。
- Bus Eventは命令単位の論理モデルで、cycle-accurate波形ではありません。
- Resizeは`SIGWINCH`ではなく定期的な端末サイズ確認で検知します。
- Windowsには未対応です。
