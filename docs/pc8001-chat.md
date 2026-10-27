# PC-8001 local LLM chat / ローカルLLMチャット

PC-8001 is a lightweight ASCII terminal. The Zig host owns Ollama HTTP,
conversation history, normalization and streaming. Pico 2 remains the existing
USB/PIO bridge; no firmware change is needed.

## Setup / 起動

Use Zig 0.17, the validated Pico firmware 0.1.4 (300bps/8N1, inverted UART),
and the existing electrical checks. Start with the
[resident loader](pc8001-serial-loader.md) waiting. Run from the repository root:

```sh
zig build
ollama pull gemma3:1b
# Only if the Ollama service is not already running:
ollama serve
zig-out/bin/zig80 chat --target pc8001 --port /dev/cu.usbmodemXXXX \
  --provider ollama --model gemma3:1b --enable-tx --voltage-confirmed \
  --log chat-session.jsonl
```

On macOS, keep the host awake for the lifetime of the chat process:

```sh
caffeinate -i zig-out/bin/zig80 chat --target pc8001 --port /dev/cu.usbmodemXXXX \
  --provider ollama --model gemma4:e2b --enable-tx --voltage-confirmed \
  --log chat-gemma4-session.jsonl
```

Download the selected model first (`ollama pull gemma4:e2b`). Model selection
requires no Z80 or Pico firmware change. `caffeinate` is an optional macOS system
tool, not a runtime dependency of Zig_80; the assertion ends with the child
process. It prevents idle system sleep, not deliberate sleep or closing the lid.

MacがスリープするとKEEPALIVEが止まり、Picoは1秒の送信許可を失効させます。
復帰後も自動的に再ARMしません。PC側にREADYが残っていても接続中とは限りません。
2026-10-27の実機セッションでは、Macのスリープ復帰と同時刻にNOT_ARMEDで
ホストが終了し、PCは常駐ローダーへ戻っていました。ローダー応答を確認してから
新しいchatセッションで再デプロイします。`--no-deploy`で途中状態へ再接続しないでください。
PicoのリースやHi-Zを緩める方法では対処しません。

Both TX flags are required and do not replace physical checks. Logs must have
a new filename. The command assembles, uploads, verifies RAM CRC and executes,
then retains the same leased USB session for chat. Wait for "Chat ready" on
the host and READY on the PC. Do not enter TERM or rerun USR.

常駐ローダー待機状態で実行します。アセンブル、CRC付き転送、実行、チャット接続を
自動で行います。別のアプリが動作中なら先に終了してください。

## Host startup progress / ホストの進捗表示

The CLI immediately flushes its startup messages, including when stdout is
redirected. It reports assembly, USB connection/configuration, resident loader
waiting/detection, BEGIN, upload, RAM CRC verification, EXEC acknowledgement,
and the application HELLO/READY handshake separately. A displayed success means
that stage has actually completed; READY is not printed during transfer.

300bpsでは起動時転送に約2分かかる場合があります。転送中は受信確認済みの64バイト
ごとに `Uploading: 64/1743 bytes (3%) elapsed=...s ETA~...s` のように表示します。
残り時間は実測した転送ペースからの推定であり、再送や検証時間は保証しません。
再送中は既存のRetry表示が出て、受信確認まで進捗を増やしません。
ローダー無応答や接続失敗の場合も、直前の表示から待っていた処理を判別できます。

After a submitted question, the host reports the prompt byte count and model
request before waiting for inference, then reports completion as before. Prompt
contents are not printed by these status messages. The wire protocol, heartbeat,
TX lease and PC-8001 application binary are unchanged.

## Keyboard and display / 操作

* A–Z, digits, space and basic punctuation; SHIFT selects punctuation.
* Return submits up to 64 bytes. Del/Ins is Backspace.
* Held keys do not repeat; a short debounce delay applies only to key input.
* ESC/STOP exits via reliable CANCEL and RET to the resident (A=43h).
* Host Ctrl-C cancels HTTP and attempts bounded application cancellation.
  TX/DTR are always released. A broken link or lost acknowledgement can require
  ESC/STOP on the PC; do not assume the application returned after an error.

The original active-low matrix is scanned directly, without ROM calls or
interrupts, based on [MAME's PC-8001 keyboard](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc88_kbd.cpp).
40/80-column mode is detected from EA66h without changing the display mode.
The classic terminal uses the upper 20 rows in either 20- or 25-row hardware
mode. The lower five rows are unused in 25-row mode.

| Row | Contents / 内容 |
|---|---|
| 0 | ZIG_80 CHAT; READY model label aligned right (up to 20 characters) |
| 1 | Header divider, 40 or 80 visible dashes |
| 2–16 | 15-row conversation area; only these rows scroll |
| 17 | Input divider |
| 18 | Fixed `> ` input and blinking cursor |
| 19 | Status on the left; ESC:EXIT on the right |

Submitted questions begin with `> `; answers and wrapped continuation lines
have a two-character indent. A blank row separates utterances. Enter copies
the question into history and clears the fixed input. Input remains locked
until DONE or ERROR. There is no repeated YOU>/AI> prefix.

40文字では入力欄の38文字分、80文字では78文字分を使います。入力バッファはどちらも
64バイトです。40文字で38文字を超えると末尾38文字を表示する横スクロールとなり、
Backspaceで削除すると前の文字が再表示されます。末尾まで埋まった場合、カーソルは
最右セルに留まります。入力欄は折り返さず、本文のスクロールから独立しています。
The viewport start is `max(0, length - (width - 2))`; the cursor is clamped to
the last visible cell. The full prompt, rather than just its viewport, is sent.

Status transitions are CONNECTING → READY → SENDING → THINKING → RECEIVING →
READY. THINKING lasts until the first nonempty validated TEXT. Empty TEXT does
not change it; empty DONE returns directly to READY. ERROR unlocks input with
an ERROR status, and normal cancellation shows EXITING.

回答待ちの記号は会話領域の回答開始位置（2文字インデント後）で
`. → + → * → +`と変化します。最初の有効な空でないTEXTで消し、同じ位置から本文を
描画します。空の回答、エラー、終了時も記号を消します。本文を上書きしません。
VRTC rising edges (port 40h, bit 5) advance the spinner once every eight frames.
It never waits for retrace; UART reception can temporarily pause animation.

The uPD3301 hardware cursor follows fixed input, then the spinner/answer tail,
and returns to row 18 on completion. Only command 81h at port 51h and X/Y at
50h are written. Forty-column X coordinates are doubled. Cursor shape/blink,
video/UART configuration and all 1000 attribute bytes are preserved. Character
cells are initially cleared; original screen contents are not restored on exit.
Start from a normal text screen: leftover graphics attributes are not converted.

英字は大文字へ統一します。曲がった引用符、ダッシュ、改行禁止空白をASCIIへ正規化し、
その他の非ASCIIは「?」へ変換します。文字追加は対象セルだけ、入力編集は入力行だけを
更新し、スクロール時だけ会話15行を移動します。ヘッダー・区切り線・入力・状態行は
スクロールしません。40/80文字、カラー/モノクロの設定を変更しません。

Display behavior follows the [MAME PC-8001 port map](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc8001.cpp)
and [uPD3301 implementation](https://github.com/mamedev/mame/blob/master/src/devices/video/upd3301.cpp).

## Streaming and safety / ストリーミング

Ollama [POST /api/chat](https://docs.ollama.com/api/chat) is called with
stream=true. Nonblocking loopback HTTP/1.1 supports chunked and content-length
bodies. Bounded NDJSON events are parsed as received, normalized and queued.
TEXT flushes at 8 bytes by default, LF, after 100ms, or on DONE. Queued bytes remain
until ACK, and HTTP reading pauses during UART transmission/ACK waits. TCP
buffers provide additional backpressure. No artificial character delay is used.

The smaller chunks reduce the size of each visible burst. --text-chunk-size
accepts 1–32: 4 gives finer updates, while 16 or 32 favors throughput. Smaller
chunks incur more CRC/ACK overhead on the 300bps link. The protocol still
allows 32 bytes and renders only validated frames; it does not display
unverified bytes or pace a completed response with delays.

Responses are limited to 160 ASCII characters (configurable downward); reaching
the limit immediately closes HTTP to cancel further generation. Completed
history defaults to four turns, configurable 0–8. HTTP inactivity defaults to
60 seconds. A provider error sends ERROR and enables another question.

The event loop pumps USB during HTTP waits and UART transmission. Connection
start, reads and writes are nonblocking. Header, body, JSON line, history and
queue memory are bounded. The existing 150ms heartbeat and 1s firmware lease
are unchanged. Sessions default to 30 minutes, configurable up to 60. Transport
failure never automatically re-arms TX.

--ollama-url supports loopback HTTP only (127.0.0.1 or localhost), with no TLS,
redirects or DNS. --mock supplies staggered chunks without Ollama. --no-deploy
only attaches to a freshly started app waiting for HELLO ACK; it cannot resume
an unknown in-flight conversation. Restart through the loader after a lost
session. Optional logs contain response text.

## RAM

| Range | Purpose |
|---|---|
| D000–D6CE | 1743-byte code, tables and three-byte ACK scratch |
| D6CF–D714 | Code headroom (70 bytes) |
| D715–D737 | Canonical transmit frame: type/sequence/length/payload (35 bytes) |
| D738–D75C | Exact previous received frame (37 bytes) |
| D75D–D766 | Keyboard edge state (10 bytes) |
| D770–D78B | Stack/display/protocol/cursor/spinner state, saved chat position and input viewport (28 bytes) |
| D78C–D7CB | Complete 64-byte prompt |
| D7CC–D7F0 | Receive frame including CRC, excluding sync (37 bytes) |
| E700–E7FF | Unchanged resident private stack |

The previous image was 1683 bytes. Static working storage reserves 211 bytes;
94 bytes remain unallocated, including 70 bytes before TX. Before ARM the host
rejects code crossing D715h; tests also assert every buffer range is disjoint
and contained in D000–D7FF. The old D6C0h RX allocation is explicitly replaced,
not overwritten. TX uses its wire-compatible canonical form without an unused
byte or a redundant frame copy. RX/TX/drain routines are shared separately from
initialization, avoiding unused initialization code in chat. Loader binaries
and protocols remain unchanged.

コードと静的データは2KB内です。ローダーのRAM保護範囲・スタック・Picoファームウェアは
変更しません。エミュレーターは保護RAM、BASICワーク、属性領域、コードの非破壊を
検証します。任意のネイティブアプリを実行時に隔離する仕組みではありません。

## Tests / 検証

```sh
zig build test --summary all
zig build loader-mock
python3 scripts/test_chat.py
# Optional installed Gemma, still with emulated Z80 and PTY:
python3 scripts/test_chat.py --live-ollama
# Optional real-time endurance, excluded from normal CI:
python3 scripts/soak_chat.py 1800
```

The integration path uses the actual CLI, portable C Pico bridge, existing CPU/
8251 model, assembled chat app and independent chunked HTTP server. Tests cover
editing, Shift, 64-byte bounds, all video modes, wrapping/scrolling, attributes,
protected RAM, CRC rejection, duplicate suppression, retransmission, history,
KEEPALIVE during provider stalls, SIGINT and another deploy after return.

Mock and live Gemma tests observed Z80 display before the host received model
DONE. This is receive-side timing, not instrumentation of the model's internal
last-token timestamp. PTY timing is accelerated and does not prove physical
UART timing. A live-model record is generated in
zig-out/pc8001/deploy-tests/chat-live-ollama.json.

For the original release, the physical PC-8001's 1528-byte image passed RAM CRC A7A1, EXEC and
HELLO/READY handshake on 2026-10-27. Physical input, progressive answers for two turns, ESC
exit and a subsequent resident HELLO/ABORT succeeded. The host validated
transport counters and released TX. See the [physical record](pc8001-validation-records/2026-10-27-chat-014.json). The 30-minute endurance test is pending at the
user's request. Earlier loader/game success is not chat validation.

The first UI refinement image was 1635 bytes (CRC16 4B3F). Its typographic punctuation,
cursor tracking, VRTC spinner, preserved attributes and protected RAM pass
automated tests, including UTF-8 split across HTTP chunks. Physical upload and
HELLO/READY, readable apostrophes, cursor following, spinner animation and ESC
return were confirmed on the physical PC-8001. A subsequent resident HELLO/ABORT
also passed and TX was released. See the [UI physical record](pc8001-validation-records/2026-10-27-chat-ui-014.json).

See [Chat Protocol v1](pc8001-chat-protocol.md).

The inline/smaller-burst revision is 1683 bytes (CRC16 F1A3). The user confirmed
the JIS-safe loading symbols and continued input/answers after the screen
filled. Ten real Gemma turns, ESC exit, resident HELLO/ABORT and TX release
succeeded with no retransmissions or transport error increase. See the
[20-row physical record](pc8001-validation-records/2026-10-27-chat-screen20-014.json).

## Classic terminal validation / 新UIの実機確認

The classic fixed-input image is 1743 bytes, CRC16 B9A6. Physical upload,
RAM verification, EXEC and HELLO/READY with Gemma succeeded on 2026-10-27.
The user confirmed input, horizontal input scrolling and conversation scrolling.
The session remains running at the user's request; physical ESC return and the
next deploy for this UI revision are pending. See the
[classic UI record](pc8001-validation-records/2026-10-27-chat-classic-014.json).
The earlier records above concern previous UIs. Automated checks pass: 145 Zig tests, C bridge and five PIO-model
cases, eight host cases, fourteen deploy cases, eight chat integration cases
(including a live Ollama run and 15-turn mock), and three bootstrap-media cases.
Chat tests cover both 20- and 25-row cursor bounds with all four width/color
settings, fixed VRAM cells and all attribute bytes. Tests use functional CPU/
8251/CRTC models, not cycle-accurate hardware verification.
The 30-minute endurance test remains pending by user request.

1. Keep the resident loader waiting; run the setup command with a new log path.
2. Check title/model, full-width dividers, fixed row-18 prompt and READY/ESC:EXIT.
3. Ask a short question. Check THINKING/spinner → RECEIVING with progressive text.
4. Continue at least 15 turns: only rows 2–16 should scroll.
5. Enter 64 letters; in 40 columns, check the final 38 remain visible. Backspace
   below 38 and confirm older characters reappear. Submit and verify the reply.
6. Press ESC/STOP. After the host reports TX released, deploy hello with
   `zig-out/bin/zig80 deploy zig-out/pc8001/hello.bin --target pc8001 --port
   /dev/cu.usbmodemXXXX --enable-tx --voltage-confirmed --wait-return`.

新UIの実機確認は旧UIの実績と区別します。RESET・電源操作・TERMは不要です。
表示を確認できない場合、成功扱いにせずログと画面の状態を記録してください。
