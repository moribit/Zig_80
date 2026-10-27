# PC-8001 Chat Protocol v1 / チャットプロトコル

This protocol owns UART after the resident acknowledges EXEC. It is distinct
from deploy framing; Pico transports both opaquely. Returning from the app
returns UART ownership to the resident. Do not interleave deploy requests.

## Frame

A5 5A TYPE SEQ LEN PAYLOAD CRC_LO CRC_HI, at most 39 bytes. LEN is 0–32.
CRC-16/CCITT-FALSE: polynomial 1021h, initial FFFFh, no reflection or final XOR.
The vector "123456789" gives 29B1h. CRC covers TYPE through payload, excludes
sync, and is little-endian. LEN permits sync bytes inside a payload.

| Type | Direction | Payload |
|---|---|---|
| 1 HELLO | PC→host | C1 version marker |
| 2 READY | host→PC | C1 plus 0–20 printable model-label bytes |
| 3 PROMPT | PC→host | final flag 0/1 plus 1–31 printable ASCII bytes |
| 4 TEXT | host→PC | 0–32 normalized ASCII bytes, including LF |
| 5 DONE | host→PC | empty; all TEXT already acknowledged |
| 6 ERROR | host→PC | empty in v1; display error and allow next question |
| 7 ACK | either | empty; SEQ identifies the acknowledged frame |
| 8 CANCEL | either | empty; terminate and return to resident |

The PC reliably sends HELLO with sequence 0. The host ACKs and reliably sends
READY with sequence 0 in its own direction. Subsequent directional sequences
advance independently modulo 256. A 64-byte prompt takes up to three PROMPT
frames; only the last has final=1. Each segment is ACKed before HTTP starts.

## Reliability

One outstanding data frame per direction. An identical retransmission of the
last accepted frame is ACKed again without applying it. Changed same-sequence
frames and out-of-order frames are not ACKed or displayed. ACKs are not
acknowledged. Both senders allow two retransmissions.

Host ACK timeout is four seconds after the complete frame drains. At 300bps/
8N1, a maximum TEXT frame takes about 1.3 seconds and ACK about 0.23 seconds.
USB lease renewal continues during both. The PC's inter-byte wait is bounded
by 65536 status polls, not a calibrated wall-clock timer; PE/OE/FE and transmit
timeouts safely return to the resident. Host partial frames reset after a
two-second gap. Missing ACK causes complete retransmission. There is no
mid-conversation reconnect or automatic sequence reset.

ASCII validation precedes rendering; CRC/length failure drops the frame and
sync search resumes. The PC remembers the entire prior frame including CRC;
the host compares kind, length and payload. UTF-8 is host-only and normalized
to uppercase ASCII. Typographic quotes, dashes and nonbreaking spaces are
folded to their ASCII counterparts; other non-ASCII becomes a question mark,
and controls except LF become spaces. PROMPT permits 20h–7Eh. These display
changes do not change protocol framing or the C1 handshake.

CANCEL is ACKed before return; the PC drains its transmitter before RET.
ESC/STOP initiates reliable CANCEL. Host Ctrl-C attempts a bounded CANCEL and
always releases GPIO/DTR; a broken/unacknowledged connection may require
ESC/STOP or normal bootstrap recovery.

CRC detects accidental errors and provides neither authentication nor proof
of electrical safety. Startup Hi-Z, explicit TX permission, the 1s firmware
lease, watchdog and disconnect handling are unchanged.

## Classic terminal UI / 固定入力欄UI

The classic layout is a presentation-only change: C1, 32-byte payload limits,
CRC16, sequence numbers, duplicate suppression, ACK and retries are unchanged.
The host still defaults to eight-byte TEXT chunks with a 100ms flush.

READY's model label is right-aligned on row 0. PROMPT is assembled from the
complete 64-byte input buffer, independently of row 18's horizontal viewport.
After the last PROMPT ACK, the UI shows THINKING. Empty TEXT is acknowledged
without ending that state or clearing the spinner. The first nonempty TEXT
validated in full changes it to RECEIVING and replaces the spinner; duplicate
or invalid frames never change the display. DONE clears any remaining spinner
and returns input focus/READY to row 18. ERROR returns input focus with ERROR.
The status line is local state and adds no protocol messages.

固定入力・会話領域の分離は表示処理だけの変更です。UART所有権、PicoのTX許可、
リース更新、Hi-Z、常駐ローダーへの復帰ABIは変更しません。本文は2〜16行だけを
スクロールし、入力欄18行・状態19行へ受信本文を描画しません。
