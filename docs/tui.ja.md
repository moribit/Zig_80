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

通常サイズではSource Editorへ横幅の約70%を割り当て、コードを主役にします。右側にはグループ化したCPUカードとInstructionカードをコンパクトに配置し、下部はBus、Memory、Display、Help、Diagnosticsを切り替えます。2行Headerはアプリ名、ファイル、Modified状態だけに抑え、Pane固有HelpはStatus Barへ置きます。

小さい端末では、`Ctrl+1`から`Ctrl+5`でSource、CPU、Memory、Bus、Displayを全面表示します。修飾付き数字をCSI-uで通知する端末が必要です。

描画には再利用可能な前後2枚のFrame Bufferを使用します。WidgetはCellだけを書き、ANSIを生成しません。Rendererが差分を比較し、一つのバッファへANSI更新を構築して変更セルだけを出力します。`NO_COLOR`と`TERM=dumb`では色を無効化します。ASCII枠とASCII画面表示を使うため、色やUnicodeだけに意味を依存させません。

## 基本キー

| キー | 操作 | 代替キー |
|---|---|---|
| `Ctrl+S` | 保存 | — |
| `Ctrl+Q` | 終了 | `Ctrl+C` |
| `Ctrl+R` | アセンブル | Paletteの`assemble` |
| `Ctrl+E` | リセットして実行 | Paletteの`run` |
| `Ctrl+T` | 1命令ステップ | Paletteの`step` |
| `Ctrl+Space` | 継続 | Paletteの`continue` |
| `Esc` | 一時停止 | 入力モード中は先にキャンセル |
| `Ctrl+B` | ソースブレークポイント切替 | Source外の`b` |
| `Ctrl+P` | Command Palette | Source外の`:` |
| `Tab` / `Shift+Tab` | SourceでIndent／解除 | Source外では次／前のPane |
| `Ctrl+1..5` | Source、CPU、Memory、Bus、Display | — |
| `Ctrl+Z` / `Ctrl+Y` | Undo／Redo | — |
| `Ctrl+F` | 文字列のIncremental Search | — |
| `Ctrl+]` | Label定義へ移動 | Label参照上のEnter |
| `Alt+Left` / `Alt+Right` | Jump履歴を戻る／進む | — |
| `Shift+Arrow` | Source選択範囲を拡張 | — |
| `?` | Source外でHelp | Source内では`?`を入力 |

矢印、Home、End、Delete、Backspace、Page Up、Page Downは編集中のViewを操作します。未保存状態での終了には2回目の`Ctrl+Q`が必要です。保存または別操作を行うと確認状態を解除します。

Memoryでは矢印で開始アドレスを移動します。`g`で画面上に`Go to address: 0x____`を開き、16進4桁を入力してEnterで確定します。Backspaceで修正、Escapeでキャンセルし、それ以外の文字は無視します。HomeでPC、EndでHL、Page UpでSP、Page DownでVRAM `0xC000`へ移動します。

Busでは`[`と`]`でイベントを選択し、Endで最新イベントへの追従へ戻り、Enterで対応ソースPCへ移動します。通常幅ではEvent GroupとLogical Waveformを同時表示し、選択位置と最新追従状態を共有します。

## アセンブルとデバッグ

空でないソースは開いた直後に自動アセンブルするため、最初のFrameからPC 0000の生成命令を表示します。失敗時はEditorを維持してDiagnosticsを表示します。その後の編集では即時アセンブルせずDIRTYにし、Sourceタイトルでロード済みbuildが古いことを示します。Ctrl+Rは保存せずアセンブルし、Ctrl+Sは保存後にアセンブルします。

Source GutterはBreakpoint (●)、現在PC (▶)、Diagnostics (!)、前回命令 (▲)、編集Cursor (┃)の独立した固定列を持ちます。十分な幅では生成Addressと最大3 byteも表示し、狭いPaneでは省略します。

### Z80専用Source編集

Gutterは`BP`、`PC`、Diagnostic、Last Executed、編集Cursor、`LINE`、`ADDR`、`BYTES`を独立列に分離します。編集Cursor (`┃`)、現在PC (`▶`)、Breakpoint (`●`)、Diagnostic (`!`)、前回実行命令 (`▲`)は互いに上書きしません。現在PCのSourceだけを控えめに強調し、十分な横幅では生成Machine CodeもSource右側へ薄く表示します。

Marker、Line、Address、Bytesは固定幅と最低1文字の間隔を持ち、`│`で明確に区切ります。編集行はGutter先頭から右Marginまで、行末の空白Cellを含む一続きの低刺激なReverse帯で示します。現在PCは緑MarkerとSourceのBoldで表すため、同一行でも編集位置とは区別できます。Address、Bytes、Line Numberは共通の補助色、Labelは構造色とBoldへ統一しました。右端12〜18列はSourceをclipして余白とし、Execution／Diagnostic Overlayの安定した表示領域にします。

Assemblerと独立した軽量TokenizerはLabel、Mnemonic、Register、Number、Directive、Comment、String、Character Literalを分類します。128 slotの行CacheがSource行のhashとTokenを保持するため、変更のない表示行を毎Frame解析しません。`NO_COLOR`ではANSI色だけを除き、構造記号は保持します。

補完は編集時に更新され、候補ごとのheap確保を行いません。

- 命令位置ではMnemonicとDirectiveのprefixを提示します。
- Operand位置では`PUSH`／`POP`、分岐条件、Jump先Source Label、`LD (`後のAddress Registerなどを形式に応じて絞ります。
- `name:`と`name equ value`からSource全体のLabelを収集します。
- Up／Downで候補を選び、Spaceは確定して区切りを追加し、Enterは改行せず確定します。

Enterは前行のIndentを維持し、Label直後は4 spacesで命令本文を開始します。Tab／Shift+Tabは現在行または選択範囲をIndent／解除します。Shift+Arrowで選択し、Ctrl+Z／Ctrl+Yで上限64 snapshotのUndo／Redo履歴を移動します。

Ctrl+FはRegexを使わないIncremental Search barを開き、Enterで次候補、Escapeで終了します。既知Label参照上のEnterまたはCtrl+]で定義へ移動し、Alt+Left／Alt+Rightで履歴を戻る／進むことができます。Command Paletteには`Go Line`、`Go Label`、`Rename Label`、`Search`、`Breakpoint`、`Assemble`、`Run`を統合しました。Renameはidentifier境界上の定義と参照を一括変更し、Comment、String、Character Literalを除外します。

Assemblerの構造化Diagnosticは別Paneと共有したまま、Source上でも対象spanとmessageを表示します。編集CursorをMnemonicへ置くとPCを変更せずInstructionカードをその命令へ切り替えます。Step時は独立した編集Cursorを動かさず現在PCを自動Scrollし、実際に観測したRegister変更、Memory Write、`HALT`を実行行の右へ短時間表示します。`execution_overlay_enabled`で将来独立してON/OFFできる構造です。

Assembleはメモリ上の編集内容に対して動作します。成功時は生成バイト、シンボル、ソース行／アドレス対応を保存し、CLI Coreと同じMachineへロードします。失敗時もテキストを保持し、ファイル、行、列、ソース行、hintを持つ共通の構造化診断を表示します。診断上でEnterを押すと該当行へ移動します。診断文字列は編集Bufferと独立して所有し、現在は最初のエラーで停止するもののAppStateは診断配列を保持します。CLIも同じ位置情報を使用します。

Runは1 UI tickあたり最大500命令の協調スライスで実行するため、Z80プログラムが無限ループでも端末入力を占有し続けません。Pause、Continue、Step、Reset、ソースブレークポイントは再利用可能なDebugSessionを共有します。PCが出力命令の先頭アドレスと厳密に一致する場合だけソース行を強調し、それ以外は逆アセンブル表示を使用します。

複数の協調スライスを通じたRunとContinueの既定上限は、総命令数10,000,000およびCPU総T-state 100,000,000です。どちらかへ達すると`LIMIT REACHED`へ遷移し、両カウンターを表示します。Resetはカウンターを消去します。Stepは明示的な上書き操作として定義し、上限停止後も1命令を実行してpaused状態になります。上限値は`ExecutionLimits`へ集約しているため、将来CLI引数や設定画面から差し替えられます。

Displayは既存の128×64、1bpp VRAMを、Machineで定義済みの画素配置から読みます。CPUやMachineへ端末描画処理は追加していません。Command Paletteで1x／2x／4x（既定2x）を選び、2x以上では8 Pixel単位のGridを切り替えられます。大きな倍率はVRAM仕様を変えず、Cursor中心のViewportを使用します。

状態行には解像度、形式、倍率、単調増加するVRAM更新Frame、直近更新の変更Pixel数、Display更新FPSを表示します。FPSはVRAM更新頻度であり、CPU実行速度や端末refresh頻度ではありません。Display Focus中は矢印でPixelを選び、x/y、VRAM Address、Bit、現在値、最後に観測したWriter命令を検査できます。倍率後の全画面が収まる場合はゲーム領域を中央配置します。変更Pixel、Instruction Card、Source Execution Overlay、Register差分は約300msの共通強調を持ちます。`NO_COLOR`ではDirty Pixelを一時記号へ置換し、Displayタイトルにも短時間の更新Markerを付けます。

StepごとにTUI層で観測した命令結果を保存します。Source MarginはRegisterまたはMemoryの結果、CPUは現在値と前値、Busは最新Event、Displayは変更Pixelを示し、Coreへ端末固有動作を持ち込みません。上限付き命令Snapshot表により、選択Bus EventのPCとCPU前後状態を関連付け、VRAM Write選択時はDisplay inspectorもそのByteへ移動します。32行以上ではBus Focus中も通常DashboardにSource、CPU、Instructionを残し、短い端末では全Waveform行の可読性を優先してBusへ本文を一時的に割り当てます。

CPUカードはControl Register (`PC`、`SP`)とGeneral Register (`AF`、`BC`、`DE`、`HL`)を分け、Flagsを縦の状態列として配置します。変更Registerは旧値、下向き遷移、新値の順で一時強調します。隣接するInstructionカードはMnemonicを主見出しにし、Address、Opcode、Length、Timing、Description、FlagsのLabelを共通補助色、値を通常またはBoldへ統一します。

Focused Paneのタイトルは反転し、`SOURCE (Assembled)`、`CPU (Halted)`、`BUS (7 events)`、`INSTRUCTION (0006)`のように状態を含みます。HeaderからShortcut一覧を削除し、Pane固有HelpはStatus Bar右側へ移しました。Ctrl+PはSource移動／編集、実行、View切替、QuitをまとめたCommand Paletteを開きます。Sourceでは通常文字の`:・?・b・g`を入力できることを優先し、単一キーUI操作はSource外だけで有効です。PaletteはCtrl+P、BreakpointはCtrl+Bで常時操作できます。操作結果は約2秒のToastで通知します。Status Barは状態／Dirty Badgeと、名前付きのPC、Instr、T-State、Trace metricを視覚的に分離します。

## Bus Traceの精度

> Bus Waveformは、命令実行中に観測された論理的なバスアクセスを等幅イベントとして可視化したものです。実Z80の電気的タイミングや各T-stateの長さを再現するものではありません。

Coreの任意`TraceSink`はopcode fetch、即値operand read、memory read、memory writeを記録します。I/O、refresh、interruptは将来用のイベント種別だけを用意しています。イベントは固定4,096件のリングバッファを使用し、アクセスごとの動的確保はありません。満杯時は古いイベントから破棄します。イベント時間が0であることは、cycle時間をモデル化していないことを明示します。

一覧には命令番号、同一命令内の論理イベント番号、命令開始時の総T-state、種別、アドレス、データ、PC、モデル上の信号を表示します。`t_state_start`はアクセス時刻ではなく命令開始時のCPU総T-stateです。`t_state_count == 0`は未計測の論理アクセスを意味します。

通常幅のBusはInstruction CardとLogic Analyzerを横に配置します。CardはPC、decodeしたMnemonic、Opcode byte、総Event数、Memory Access数、I/O Access数を示した後、選択命令を構成するAccessを命令内index付きでまとめます。

Logic Analyzerは`Time →`を主軸にし、Slotを`Instruction #`見出しでGroup化します。Active Low制御線は`/MREQ`、`/IORQ`、`/RD`、`/WR`、`/RFSH`と表記し、assertされた論理AccessをLow Pulseとして描きます。`┐`／`└`と`┌`／`┘`の組で立下り・立上りを示し、低いPaneではCompact Traceへ切り替えます。AddressとDataは`[0000]`／`[00]`の箱型Bus表示です。選択Eventは見出し、信号、Busを貫く幅1 Cellの細い`│` Time Cursor（ASCIIでは`|`）を持ち、末尾へPC／Event種別／Data detailを表示します。`+`／`-`で1x、2x、4x、`f`でFit、Shift+Left／Rightまたは`<`／`>`でCursorと独立したPanを行います。Fitは必要に応じ、論理Sequence全体を端末列へsamplingします。Pulse幅は等幅の論理Slotであり、計測された電気的時間ではありません。

Eventが0件ならBus領域をGetting Startedの横へ縮小し、StepまたはRun後に自動で拡大します。UTF-8 localeでは線・block文字と自動生成したPane交点を使用し、それ以外はASCIIへフォールバックします。VCD出力は今後の検討対象です。Execution OverlayはCommand PaletteからON/OFFできます。

Command Paletteでは全Bus Event表示とMemory Writeのみの表示を選択できます。Filterは共有選択を維持したままGrouped List、Waveform Slot、矢印移動へ適用されます。Opcode Fetch、Operand Read、Memory Read、Memory Write、I/O Read、I/O Writeは、将来の設定UIに備えて独立したFilter fieldを持ちます。

入力層はヒープ確保を行わない永続的な256 byte stream decoderを持ちます。未完了のUTF-8とescape sequenceを次のreadまで保持し、短い端末層timeout後にEscape単体を確定し、分割されたAlt入力も処理します。不正UTF-8、未知の完了sequence、overflowは後続入力を止めないよう破棄または上限内へ復旧します。

## 現在の制限

- 補完は学習用に広いZ80語彙を提示しますが、現在のAssemblerが実装するのはドキュメント記載のsubsetです。`LDI`などを選択してもAssembler Diagnosticになる場合があります。
- Searchは大文字小文字を区別するliteral検索です。Undo/Redoは編集のcoalescingではなく、上限付きSource全体snapshotを使用します。
- Clipboard操作、マウス、複数ファイルには未対応です。
- UTF-8を壊さず保持・編集しますが、全角文字や結合文字の端末表示幅はモデル化しません。
- watchpoint、step over/out、time travel、非同期実行、実機USBデバッグはありません。
- 過去CPU状態の関連付けは直近4,096命令Snapshotまでです。Display同期は選択VRAM Byteを現在のMachine Memory上で示すもので、過去Frameを復元するTime Travelではありません。
- Bus Waveformのslotは論理アクセスであり、電気的・cycle-accurateな時間ではありません。I/O、refresh、interruptイベントはまだ生成しません。
- 診断は最初のアセンブルエラーで停止し、secondary noteやfix-it editはありません。
- Resizeは`SIGWINCH`ではなく定期的な端末サイズ確認で検知します。
- Windowsには未対応です。
