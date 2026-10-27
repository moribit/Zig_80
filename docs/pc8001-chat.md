# PC-8001 local LLM chat: work in progress

The repository contains experimental bounded framing, UTF-8-to-ASCII handling,
Ollama newline-delimited JSON decoding, stop-and-wait sender state, and a
160-byte response queue. These are not yet connected to a
serial session, HTTP client, CLI, or Z80 terminal. There is currently no
`zig80 chat` command and no PC-8001 chat binary. Do not deploy experimental
frames or enable Pico TX for these tests.

Ollama's chat endpoint streams newline-delimited JSON. The decoder emits an
event as each complete JSON line arrives, before the final `done` event, and
limits a line to 8192 bytes. It does not itself make an HTTP request, implement
the time-based flush policy, maintain conversation history, or provide
backpressure at the HTTP layer. The text normalizer limits output to 160 characters by default,
converts non-ASCII code points to `?`, and rejects malformed UTF-8.

Before an actual session can be considered safe, the remaining work includes a
PC-8001 terminal and keyboard driver, deploy-to-chat ownership handoff, an
independent USB lease maintenance loop during HTTP waits, bounded streaming
and cancellation, retransmission and synchronization, end-to-end mock tests,
and physical tests. The existing Pico 2 safety settings and deployment path
are unchanged. Hardware streaming and 30-minute stability have not been tested.

A unit integration test sends a mock NDJSON fragment through the decoder,
normalizer, queue, and in-memory sender/receiver before the mock DONE event.
It verifies an ACK-loss retransmission is not applied twice. It does not use
the Z80, virtual USART, Pico mock, HTTP, or an actual PC-8001 screen.

See [experimental frame format](pc8001-chat-protocol.md) and
[existing serial safety guidance](pc8001-serial-validation.md).
