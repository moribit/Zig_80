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

Both TX flags are required and do not replace physical checks. Logs must have
a new filename. The command assembles, uploads, verifies RAM CRC and executes,
then retains the same leased USB session for chat. Wait for "Chat ready" on
the host and READY on the PC. Do not enter TERM or rerun USR.

常駐ローダー待機状態で実行します。アセンブル、CRC付き転送、実行、チャット接続を
自動で行います。別のアプリが動作中なら先に終了してください。

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
40/80-column mode is detected from EA66h. The header shows the model label;
the status row shows CONNECTING, READY or RECEIVING. The hardware blinking
cursor follows both input and answer text, including wrapping, Backspace
and scrolling. It uses the uPD3301 cursor-position command (81h at port 51h,
column/row at 50h); 40-column positions use twice the displayed column. The
existing cursor shape/blink timing is retained and unchanged positions are not
reloaded. Timing/attribute/UART configuration is preserved. VRAM writes touch
only character cells; all 1000 attribute bytes and the video/UART modes are
preserved. Start from a
normal text screen; arbitrary leftover graphics attributes are not converted.
Screen contents are not restored on exit.

英字は大文字へ統一します。曲がった単引用符・二重引用符はASCIIの引用符へ、
ダッシュは「-」、改行禁止空白は通常の空白へ変換します。それ以外の非ASCII文字は
「?」、LF以外の制御文字は空白になります。点滅カーソルは入力・回答の末尾に追従します。
回答待ちの間は「AI> .」の位置で`. → + → * → +`と記号が変化し、
最初の回答が届くと本文に置き換わります。円記号になるバックスラッシュ等は使いません。
属性と表示モードを維持し、文字領域だけをクリア・更新します。

The four-phase spinner appears immediately after AI> and advances every eight
VRTC rising edges (port 40h, bit 5). The cursor waits one cell after it. It never
waits for retrace or adds UART/display delays; frame reception can temporarily
pause the indicator. First valid TEXT replaces it; empty DONE, ERROR and exit
also clear it. Later answer text is never overwritten by the indicator.
Cursor/VRTC behavior follows the
[MAME PC-8001 port map](https://github.com/mamedev/mame/blob/master/src/mame/nec/pc8001.cpp)
and [uPD3301 command implementation](https://github.com/mamedev/mame/blob/master/src/devices/video/upd3301.cpp).

The chat viewport uses rows 0–19, keeping the title/status fixed and scrolling
only rows 2–19. This is visible in both 20- and 25-row hardware modes without
changing the CRTC configuration; five lower rows remain unused in 25-row mode.
The [NEC manual's power-on description (PDF page 15)](https://oldcrap.org/wp-content/uploads/2024/07/nec-pc8001b-users-manual.pdf)
specifies 40 columns by 20 rows. Earlier chat versions assumed 25 rows and
could put the next prompt outside that visible area. A regression test now
fills and scrolls the screen repeatedly for 15 turns, checks every prompt and
cursor stays below row 20, and exercises sequence-number wraparound.

標準の20行表示で入力欄が画面外に隠れないよう、本文を2〜19行の範囲でスクロールします。
25行表示でも表示モードは変えず、上側20行を使います。

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
| D000–D692 | 1683-byte app, tables and ACK scratch |
| D6C0–D6E6 | receive frame |
| D700–D726 | transmit frame |
| D730–D754 | exact previous received frame |
| D760–D769 | keyboard edge state |
| D770–D77E | saved stack, display and protocol state |
| D780–D787 | cached cursor position and VRTC/spinner state |
| D7C0–D7FF | 64-byte prompt |
| E700–E7FF | existing resident private stack |

Before ARM, code is checked not to cross D6C0h. Upload uses the resident's
D000–D7FF checks. Emulator tests verify no writes to protected RAM, resident
code or BASIC work. Native apps are not execution sandboxes.

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
