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
| `F8` | 一時停止 | — |
| `F9` | ソースブレークポイント切替 | `Ctrl+B` |
| `Ctrl+R` | リセット | — |
| `Ctrl+P` | Command Palette | — |
| `Alt+1..5` | Editor、Debug、Memory、Bus、Display | — |
| `?` / `F1` | Help | — |

矢印、Home、End、Delete、Backspace、Page Up、Page Downは編集中のViewを操作します。未保存状態での終了には2回目の`Ctrl+Q`が必要です。保存または別操作を行うと確認状態を解除します。

Memoryでは矢印で開始アドレスを移動します。`G`で画面上に`Go to address: 0x____`を開き、16進4桁を入力してEnterで確定します。Backspaceで修正、Escapeでキャンセルし、それ以外の文字は無視します。HomeでPC、EndでHL、Page UpでSP、Page DownでVRAM `0xC000`へ移動します。

Busではイベント選択、スクロール、最新イベントへの追従復帰、Enterによる対応ソースPCへの移動ができます。通常幅ではEvent GroupとLogical Waveformを同時表示し、Tabで両者のFocusを変えます。狭い端末ではTabで表示するBus subviewを切り替えます。すべての表示が選択位置と最新追従状態を共有します。

## アセンブルとデバッグ

空でないソースは開いた直後に自動アセンブルするため、最初のFrameからPC 0000の生成命令を表示します。失敗時はEditorを維持してDiagnosticsを表示します。その後の編集では即時アセンブルせずDIRTYにし、Sourceタイトルでロード済みbuildが古いことを示します。F2は保存せずアセンブルし、Ctrl+Sは保存後にアセンブルします。

Source GutterはBreakpoint (●)、現在PC (▶)、Diagnostics (!)、前回命令 (·)、編集Cursor (▏)の固定列を持ちます。十分な幅では生成Addressと最大3 byteも表示し、狭いPaneでは省略します。軽量ScannerがLabel、Directive、Mnemonic、Register、Number、Commentを色分けします。NO_COLORでも記号の意味は残ります。

Assembleはメモリ上の編集内容に対して動作します。成功時は生成バイト、シンボル、ソース行／アドレス対応を保存し、CLI Coreと同じMachineへロードします。失敗時もテキストを保持し、ファイル、行、列、ソース行、hintを持つ共通の構造化診断を表示します。診断上でEnterを押すと該当行へ移動します。診断文字列は編集Bufferと独立して所有し、現在は最初のエラーで停止するもののAppStateは診断配列を保持します。CLIも同じ位置情報を使用します。

Runは1 UI tickあたり最大500命令の協調スライスで実行するため、Z80プログラムが無限ループでも端末入力を占有し続けません。Pause、Continue、Step、Reset、ソースブレークポイントは再利用可能なDebugSessionを共有します。PCが出力命令の先頭アドレスと厳密に一致する場合だけソース行を強調し、それ以外は逆アセンブル表示を使用します。

複数の協調スライスを通じたRunとContinueの既定上限は、総命令数10,000,000およびCPU総T-state 100,000,000です。どちらかへ達すると`LIMIT REACHED`へ遷移し、両カウンターを表示します。Resetはカウンターを消去します。Stepは明示的な上書き操作として定義し、上限停止後も1命令を実行してpaused状態になります。上限値は`ExecutionLimits`へ集約しているため、将来CLI引数や設定画面から差し替えられます。

Displayは既存の128×64、1bpp VRAMを、Machineで定義済みの画素配置から読みます。CPUやMachineへ端末描画処理は追加していません。

CPU PaneはAF、BC、DE、HL、SP、PCを優先します。変更値には*と約1.2秒の一時強調を付けます。隣接するInstruction DetailはAddress、生成Bytes、Disassembly、byte長、Emulatorが使うTiming、教材向けの短いDescriptionを表示します。

Focused Paneのタイトルは反転し、Headerは共通一覧ではなくPane固有キーへ切り替わります。Ctrl+PはAssemble、Run、Reset、Go Address、Toggle Breakpointを持つ固定長Command Paletteを開きます。操作結果は約2秒のToastで通知します。Status BarはEDIT/ASSEMBLED/RUNNING/PAUSED/HALTED/BREAKPOINT/FAULT/LIMIT、PC、命令数、T-state、Trace使用量、Dirtyを常時表示します。

## Bus Traceの精度

> Bus Waveformは、命令実行中に観測された論理的なバスアクセスを等幅イベントとして可視化したものです。実Z80の電気的タイミングや各T-stateの長さを再現するものではありません。

Coreの任意`TraceSink`はopcode fetch、即値operand read、memory read、memory writeを記録します。I/O、refresh、interruptは将来用のイベント種別だけを用意しています。イベントは固定4,096件のリングバッファを使用し、アクセスごとの動的確保はありません。満杯時は古いイベントから破棄します。イベント時間が0であることは、cycle時間をモデル化していないことを明示します。

一覧には命令番号、同一命令内の論理イベント番号、命令開始時の総T-state、種別、アドレス、データ、PC、モデル上の信号を表示します。`t_state_start`はアクセス時刻ではなく命令開始時のCPU総T-stateです。`t_state_count == 0`は未計測の論理アクセスを意味します。

通常幅でBusへFocusすると本文全体を使用し、Event GroupとLogical Waveformを横に配置します。Event Groupは選択命令を構成するOpcode Fetch、Operand Read、Memory Writeなどを命令内index付きでまとめます。Tabは両者のFocusを変えますが、選択Eventは共有されます。

Logical WaveformはM1、MREQ、IORQ、RD、WR、RFSH、Address、Data、Typeを表示します。各イベントは等幅の`Event slot`であり、継続時間を推測しません。選択列は反転表示されるため色を無効にしても判別できます。端末幅から表示スロット数を決め、描画時にリングバッファを複製しません。Eventが0件ならBus領域をGetting Startedの横へ縮小し、StepまたはRun後に自動で拡大します。UTF-8 localeでは線・block文字と自動生成したPane交点を使用し、それ以外はASCIIへフォールバックします。VCD出力は今後の検討対象です。

入力層はヒープ確保を行わない永続的な256 byte stream decoderを持ちます。未完了のUTF-8とescape sequenceを次のreadまで保持し、短い端末層timeout後にEscape単体を確定し、分割されたAlt入力も処理します。不正UTF-8、未知の完了sequence、overflowは後続入力を止めないよう破棄または上限内へ復旧します。

## 現在の制限

- 補完、Undo/Redo、検索、マウス、複数ファイルには未対応です。
- UTF-8を壊さず保持・編集しますが、全角文字や結合文字の端末表示幅はモデル化しません。
- watchpoint、step over/out、time travel、非同期実行、実機USBデバッグはありません。
- Bus Waveformのslotは論理アクセスであり、電気的・cycle-accurateな時間ではありません。I/O、refresh、interruptイベントはまだ生成しません。
- 診断は最初のアセンブルエラーで停止し、secondary noteやfix-it editはありません。
- Resizeは`SIGWINCH`ではなく定期的な端末サイズ確認で検知します。
- Windowsには未対応です。
