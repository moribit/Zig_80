# Host serial test / wire protocol v1

The host implementation is `src/serial/`, integrated as `zig80 serial` and built
with Zig 0.17.0 using only its standard library. macOS and Linux use nonblocking
POSIX TTY I/O. Windows is not supported by this tool. USB CDC candidates are listed
without opening them; every live operation requires an explicit `--port`.
Run `build-examples` from the repository root; it uses the checked-in assembly sources.

| Command | Operation |
| --- | --- |
| `list` | List `/dev/cu.usbmodem*` or `/dev/ttyACM*`; never auto-select |
| `info --port PATH` | Verify firmware identity, get UART configuration; leave disarmed |
| `monitor --port PATH` | Enable RX only, default 5 s; hex/ASCII/Pico timestamp events |
| `send TEXT --port PATH` | Send 1–256 bytes with both explicit safety flags |
| `send --file FILE --port PATH` | Binary-safe send, including NUL; maximum 256 bytes |
| `test --port PATH` | Send 00..FF and compare a returned pattern; needs a loopback/echo target |
| `build-examples [--out-dir DIR]` | Build four Z80 sources to BIN/Intel HEX/N-BASIC DATA |

`--duration-ms N`, `--timeout-ms N`, `--log FILE`, `--raw`, `--normal` are supported.
The default UART is inverted; `--normal` is for explicitly selected Pico-only
comparison tests. USB line coding is 115200 8N1, independent of the PIO's 300 8N1.
Raw mode writes UART bytes only to stdout and statistics to stderr. JSONL logs
contain `pico_us`, `byte`, `flags`; flags 1 = invalid stop bit, 2 = gap/line timeout.
The timestamp is when the firmware drains the PIO FIFO, not a bit-edge timestamp.
Empty RX periods are normal; a continuously active line for 50 ms is a timeout.

TX requires both `--enable-tx --voltage-confirmed`. A 1 s firmware lease is renewed
every 200 ms. SIGINT/SIGTERM trigger best-effort DISARM, DTR drop and termios restore.
SIGKILL cannot run cleanup; DTR and the firmware lease provide bounded revocation.
A hung firmware is reset by its 250 ms watchdog. No claim of instantaneous
revocation under every possible electrical/CPU fault is made.

## Binary framing

All USB traffic is framed, including raw UART payloads. No command text is ever
forwarded to the Z80. Integers are little-endian.

```
5A 38 | version=1 u8 | command u8 | sequence u16 | length u16 | payload | CRC u16
```

Maximum payload 256 bytes, frame 266 bytes. CRC16-CCITT-FALSE (poly 1021h,
initial FFFFh) covers version through payload; `123456789` → 29B1h. Commands:
1 INFO, 2 CONFIG, 3 RX_START, 4 RX_STOP, 5 ARM, 6 DISARM, 7 SEND,
8 STATS, 9 KEEPALIVE, 10 INVERT. Except SEND/ARM/INVERT, payload is empty.
ARM payload is the 16 ASCII bytes `VOLTAGES_CHECKED`; INVERT is one byte 0/1,
accepted only while TX/RX are disabled. Replies use command|80h and the request
sequence, with a status byte followed by data. Status 0 OK, 1 bad command,
2 bad length, 3 disarmed, 4 busy, 5 missing confirmation. No automatic retries
of SEND are made, preventing duplicate target bytes after an uncertain response.
An incomplete frame expires after 500 ms; invalid frames/commands revoke TX.

CONFIG data after status: baud u32, data bits u8, parity u8 (0), stop bits u8,
inverted u8, RX pin u8, TX pin u8, flags u8 (RX bit0/TX bit1), reserved u8,
system clock u32, divider Q8 u32. INFO data is an identity string
`pico2-pc8001/0.1.0`; a mock advertises `pico2-pc8001/mock`.

UART events use command 40h, sequence 0, up to 25 records of
`timestamp_us u64, flags u8, byte u8`. A gap record's byte is not data.
RX and TX software queues are each 512 entries; the PIO hardware queues are
four words per direction. USB CDC RX is 512 bytes, TX 1024 bytes.
USB backpressure retains events until the queue fills; further drops are counted.
Disconnect clears queues and counts lost queued events/aborted TX. Reconnection
never restores RX or TX permission. Counters persist until firmware restart.

STATS data after status is eleven u64 counters in this order:
`rx_bytes`, `tx_completed`, `framing_errors`, `rx_overflows`, `pio_overrun_events`,
`tx_timeouts`, `protocol_errors`, `usb_dropped_events`, `lease_expirations`,
`tx_aborted`, `rx_timeouts`, then TX pending u16 and RX pending u16.
PIO overrun is a sticky-event count/lower bound, not the exact lost byte count.
TX completed means a stop bit finished on the virtual UART, not peer acceptance.
USART PE/OE/FE and target timeout counts are obtained separately from the Z80 report.
The host comparison rate uses host elapsed time; topology is explicitly unverified.
It is not a physical line-rate or PC-8001 success certificate.

For hardware precautions and the next physical steps, see
[PC-8001 serial validation](../../docs/pc8001-serial-validation.md).
There is no Serial Loader, ROM upload, reset, execution or ESP32 transport command.
