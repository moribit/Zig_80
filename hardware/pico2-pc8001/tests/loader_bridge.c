/* Native integration adapter, no GPIO. Keep the real bridge state private to C.
 * The small extern interface works on Zig 0.17 without the removed @cImport. */
#include "bridge.h"
extern bool loader_mock_emit(const uint8_t *, size_t);
extern void loader_mock_safety(bool);
static bridge core;
static bool emit(void *context, const uint8_t *bytes, size_t len) {
  (void)context;
  return loader_mock_emit(bytes, len);
}
static void safety(void *context, bool tx, bool rx) {
  (void)context;
  (void)rx;
  loader_mock_safety(tx);
}
void loader_bridge_init(void) {
  bridge_init(&core, (bridge_io){.emit = emit,
                                 .safety = safety,
                                 .identity = "pico2-pc8001/mock-z80",
                                 .system_hz = 150000000});
}
void loader_bridge_connected(bool value) { bridge_connected(&core, value); }
void loader_bridge_feed(uint8_t byte, uint64_t now) {
  bridge_feed(&core, byte, now);
}
void loader_bridge_tick(uint64_t now) { bridge_tick(&core, now); }
bool loader_bridge_pop(uint8_t *value) { return bridge_tx_pop(&core, value); }
void loader_bridge_complete(void) { bridge_tx_complete(&core); }
void loader_bridge_rx(uint8_t byte, uint64_t now) {
  bridge_rx(&core, byte, 0, now);
}
void loader_bridge_fault(uint8_t byte, uint64_t now) {
  bridge_rx(&core, byte, BR_FRAMING, now);
}
void loader_bridge_flush(void) { (void)bridge_flush_rx(&core); }
