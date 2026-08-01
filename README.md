# Zig_80

Zig_80 は、Z80 の命令、レジスタ、フラグ、メモリを観察しながら学べる、依存なしの CLI 開発環境です。Zig 0.16 系で動作する MVP で、アセンブラから実行・逆アセンブル・デバッグ・1bpp 描画までを一つのバイナリにまとめています。

## Build and quick start

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

実行には必ず命令数と T-state の既定上限があります。`run` では `--max-instructions N`、`--max-cycles N` で変更できます。`--screen` は終了時の画面を表示します。

## Commands

- `asm source.asm -o program.bin`: 2パスでアセンブルし、バイナリとシンボル一覧を出力
- `run program.bin`: HALT または上限まで実行
- `disasm program.bin`: アドレス、バイト列、命令を表示。未知命令は `DB`
- `debug program.bin`: 行単位 REPL。`help` でコマンド一覧を表示
- `test program.bin`: 最大100,000命令以内に HALT することを検証する簡易プログラムテスト
- `explain source.asm`: 各出力命令のエンコードを短く表示

デバッガーは `step/s`、`continue/c`、`registers/r`、`memory/m`、`disasm`、`break`、`delete`、`input`、`screen`、`reset`、`quit/q` に対応します。`input 0x11` のように入力レジスタを直接設定できます。

## Virtual machine

| Address | Purpose |
|---|---|
| `0000-7FFF` | program area |
| `8000-BFFF` | general RAM |
| `C000-C3FF` | video RAM |
| `C400` | input state |
| `C401-C402` | frame counter, little endian |
| `C403` | pseudo-random value |
| `C404-FFFF` | reserved RAM |

画面は 128×64、1bpp です。`C000 + (y / 8) * 128 + x` の bit `y % 8` が1ピクセルで、SSD1306に近いページ配置です。端末では上下2ピクセルを Unicode ブロック1文字へまとめます。入力は bit 0から順に Up、Down、Left、Right、A、B、Start、Reserved です。

## Assembly syntax

ラベル、前方参照、`;` コメント、10進 (`42`)、16進 (`0x2A`)、2進 (`0b101010`)、文字 (`'A'`)、現在アドレス (`$`)、単純な `+`/`-` 式に対応します。ディレクティブは `org`、`db`、`dw`、`equ` です。`db "HELLO", 0` も使用できます。複数セグメント形式ではなく、`org` は論理アドレスを変更し、出力ファイルへパディングしません。

対応命令は NOP、HALT、JP、条件 JP (Z/NZ)、JR、条件 JR (Z/NZ)、CALL、RET、仕様書記載の8/16ビット LD、INC/DEC、ADD A、SUB、CP、AF/BC/DE/HL の PUSH/POP です。算術命令は S/Z/H/PV/N/C を更新し、INC/DEC は C を保存します。

## Architecture

- CPU: fetch → decode → execute → registers/flags 更新 → T-state を `StepResult` で返却。端末やファイルには依存しません。
- Bus: 64KB アドレス空間への8/16ビットアクセスと将来の I/O 境界。16ビット値はリトルエンディアンで `FFFF` から `0000` へラップします。
- Machine: CPU、Bus、メモリマップ、VRAM、入力、フレーム／疑似乱数レジスタを統合します。
- Frontend: CLI、画面レンダラー、逆アセンブラ、REPLデバッガーです。

アセンブラの Pass 1 は行を解析してアドレスを計算しシンボルを収集します。Pass 2 はシンボルを解決して命令をエンコードし、バイト列とソース行対応を生成します。

新しい命令は CPU の opcode family、アセンブラの encoder、逆アセンブラへ追加します。固定命令の共有メタデータは `src/cpu/instruction.zig` にあり、今後対応範囲を広げる際の統合点です。周辺機器は Bus の予約アドレスと Machine の同期処理を追加し、CPU へデバイス依存を持ち込まないでください。

## Current limitations and roadmap

MVP は Z80 全命令、CB/DD/ED/FD prefix、IX/IY、割り込み、I/O命令、cycle-accurate 動作、実時間入力、ウォッチポイント、タイムトラベル、UART/PSG/SD、Wasm、GDB/LSP に未対応です。ROM 範囲は現在書き込み保護されません。画面は実行終了時またはデバッガーで明示表示し、非TTY向け ANSI 更新は行いません。CLI `test` は簡易 HALT 検証で、詳細なレジスタ／メモリ検証には `Machine` を使う Zig ユニットテスト API を利用します。

次の優先事項は、命令メタデータの共有範囲拡大、詳細なテスト定義形式、ウォッチポイント、非ブロッキング実時間入力、CB prefix の順です。
