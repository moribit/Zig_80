# Zig_80 TUI開発環境 初期実装依頼

リポジトリ `appleuser634/Zig_80` の既存実装を確認し、現在のヘッドレスCLI機能を維持したまま、Z80アセンブリの編集・アセンブル・実行・デバッグを行えるTUIフロントエンドを追加してください。

今回の目的は、Zig_80を単なるCLIツールから、以下を一つのターミナル画面で扱える学習・開発環境へ発展させることです。

- Z80アセンブリソースの編集
- 任意のタイミングでのアセンブル
- エミュレーターの実行・停止・ステップ実行
- レジスタ、フラグ、PC、SPの表示
- 現在の命令とソース行の対応表示
- メモリアクセスとZ80バスイベントの観察
- 将来的なロジックアナライザー風波形表示
- 将来的な実Z80ハードウェアとの接続

今回は、既存CLIを置き換えず、同じ内部APIを利用する新しいTUIフロントエンドを追加してください。

---

# 1. 最初に既存実装を調査する

変更前に、リポジトリ全体を確認してください。

最低限、以下を確認してください。

- `README.md`
- `build.zig`
- `build.zig.zon`
- `src/main.zig`
- CPU実装
- Bus実装
- Machine実装
- アセンブラ
- 逆アセンブラ
- REPLデバッガー
- 画面レンダラー
- テスト
- examples
- docs

以下を把握してから実装へ入ってください。

1. CLIサブコマンドの現在の構造
2. CPUの`step` API
3. `StepResult`の内容
4. Machineのライフサイクル
5. アセンブラの戻り値
6. ソース行とアドレスの対応情報
7. 逆アセンブラのAPI
8. デバッガーのブレークポイント管理
9. VRAMと仮想画面の仕様
10. 現在のZigバージョン

既存コードに利用可能な仕組みがある場合は再利用し、同じ処理をTUI内へ複製しないでください。

---

# 2. 最重要方針

## 2.1 CLIを維持する

現在の以下のコマンドは、変更後も引き続き利用可能にしてください。

```console
zig80 asm
zig80 run
zig80 disasm
zig80 debug
zig80 test
zig80 explain
```

TUI追加後も、既存CLIの出力や自動テスト用途を壊さないでください。

新しいTUIは、以下のようなサブコマンドで起動できるようにしてください。

```console
zig80 tui
zig80 tui examples/pixel.asm
```

可能であれば、次の形式にも対応してください。

```console
zig80
```

ただし、引数なし実行時にTUIを起動する変更が既存CLIの互換性を損なう場合は、今回は`zig80 tui`だけで構いません。

## 2.2 CoreとFrontendを分離する

次の依存方向を維持してください。

```text
Assembler ─┐
Emulator ──┤
Debugger ──┼── Core API
Machine ───┤
Trace ─────┘
     ▲
     │
 ┌───┴──────────────┐
 │                  │
CLI Frontend    TUI Frontend
```

禁止事項：

- TUIからCLIサブコマンドを子プロセスとして起動する
- TUI内に別のアセンブラ処理を書く
- TUI内に別のCPU実行処理を書く
- CPUコアからターミナル描画を行う
- MachineからANSIエスケープシーケンスを出力する
- CLI専用型へTUIを強く依存させる

CLIとTUIは同じCore APIを直接利用してください。

---

# 3. 今回の実装範囲

今回の必須範囲は、実際に利用可能なTUI MVPです。

## 必須機能

- TUIの起動・終了
- アセンブリソースの読み込み
- 簡単なソース編集
- ファイル保存
- アセンブル
- 診断表示
- 実行
- 一時停止
- 1命令ステップ実行
- リセット
- レジスタ表示
- フラグ表示
- 現在のPC表示
- 現在の命令の逆アセンブル表示
- ブレークポイント
- 基本的なメモリ表示
- Bus Traceイベントの記録
- Bus Traceイベント一覧の表示
- 仮想画面の表示
- 既存CLIの回帰テスト

## 今回は完全実装を求めない機能

以下は設計上の拡張ポイントを用意してください。ただし、今回無理に完成させないでください。

- 完全なロジックアナライザー波形
- T-state単位のcycle-accurate波形
- Undo/Redo
- 構文ハイライト
- 補完
- マウス操作
- タイムトラベルデバッガー
- ウォッチポイント
- Step over
- Step out
- 実機USBデバッグ
- VCD出力
- 非同期バックグラウンド実行
- 複数ファイル編集
- プロジェクト管理
- LSP
- GDB Remote Serial Protocol

---

# 4. TUIライブラリの実装
# 依存方針の変更

本実装は、**Zig本体とZig標準ライブラリのみを使用し、外部依存を一切追加しない構成**としてください。

以下は禁止です。

- 外部TUIライブラリ
- 外部ターミナル制御ライブラリ
- ncurses
- termbox
- vaxis
- libuv
- SDL
- Cライブラリへのリンク
- Git submodule
- package manager経由の依存追加
- build.zig.zonへの外部パッケージ追加

`build.zig.zon`には、Zig_80自身のパッケージ情報以外の依存を追加しないでください。

---

# TUI実装方針
TUIは、Zig標準ライブラリとOSの標準的な端末機能だけを利用して独自実装してください。

端末制御は、以下を直接扱う小さな抽象化層として実装してください。

- ANSI / VT100互換エスケープシーケンス
- alternate screen
- cursor visibility
- cursor position
- clear screen
- text attributes
- foreground/background color
- terminal size
- raw mode
- non-blocking input
- key sequence decoding
- terminal resize
- terminal state restoration

端末固有処理をTUIアプリ本体へ直接散らさず、専用モジュールへ分離してください。

推奨構成：

```text
src/tui/
├── terminal/
│   ├── terminal.zig
│   ├── session.zig
│   ├── ansi.zig
│   ├── input.zig
│   ├── key.zig
│   ├── size.zig
│   ├── unix.zig
│   └── windows.zig
├── render/
│   ├── frame.zig
│   ├── cell.zig
│   ├── style.zig
│   └── diff.zig
├── app.zig
├── state.zig
├── command.zig
├── event.zig
├── event_loop.zig
├── layout.zig
├── editor/
├── screens/
└── widgets/
```

現在の対象はmacOSとLinuxを優先してください。

Windows対応を今回実装しない場合も、OS依存箇所を分離し、将来的に追加できる構造にしてください。

---

# POSIX端末制御

macOSとLinuxでは、Zig標準ライブラリから利用可能なPOSIX APIを使用してください。

必要に応じて以下を扱ってください。

- `termios`
- `tcgetattr`
- `tcsetattr`
- `poll`
- `read`
- `write`
- `ioctl`
- `SIGWINCH`
- stdin/stdoutのTTY判定

ただし、Zigの現在のバージョンにおける正しい標準ライブラリAPIを確認して使用してください。

古いZigバージョンのAPIを推測で使用しないでください。

Cヘッダーを直接インポートする必要がない場合は、`@cImport`を使用せず、Zig標準ライブラリのPOSIXラッパーを優先してください。

---

# TerminalSession

端末状態の開始と復旧を、安全なライフサイクル型として実装してください。

概念例：

```zig
pub const TerminalSession = struct {
    original_termios: Termios,
    active: bool,

    pub fn begin() !TerminalSession;
    pub fn deinit(self: *TerminalSession) void;
};
```

`begin`では以下を行ってください。

- stdin/stdoutがTTYか確認
- 現在のtermios保存
- raw mode設定
- alternate screenへ移行
- cursor非表示
- 必要な入力モードを有効化

`deinit`では必ず以下を行ってください。

- cursor表示
- alternate screen終了
- text attributesリセット
- 元のtermios復旧
- 出力flush

`defer session.deinit()`で安全に復旧できる設計にしてください。

---

# Raw mode

raw modeでは、少なくとも以下を考慮してください。

- canonical input無効化
- echo無効化
- signal characterの扱い
- CR/LF変換
- blocking/non-blocking read
- `VMIN`
- `VTIME`

Ctrl+Cをアプリ側で処理するか、OSシグナルとして扱うかは明確に設計してください。

どちらを選んでも、端末状態が復旧されることを優先してください。

---

# ANSI描画

ANSI出力は各ウィジェットから直接生成させず、共通レンダラーに集約してください。

画面全体を毎フレーム無条件に消去・再描画するのではなく、内部Frame Bufferを比較して、変更セルだけを出力する差分描画を実装してください。

概念例：

```zig
pub const Cell = struct {
    codepoint: u21 = ' ',
    style: Style = .{},
};

pub const Frame = struct {
    width: usize,
    height: usize,
    cells: []Cell,
};
```

レンダリング手順：

```text
AppState
   ↓
Widgets render to next Frame
   ↓
Compare previous Frame and next Frame
   ↓
Emit only changed terminal cells
   ↓
Swap frames
```

初期実装で差分描画が複雑な場合は、まず行単位の差分更新でも構いません。

ただし、各ウィジェットが直接stdoutへ書く構成は避けてください。

---

# 出力バッファ

描画時は、小さな`write`を大量に呼び出さないでください。

1フレーム分のANSI出力をバッファへ構築し、可能な限り少ない回数でstdoutへ書き込んでください。

例：

```zig
var output = std.ArrayList(u8).empty;
defer output.deinit(allocator);

try renderer.renderDiff(
    allocator,
    &output,
    previous_frame,
    next_frame,
);

try stdout.writeAll(output.items);
```

通常描画ループ内で毎回不要なヒープ確保を行わないよう、バッファを再利用してください。

---

# 入力デコーダー

ターミナル入力は、バイト列を直接Appへ渡さず、意味のあるKeyEventへ変換してください。

概念例：

```zig
pub const KeyCode = union(enum) {
    character: u21,
    enter,
    escape,
    backspace,
    delete,
    tab,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    function: u8,
};

pub const KeyEvent = struct {
    code: KeyCode,
    ctrl: bool = false,
    alt: bool = false,
    shift: bool = false,
};
```

以下のような入力を扱ってください。

- ASCII
- UTF-8文字
- 矢印キー
- Home/End
- Delete
- Page Up/Page Down
- Function keys
- Ctrlキー
- Altキー
- Escape単体
- 複数バイトのANSI escape sequence

Escape単体とescape sequenceを区別するための短い入力待ち時間が必要な場合は、その設計を端末入力層へ閉じ込めてください。

---

# イベントループ

外部イベントループライブラリは使用せず、Zig標準ライブラリとPOSIXの`poll`相当機能で実装してください。

イベントループは、少なくとも以下を統合してください。

- stdin入力
- emulator execution slice
- terminal resize
- redraw request
- periodic refresh
- quit request

概念：

```text
poll input with timeout
        ↓
decode key events
        ↓
update AppState
        ↓
run limited emulator instructions
        ↓
render if dirty or timer elapsed
```

実行中も入力を受け付けられるよう、1回のループで実行する命令数を制限してください。

マルチスレッドは初期版では不要です。

---

# リサイズ処理

端末サイズは、標準的なTTY APIを通じて取得してください。

`SIGWINCH`または定期確認によりサイズ変更を検知し、Frame Bufferを再確保して再描画してください。

シグナルハンドラー内で複雑な処理やヒープ確保を行わないでください。

シグナルハンドラーを使う場合は、フラグ設定のみとし、実際の処理はイベントループ側で行ってください。

---

# 色と互換性

色はANSI 16色または256色を基本とし、True Colorを前提にしないでください。

以下を考慮してください。

- `NO_COLOR`
- 色を使えない端末
- Unicode幅の差異
- 非UTF-8環境
- `TERM=dumb`
- 非TTY環境

色が無効でも、記号・枠・反転・ラベルで情報が判別できるUIにしてください。

非TTY環境で`zig80 tui`が実行された場合は、制御シーケンスを出力せず、分かりやすいエラーを返してください。

---

# Unicode

Unicodeブロック文字や罫線文字は利用可能ですが、ASCIIフォールバックを用意してください。

例：

```text
Unicode:
┌──────┐
│ █▀▄  │
└──────┘

ASCII:
+------+
| ##.  |
+------+
```

文字幅が不明な絵文字などは使用しないでください。

Frame Bufferでは原則として、表示幅1のコードポイントを使用してください。

全角文字や結合文字の完全対応は初期版では不要ですが、クラッシュやバッファ破壊を起こさないようにしてください。

---

# メモリ管理

TUI描画ループでは、可能な限り以下を避けてください。

- 毎フレームのアロケータ生成
- 毎セルの動的確保
- 毎キーイベントの動的確保
- 毎BusEventの動的確保
- 毎描画の文字列複製

以下を優先してください。

- 固定長配列
- リングバッファ
- 再利用可能なArrayList
- ArenaAllocatorのライフサイクルを限定
- Frame Bufferの再利用
- Stack上の小さな一時バッファ

Bus Traceは固定容量リングバッファとし、イベントごとのヒープ確保は禁止してください。

---

# 依存ゼロの確認

作業完了時に以下を確認してください。

```console
zig build
zig build test
```

加えて、以下を報告してください。

- `build.zig.zon`へ外部依存を追加していないこと
- Cライブラリをリンクしていないこと
- ncurses等を使用していないこと
- Zig標準ライブラリとOS標準APIのみで実装したこと
- macOSとLinuxで異なる処理がある箇所
- Windows対応の現在の状態

---

# 完了条件への追加

以下を追加の完了条件としてください。

1. 外部依存がゼロである
2. TUIライブラリを使用していない
3. Cライブラリをリンクしていない
4. `build.zig.zon`に外部パッケージがない
5. ANSI描画層がTUIアプリ本体から分離されている
6. raw modeの開始・終了が安全に管理されている
7. 正常終了・エラー終了の両方で端末状態が復旧する
8. 入力デコーダーにユニットテストがある
9. Frame Bufferまたは描画モデルにユニットテストがある
10. 非TTY環境で安全に失敗する
11. macOSとLinuxを対象としてビルド可能な構造である
12. 外部依存を追加しなければ実現困難な機能は、無理に追加せず制限として明記する

最優先事項は、外部ライブラリを使って見た目を早く完成させることではありません。

**Zigと標準ライブラリだけで、端末制御、入力、描画、イベントループを理解可能かつ再利用可能な形で実装し、Zig_80の教育的な思想に沿った依存ゼロのTUI基盤を作成してください。**
---

# 5. 推奨ディレクトリ構成

既存構成を優先し、必要に応じて調整してください。

概念的には以下のように分離してください。

```text
src/
├── core/
│   ├── cpu/
│   ├── assembler/
│   ├── disassembler/
│   ├── machine/
│   ├── debugger/
│   └── trace/
│
├── frontend/
│   ├── cli/
│   └── tui/
│       ├── app.zig
│       ├── state.zig
│       ├── command.zig
│       ├── event.zig
│       ├── event_loop.zig
│       ├── layout.zig
│       ├── terminal.zig
│       ├── keymap.zig
│       ├── editor/
│       │   ├── buffer.zig
│       │   ├── cursor.zig
│       │   └── view.zig
│       ├── screens/
│       │   ├── editor.zig
│       │   ├── debugger.zig
│       │   ├── memory.zig
│       │   ├── bus.zig
│       │   └── display.zig
│       └── widgets/
│           ├── source.zig
│           ├── diagnostics.zig
│           ├── registers.zig
│           ├── flags.zig
│           ├── disassembly.zig
│           ├── memory.zig
│           ├── bus_events.zig
│           ├── bus_waveform.zig
│           ├── virtual_display.zig
│           └── status_bar.zig
```

既存ファイルを大規模に移動すると回帰リスクが高い場合は、今回は既存構造を維持して`src/tui/`を追加するだけでも構いません。

ディレクトリ整理そのものを目的にした大規模リファクタリングは行わないでください。

---

# 6. TUI画面の基本構成

初期画面は、以下の4領域を基本としてください。

```text
┌ Zig_80 ─ game.asm ──────────────────────────────────────────────────┐
│ F2 Assemble  F5 Run  F6 Step  F7 Continue  F8 Pause  F9 Breakpoint │
├────────────────────────────────────────┬─────────────────────────────┤
│ SOURCE                                 │ CPU                         │
│                                        │                             │
│  1  org 0x0000                        │ PC  0012    SP  FFFE        │
│  2                                     │ AF  4100    BC  0000        │
│  3  start:                            │ DE  C000    HL  C008        │
│  4      ld hl, VRAM                   │                             │
│  5      ld a, 1                       │ Flags: S Z H P/V N C        │
│  6 >    ld (hl), a                    │        0 0 0  0  0 0        │
│  7      inc hl                        │                             │
│  8      jp loop                       │ Current instruction         │
│                                        │ 0012  77  LD (HL),A         │
├────────────────────────────────────────┴─────────────────────────────┤
│ BUS EVENTS                                                          │
│ T-State  Type           Address  Data  Signals                      │
│ 000000   Opcode Fetch   0000     21    M1 MREQ RD                   │
│ 000004   Memory Read    0001     00    MREQ RD                      │
│ 000007   Memory Read    0002     C0    MREQ RD                      │
├──────────────────────────────────────────────────────────────────────┤
│ PAUSED | PC=0012 | 42,817 T-states | F1 Help | Ctrl+Q Quit          │
└──────────────────────────────────────────────────────────────────────┘
```

小さなターミナルでは、領域を無理に詰め込まず、タブ式画面へフォールバックしてください。

最低限の推奨タブ：

```text
F1 Help
Alt+1 Editor
Alt+2 Debug
Alt+3 Memory
Alt+4 Bus
Alt+5 Display
```

ファンクションキーが環境により扱いにくい場合は、代替キーを必ず用意してください。

---

# 7. AppStateとCommand

TUI全体の状態を一つの構造体へまとめてください。

概念例：

```zig
pub const AppState = struct {
    allocator: std.mem.Allocator,

    mode: Mode,
    active_screen: Screen,

    source_path: ?[]const u8,
    source: SourceBuffer,
    source_dirty: bool,

    diagnostics: DiagnosticList,
    assembly: ?AssemblyResult,

    machine: Machine,
    debug_session: DebugSession,
    trace: TraceBuffer,

    selected_source_line: usize,
    selected_address: u16,
    selected_trace_event: usize,

    execution_state: ExecutionState,
    status_message: []const u8,
};
```

入力イベントをウィジェットが直接処理して状態を自由に変更する設計は避けてください。

入力は、可能な限り`Command`へ変換してください。

```zig
pub const Command = union(enum) {
    insert_character: u21,
    newline,
    backspace,
    delete,
    move_cursor: Direction,

    save,
    assemble,
    run,
    pause,
    continue_execution,
    step_instruction,
    reset,

    toggle_breakpoint,
    switch_screen: Screen,
    show_help,
    quit,
};
```

イベント処理、状態更新、描画を分離してください。

```text
Terminal Event
      ↓
Key Mapping
      ↓
Command
      ↓
App Update
      ↓
Render
```

---

# 8. ソースエディター

今回はZ80アセンブリ専用の小さなエディターとして実装してください。

## 必須機能

- UTF-8テキストの読み込み
- 行単位の保持
- カーソル移動
- 文字入力
- 改行
- Backspace
- Delete
- Home/End相当
- 上下左右移動
- 垂直スクロール
- 水平スクロール
- 行番号
- 保存
- 未保存状態の表示
- 現在行の強調
- PCに対応する実行行の強調
- ブレークポイント行の表示

## 今回不要

- Vim完全互換
- Emacs完全互換
- 高度な複数カーソル
- 検索置換
- マクロ
- 構文木ベース編集
- 完全なUndo/Redo

終了時に未保存の変更がある場合は、警告なしに破棄しないでください。

---

# 9. アセンブル処理

TUIの`Assemble`操作は、既存アセンブラAPIを直接使用してください。

アセンブル成功時：

- 生成バイト数
- シンボル数
- エントリーアドレス
- 成功メッセージ
- ソース行とアドレスの対応
- 対応するバイナリ

をAppStateへ保存してください。

アセンブル失敗時：

- TUIを終了しない
- 編集内容を失わない
- 診断パネルへ表示する
- 可能なら該当行へ移動できるようにする

診断例：

```text
game.asm:18:5: error: JR target is out of range

    jr game_loop
    ^

required offset: +226
valid range: -128...+127
suggestion: use `jp game_loop`
```

現在のアセンブラが構造化された診断情報を返していない場合は、TUI専用の文字列解析で無理に補完せず、Core側に再利用可能な診断型を追加してください。

概念例：

```zig
pub const Diagnostic = struct {
    severity: Severity,
    message: []const u8,
    file_path: ?[]const u8,
    line: ?usize,
    column: ?usize,
    source_line: ?[]const u8,
    hint: ?[]const u8,
};
```

CLIでも将来的に同じ診断型を利用できる構造にしてください。

---

# 10. 実行とデバッグ

## 実行状態

最低限、以下を区別してください。

```zig
pub const ExecutionState = enum {
    empty,
    assembled,
    paused,
    running,
    halted,
    breakpoint,
    limit_reached,
    faulted,
};
```

## 必須操作

- Assemble
- Run from reset
- Continue
- Pause
- Step instruction
- Reset
- Toggle breakpoint

## 実行制限

TUIでも無限ループにより操作不能にならないようにしてください。

1回の描画フレームで実行する命令数に上限を設け、イベントループへ定期的に制御を戻してください。

例：

```text
1 UI tick
  ├─ input polling
  ├─ maximum N instructions
  ├─ trace update
  └─ render
```

`run`または`continue`がUIスレッドを永久に占有しないようにしてください。

初期版ではマルチスレッド化せず、協調的な実行ループで構いません。

## ステップ実行時の差分

ステップ前後の状態を比較し、変更されたレジスタやフラグを識別できるようにしてください。

最低限、内部状態として以下を保持してください。

```zig
pub const CpuSnapshot = struct {
    registers: Registers,
    halted: bool,
    total_t_states: u64,
};
```

変更された値をTUI上で強調してください。

---

# 11. ソース行とPCの同期

アセンブラが生成するソース行・アドレス対応情報を利用し、現在のPCに対応するソース行を特定してください。

以下の同期を実装してください。

```text
Source line
    ↕
Machine address
    ↕
Disassembled instruction
    ↕
CPU PC
```

PCに対応するソース行が見つからない場合は、無理に推測せず、逆アセンブル表示だけを更新してください。

複数バイト命令については、PCが命令先頭を指す場合だけソース行へ同期してください。

---

# 12. レジスタとフラグ表示

最低限、現在実装されている以下を表示してください。

- AF
- BC
- DE
- HL
- SP
- PC
- A
- F
- B
- C
- D
- E
- H
- L
- halted
- total T-states

フラグ：

- S
- Z
- H
- P/V
- N
- C

各フラグは0/1表示に加え、十分な画面幅がある場合は短い説明を表示してください。

```text
Z 1 Zero
C 0 No carry
N 0 Addition
```

ステップ直後に変更されたレジスタとフラグは視覚的に区別してください。

色が使えない環境でも理解できるよう、色だけに依存しない表示にしてください。

---

# 13. メモリビュー

基本的な16進メモリビューを実装してください。

```text
        +0 +1 +2 +3 +4 +5 +6 +7 +8 +9 +A +B +C +D +E +F
C000    01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
C010    00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

必須機能：

- 表示開始アドレスの変更
- 上下スクロール
- HL、SP、PC、VRAM先頭へのジャンプ
- 直前のステップで変更されたメモリの識別
- 16進アドレス入力

今回、メモリの直接編集は不要です。

---

# 14. 仮想画面

既存の128×64、1bpp、SSD1306に近いVRAM形式を使用してください。

TUI内に仮想画面ビューを追加してください。

要件：

- 現在のVRAM内容を表示
- Unicodeブロック文字を利用可能
- 小さい端末では縮小表示
- 非対応端末ではASCII表示へフォールバック
- 実行中に一定間隔で更新
- 停止中も最新状態を表示

CPUやMachine側にTUI専用描画コードを追加しないでください。既存の画面レンダラーを抽象化または再利用してください。

---

# 15. Bus Trace基盤

ロジックアナライザー風表示の前提として、Z80のバスイベントを記録できる共通Trace基盤を追加してください。

## 15.1 BusEvent

概念的には次の情報を持たせてください。

```zig
pub const BusEventKind = enum {
    opcode_fetch,
    operand_read,
    memory_read,
    memory_write,
    io_read,
    io_write,
    refresh,
    interrupt_ack,
};

pub const BusSignals = packed struct {
    m1: bool = false,
    mreq: bool = false,
    iorq: bool = false,
    rd: bool = false,
    wr: bool = false,
    rfsh: bool = false,
    halt: bool = false,
    wait: bool = false,
    int: bool = false,
    nmi: bool = false,
};

pub const BusEvent = struct {
    sequence: u64,
    instruction_index: u64,
    t_state_start: u64,
    t_state_count: u16,

    kind: BusEventKind,
    address: u16,
    data: u8,
    signals: BusSignals,

    pc: u16,
};
```

現在のエミュレーターが命令単位であり、実際の各T-stateを再現していない場合は、イベントをcycle-accurateであるかのように偽装しないでください。

その場合は、READMEとUI上で以下を明記してください。

```text
Instruction-level modeled bus events
Not cycle-accurate
```

## 15.2 TraceSink

CPUやBusがTUIを直接知らないように、TraceSinkまたはObserver形式にしてください。

概念例：

```zig
pub const TraceSink = struct {
    context: *anyopaque,
    record_fn: *const fn (
        context: *anyopaque,
        event: BusEvent,
    ) void,

    pub fn record(self: TraceSink, event: BusEvent) void {
        self.record_fn(self.context, event);
    }
};
```

トレース無効時に不要な動的確保を行わない設計にしてください。

## 15.3 TraceBuffer

TUI用には固定上限を持つリングバッファを使用してください。

```text
default capacity: 4,096 events
```

上限へ達したら古いイベントから破棄してください。

毎命令・毎イベントでヒープ確保しないでください。

## 15.4 記録対象

現在実装可能な範囲で、最低限以下を記録してください。

- opcode fetch
- immediate operand read
- memory read
- memory write

I/O、refresh、interruptは未実装なら列挙値と拡張点だけ用意してください。

---

# 16. Busイベント一覧

今回のMVPでは、完全な波形表示より先に、確実に動作するイベント一覧を完成させてください。

```text
T-State  Instruction  Type          Address  Data  Signals
000000   #0           Opcode Fetch  0000     21    M1 MREQ RD
000004   #0           Operand Read  0001     00    MREQ RD
000007   #0           Operand Read  0002     C0    MREQ RD
000010   #1           Opcode Fetch  0003     3E    M1 MREQ RD
```

機能：

- 上下スクロール
- 最新イベントへ追従
- 自動追従のON/OFF
- 選択イベントの詳細表示
- イベント種別
- アドレス
- データ
- PC
- 命令番号
- T-state
- 信号
- 対応するソース行への移動

---

# 17. ロジックアナライザー風波形

完全なcycle-accurate実装は今回の必須条件ではありません。

ただし、記録済みBusEventを利用した初期波形ウィジェットを可能な範囲で実装してください。

初期対象信号：

- M1
- MREQ
- IORQ
- RD
- WR
- RFSH
- Address
- Data

表示例：

```text
M1    ──┐  ┌──────────────────────
        └──┘

MREQ  ──┐  ┌──┐  ┌──┐  ┌────────
        └──┘  └──┘  └──┘

RD    ──┐  ┌──┐  ┌──┐  ┌────────
        └──┘  └──┘  └──┘

WR    ───────────────────┐  ┌────
                         └──┘

ADDR  0000 0001 0002 C000
DATA  21   00   C0   01
```

要件：

- 選択したイベントを中心に表示
- 横スクロール
- 端末幅へクリップ
- 信号名を固定列に表示
- Address/Dataは数値行として表示
- 現在の実装が近似である場合は明記

波形表示の実装がMVP全体を不安定にする場合は、以下までで構いません。

1. BusEvent記録
2. Busイベント一覧
3. 波形ウィジェットのインターフェース
4. 最小限の静的波形レンダリング
5. 詳細実装を明確なTODOとして残す

ただし、空のスタブを完成扱いしないでください。

---

# 18. キーマップ

推奨キーマップ：

```text
Ctrl+S       Save
Ctrl+Q       Quit
F2           Assemble
F5           Run from reset
F6           Step instruction
F7           Continue
F8           Pause
F9           Toggle breakpoint
Ctrl+R       Reset
Alt+1        Editor
Alt+2        Debug
Alt+3        Memory
Alt+4        Bus
Alt+5        Display
?            Help
Esc          Cancel / Close dialog
```

ファンクションキーが使えない環境向けに、コマンドパレットまたは代替キーを用意してください。

例：

```text
:assemble
:run
:step
:continue
:pause
:reset
:write
:quit
```

初期版では簡単なコマンド入力欄でも構いません。

---

# 19. 端末状態の安全な復旧

TUI終了時には必ず以下を復旧してください。

- canonical mode
- echo
- cursor visibility
- alternate screen
- terminal attributes

以下の場合も復旧してください。

- 正常終了
- Ctrl+C
- エラー
- アセンブル失敗
- ファイル読み込み失敗
- 実行時エラー

可能な範囲で`defer`と明示的なterminal session型を利用してください。

通常の入力エラーに`catch unreachable`を使用しないでください。

---

# 20. リサイズと最小画面

ターミナルサイズ変更を検知して再レイアウトしてください。

推奨最小サイズ：

```text
80 columns × 24 rows
```

それ未満の場合はクラッシュせず、次のようなメッセージを表示してください。

```text
Terminal is too small.
Required: 80x24
Current: 62x18
```

または、単一パネル表示へフォールバックしてください。

---

# 21. テスト

TUI描画そのものを実端末だけで検証する設計にしないでください。

描画結果を抽象的なFrame Bufferへ出力し、可能な範囲でユニットテストしてください。

最低限、以下をテストしてください。

## SourceBuffer

- ファイル読み込み
- 文字挿入
- 改行
- Backspace
- Delete
- カーソル移動
- 行境界
- スクロール
- dirty state

## Command

- キー入力からCommandへの変換
- 代替キー
- 不明キーの無視

## AppState

- Assemble成功
- Assemble失敗
- Run
- Pause
- Step
- Reset
- Breakpoint
- 状態遷移
- ソース行とPCの同期

## Trace

- opcode fetch記録
- memory read記録
- memory write記録
- instruction index
- T-state
- リングバッファの上限
- 古いイベントの破棄
- trace無効時の動作

## Layout

- 通常サイズ
- 小さい端末
- リサイズ
- パネル境界

## Regression

既存の以下が引き続き動作することを確認してください。

```console
zig build
zig build test
zig build run -- --help
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- disasm zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
zig build run -- test zig-out/pixel.bin
```

---

# 22. サンプル

TUI確認用に、小さなサンプルを追加または既存サンプルを利用してください。

推奨サンプル：

```asm
org 0x0000

VRAM equ 0xC000

start:
    ld hl, VRAM
    ld a, 1

loop:
    ld (hl), a
    inc hl
    jp loop
```

このサンプルで以下を確認してください。

- ソースを開ける
- アセンブルできる
- 1命令ステップできる
- PCがソース行へ同期する
- HLが変化する
- VRAM書き込みがメモリビューへ反映される
- Bus Eventへmemory writeが追加される
- Displayビューへピクセルが表示される
- ブレークポイントで停止できる

---

# 23. READMEとドキュメント

READMEへ以下を追加してください。

- TUIの起動方法
- 基本キーマップ
- 画面構成
- 対応機能
- 端末要件
- TUIとCLIの関係
- Bus Traceの説明
- Bus Traceがcycle-accurateかどうか
- 現在の制限
- 今後の波形表示ロードマップ

必要であれば、詳細を以下へ分離してください。

```text
docs/tui.md
docs/debugger.md
docs/bus-trace.md
```

Bus Traceについては、実際より正確に見える説明をしないでください。

命令単位のモデルである場合は、次のように明記してください。

> 現在のBus Traceは、命令実行時に発生する論理的なバスアクセスを可視化したものです。実Z80の各T-stateおよび電気的タイミングを完全に再現するcycle-accurate波形ではありません。

---

# 24. 実装順序

以下の順序で進めてください。

## Phase 1：Core API整理

- 既存コード調査
- CLIとCoreの境界確認
- 必要最小限のAPI抽出
- 構造化診断
- CpuSnapshot
- DebugSessionの再利用可能化
- 既存CLI回帰テスト

## Phase 2：TUI基盤

- Terminal session
- raw mode
- alternate screen
- イベントループ
- Frame Buffer
- Layout
- AppState
- Command
- 最小画面
- 安全な終了

## Phase 3：Editor

- ファイル読み込み
- SourceBuffer
- カーソル
- 編集
- 保存
- 行番号
- スクロール
- dirty state

## Phase 4：AssembleとDebug

- Assemble
- Diagnostics
- Run
- Pause
- Step
- Reset
- Breakpoint
- Registers
- Flags
- Disassembly
- PCとソース行の同期

## Phase 5：MemoryとDisplay

- Hex memory view
- 変更アドレスの識別
- VRAM表示
- 仮想画面ビュー

## Phase 6：Bus Trace

- BusEvent
- TraceSink
- TraceBuffer
- opcode fetch
- operand read
- memory read/write
- イベント一覧
- ソース・命令との同期

## Phase 7：初期波形表示

- デジタル信号行
- Address/Data行
- 選択イベント
- 横スクロール
- 非cycle-accurate表記

各Phase終了時にビルドとテストを実行し、壊れた状態のまま次へ進まないでください。

---

# 25. 完了条件

今回の実装は、以下をすべて満たした時点で完了とします。

1. 既存CLIコマンドが引き続き動作する
2. `zig80 tui examples/pixel.asm`でTUIを起動できる
3. TUIでソースを編集・保存できる
4. TUIからアセンブルできる
5. アセンブルエラーを画面内に表示できる
6. アセンブルしたプログラムを実行できる
7. 一時停止と1命令ステップができる
8. PC、SP、主要レジスタ、フラグを表示できる
9. PCとソース行を対応表示できる
10. ブレークポイントで停止できる
11. メモリ内容を表示できる
12. VRAMを仮想画面として表示できる
13. opcode fetch、memory read、memory writeをBus Eventとして記録できる
14. Bus EventをTUI上の一覧で確認できる
15. 最小限のロジックアナライザー風表示、またはその安定した基盤が存在する
16. 無限ループ中もUI操作を継続できる
17. 終了時に端末状態が正常に戻る
18. macOSとLinuxを考慮した構造になっている
19. `zig build`が成功する
20. `zig build test`が成功する
21. READMEまたはdocsに利用方法と制限が記載されている

---

# 26. 今回避けること

以下は行わないでください。

- Z80全命令対応
- CPUコアの全面書き換え
- アセンブラの全面書き換え
- 既存CLIの削除
- TUIからCLIプロセスを起動する実装
- 大規模なファイル移動だけを目的としたリファクタリング
- cycle-accurateでないトレースをcycle-accurateと表現すること
- UI描画のための毎フレーム大量ヒープ確保
- Bus Eventごとのヒープ確保
- 端末状態を壊したまま終了する実装
- 未完成の空スタブを完成済みとして報告すること
- テスト未実行のまま完了報告すること

---

# 27. 作業完了時の報告

最後に以下を報告してください。

1. 既存構成について確認した内容
2. 実装したTUI機能
3. 追加したCore API
4. CLI互換性のために行った対応
5. Bus Traceの精度と現在の制限
6. 採用したTUIライブラリまたは端末実装方式
7. 作成・変更したファイル
8. 実行したテスト
9. テスト結果
10. TUIの起動方法
11. 基本操作
12. 未実装機能
13. 次に実装すべき項目
14. 既知の問題

可能であれば最後に、以下を実行してください。

```console
zig fmt --check .
zig build
zig build test
zig build run -- --help
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- disasm zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
zig build run -- test zig-out/pixel.bin
```

TUIは対話操作が必要なため、完全な自動実行が難しい場合でも、少なくとも起動処理、AppState、描画、Command、Traceについて自動テストを追加してください。

最優先事項は、見た目だけのTUIを作ることではありません。

**既存のZig_80 Coreを再利用し、ソース、機械語、CPU状態、メモリ、仮想画面、バスイベントが一つの開発体験として同期する、動作可能な垂直スライスを完成させてください。**
