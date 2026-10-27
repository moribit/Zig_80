# PC-8001 chat protocol: experimental building blocks

This document describes a proposed frame codec, not an operational chat
protocol. Neither a PC-8001 chat application nor a host chat bridge is yet
connected to this codec. Do not send these frames to the resident deploy loader.

Frames are `A5 5A TYPE SEQ LEN PAYLOAD CRC_LO CRC_HI`. The payload is at most
32 bytes. CRC-16/CCITT-FALSE (polynomial 1021, initial value FFFF, no final
XOR) covers TYPE through PAYLOAD; `123456789` has CRC 29B1. Payload bytes may
include the sync bytes: LEN controls framing. A partial frame must be reset by
the caller after an inter-byte timeout. An invalid length or CRC drops the
frame; the next bytes are searched for the sync pair. A sender must retransmit
the complete frame after a missing acknowledgement. The sender state tracks a
configurable retry count; transport deadlines and UART integration are not
implemented yet.

Types 1 through 8 designate HELLO, READY, PROMPT, TEXT, DONE, ERROR, ACK and
CANCEL respectively. The receiver accepts only its expected sequence, repeats
the acknowledgement for an identical previous frame, and rejects both an
out-of-order frame and a changed frame bearing the previous sequence number.
Sequence wraps modulo 256. An ACK has an empty payload and its sequence equals
the acknowledged frame. ACKs are not acknowledged. Session start, cancellation,
and sequence reset rules still need an interoperable implementation and tests.
