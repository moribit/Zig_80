# Zig_80

[English](README.md)

Zig_80は、Z80プログラムを書く、アセンブルする、実行する、デバッグする、検証するための依存なし統合環境です。学習にも利用できますが、初心者、Assembly経験者、Retro Game開発者、Emulator開発者、Headless CI利用者を対象とする通常の開発Toolとして設計します。Zig 0.16系のMVPで、Assembly、実行、逆Assembly、Debug、Trace、1bpp描画を一つのBinaryへまとめています。

プロジェクトの思想、実機を含む将来像、長期的な設計方針については、[ビジョンとアーキテクチャの方向性](docs/vision.ja.md) を参照してください。記載されている将来像は構想段階であり、実装予定を確約するものではありません。

Z80、Assembly言語、CPU Hardwareが初めての場合は、[Zig_80 IDE入門チュートリアル](docs/tutorial/README.ja.md)から始めてください。1命令のROMから、Register、Memory、分岐、Stack、論理Bus Event、Input、1bpp DisplayのDebugまでを段階的に説明しています。

## ビルドとクイックスタート

```console
zig build
zig build test
zig build run -- --help
zig build run -- asm examples/pixel.asm -o zig-out/pixel.bin
zig build run -- disasm zig-out/pixel.bin
zig build run -- run zig-out/pixel.bin --screen
zig build run -- debug zig-out/pixel.bin
zig build run -- test zig-out/pixel.bin
```

## ターミナルUI

アセンブリソースを指定して、依存ゼロのターミナルフロントエンドを起動できます。

```console
zig build run -- tui examples/pixel.asm
```

すぐにHALTしないプログラムを確認するには、自律動作するPinpon demoを開きます。

```console
zig build run -- tui examples/pinpon.asm
```

`Ctrl+E`で実行し、`Ctrl+5`またはCommand Paletteの`display`で、固定Paddle間をBallが往復する様子を確認できます。Escapeで一時停止します。このdemoは意図的に無限Loopしますが、TUIの実行上限は安全停止として有効です。

Sourceを主役にしたTUIは通常画面の約70%をEditorに割り当て、補助色のAddress／Bytes、現在PC、Group化したCPU／Instructionカード、論理Busアクセスを関連付けます。静かなHeaderはFile状態だけを示し、Pane固有Context HelpはBadge風Status Barへ表示します。Fnキーを使わずCtrl+PのCommand Paletteを中心に操作します。Bus画面はInstruction Cardと等幅のLogical Waveformを横に表示します。この波形はcycle-accurateではありません。詳細は[TUIガイド](docs/tui.ja.md)を参照してください。

Displayは128×64、1bpp出力をゲーム画面として扱い、1x／2x／4x倍率（既定2x）、任意Grid、Pixel検査、更新番号、変更Pixel数、Display更新FPSを表示します。Stepでは観測したSource実行結果、Register前後値、論理Bus Access、変更VRAM Pixelを関連付け、Bus選択時も命令PCと保存済みCPU状態へ同期します。Display倍率／GridとBus Filterは`Ctrl+P`から変更できます。

Logic AnalyzerはHigh／Low Trace、明示的な立上り・立下り、垂直Time Cursor、1x／2x／4x／Fit Zoom、独立Panを備えます。時間軸は論理Event順序であり、cycle-accurateではないことを常時明記します。

Sourceは汎用テキストエディターではなくZ80専用です。キャッシュされたTokenからMnemonic、Register、Directive、Operand、Source Labelを文脈補完し、自動Indent、選択、Undo/Redo、Incremental Search、Label移動／Rename、Inline Diagnostic／Bytes、Stepで実際に起きた変化の短時間Overlayを提供します。

TUIのRunとContinueは、既定で総命令数10,000,000または総T-state 100,000,000へ達すると停止します。Resetは両カウンターを消去し、上限停止後も明示的なStepは実行できます。

実行には必ず命令数と T-state の既定上限があります。`run` では `--max-instructions N`、`--max-cycles N` で変更できます。`--screen` は終了時の画面を表示します。

## コマンド

- `asm source.asm -o program.bin`: 2パスでアセンブルし、バイナリとシンボル一覧を出力
- `run program.bin`: HALT または上限まで実行
- `disasm program.bin`: アドレス、バイト列、命令を表示。未知命令は `DB`
- `debug program.bin`: 行単位 REPL。`help` でコマンド一覧を表示
- `test program.bin`: 最大100,000命令以内に HALT することを検証する簡易プログラムテスト
- `explain source.asm`: 各出力命令のエンコードを短く表示

デバッガーは `step/s`、`continue/c`、`registers/r`、`memory/m`、`disasm`、`break`、`delete`、`input`、`screen`、`reset`、`quit/q` に対応します。`input 0x11` のように入力レジスタを直接設定できます。

## 仮想マシン

| アドレス | 用途 |
|---|---|
| `0000-7FFF` | プログラム領域 |
| `8000-BFFF` | 汎用RAM |
| `C000-C3FF` | ビデオRAM |
| `C400` | 入力状態 |
| `C401-C402` | フレームカウンター（リトルエンディアン） |
| `C403` | 疑似乱数値 |
| `C404-FFFF` | 予約RAM |

画面は 128×64、1bpp です。`C000 + (y / 8) * 128 + x` の bit `y % 8` が1ピクセルで、SSD1306に近いページ配置です。端末では上下2ピクセルを Unicode ブロック1文字へまとめます。入力は bit 0から順に Up、Down、Left、Right、A、B、Start、Reserved です。

## アセンブリ構文

ラベル、前方参照、`;` コメント、10進 (`42`)、16進 (`0x2A`)、2進 (`0b101010`)、文字 (`'A'`)、現在アドレス (`$`)、単純な `+`/`-` 式に対応します。ディレクティブは `org`、`db`、`dw`、`equ` です。`db "HELLO", 0` も使用できます。複数セグメント形式ではなく、`org` は論理アドレスを変更し、出力ファイルへパディングしません。

対応命令はNOP、HALT、JP、条件JP (Z/NZ)、JR、条件JR (Z/NZ)、CALL、RET、即値/Memory LD、8 bit Registerと`(HL)`間の一般LD、INC/DEC、ADD A、SUB、CP、AND、XOR、OR、AF/BC/DE/HLのPUSH/POPです。算術/論理命令はS/Z/H/PV/N/Cを更新し、INC/DECはCを保存します。

## Documentation

- [Tutorial](docs/tutorial/README.ja.md): CLI/TUIを使うZ80 Programmingの順序教材
- [Reference](docs/reference/README.ja.md): 実装済みCLI、Assembler、命令、Debugger、Machine、Key
- [Guides](docs/guides/README.ja.md): Game、Display、Input、Debug、Profile、Asset、Hardware
- [Architecture](docs/architecture/README.ja.md): Core境界と将来Hardware Target
- [Roadmap](docs/roadmap.md): 将来作業のPhaseと依存関係

## アーキテクチャ

- CPU: fetch → decode → execute → registers/flags 更新 → T-state を `StepResult` で返却。端末やファイルには依存しません。
- Bus: 64KB アドレス空間への8/16ビットアクセスと将来の I/O 境界。16ビット値はリトルエンディアンで `FFFF` から `0000` へラップします。
- Machine: CPU、Bus、メモリマップ、VRAM、入力、フレーム／疑似乱数レジスタを統合します。
- Frontend: CLI、画面レンダラー、逆アセンブラ、REPLデバッガーです。

アセンブラの Pass 1 は行を解析してアドレスを計算しシンボルを収集します。Pass 2 はシンボルを解決して命令をエンコードし、バイト列とソース行対応を生成します。

新しい命令は CPU の opcode family、アセンブラの encoder、逆アセンブラへ追加します。固定命令の共有メタデータは `src/cpu/instruction.zig` にあり、今後対応範囲を広げる際の統合点です。周辺機器は Bus の予約アドレスと Machine の同期処理を追加し、CPU へデバイス依存を持ち込まないでください。

## 現在の制限とロードマップ

MVP は Z80 全命令、CB/DD/ED/FD prefix、IX/IY、割り込み、I/O命令、cycle-accurate 動作、実時間入力、ウォッチポイント、タイムトラベル、UART/PSG/SD、Wasm、GDB/LSP に未対応です。ROM 範囲は現在書き込み保護されません。Bus Traceは命令単位の論理アクセスであり、実Z80の電気的タイミングや各T-stateを再現するものではありません。CLI `test` は簡易 HALT 検証で、詳細なレジスタ／メモリ検証には `Machine` を使う Zig ユニットテスト API を利用します。

次の優先事項は、命令メタデータの共有範囲拡大、詳細なテスト定義形式、ウォッチポイント、非ブロッキング実時間入力、CB prefix の順です。
