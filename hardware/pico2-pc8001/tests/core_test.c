#include "../firmware/bridge.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
typedef struct {
  bridge b;
  uint8_t reply[BRIDGE_FRAME_MAX];
  size_t len;
  bool writable, tx, rx;
  unsigned enabled;
} fixture;
static bool emit(void *context, const uint8_t *data, size_t len) {
  fixture *f = context;
  if (!f->writable)
    return false;
  assert(len <= sizeof(f->reply));
  memcpy(f->reply, data, len);
  f->len = len;
  return true;
}
static void safety(void *context, bool tx, bool rx) {
  fixture *f = context;
  f->tx = tx;
  f->rx = rx;
  if (tx)
    f->enabled++;
}
static void init(fixture *f) {
  memset(f, 0, sizeof(*f));
  f->writable = true;
  bridge_init(&f->b, (bridge_io){.context = f,
                                 .emit = emit,
                                 .safety = safety,
                                 .system_hz = 150000000});
  assert(!f->tx && !f->rx);
  bridge_connected(&f->b, true);
}
static uint8_t command(fixture *f, uint8_t cmd, const void *data, size_t len,
                       uint64_t now) {
  uint8_t frame[BRIDGE_FRAME_MAX];
  size_t n = bridge_encode(frame, cmd, 7, data, len);
  assert(n);
  f->len = 0;
  for (size_t i = 0; i < n; i++)
    bridge_feed(&f->b, frame[i], now);
  assert(f->len >= 11 && f->reply[3] == (uint8_t)(cmd | 0x80));
  return f->reply[8];
}
int main(void) {
  fixture f;
  init(&f);
  assert(bridge_crc((const uint8_t *)"123456789", 9) == 0x29b1);
  assert(command(&f, BR_INFO, NULL, 0, 10) == BR_OK && !f.tx);
  assert(command(&f, BR_CONFIG, NULL, 0, 10) == BR_OK && f.len == 31);
  assert(command(&f, BR_SEND, "X", 1, 10) == BR_NOT_ARMED && !f.tx);
  assert(command(&f, BR_ARM, "yes", 3, 10) == BR_CONFIRM_REQUIRED && !f.tx);
  assert(command(&f, BR_RX_START, NULL, 0, 10) == BR_OK && f.rx && !f.tx);
  assert(command(&f, BR_ARM, BRIDGE_CONFIRM, sizeof(BRIDGE_CONFIRM) - 1, 10) ==
             BR_OK &&
         f.tx);
  uint8_t all[256];
  for (unsigned i = 0; i < 256; i++)
    all[i] = (uint8_t)i;
  assert(command(&f, BR_SEND, all, 256, 20) == BR_OK);
  assert(command(&f, BR_SEND, all, 256, 20) == BR_OK && f.b.tx_len == 512);
  assert(command(&f, BR_SEND, all, 1, 20) == BR_BUSY && f.b.tx_len == 512);
  for (unsigned i = 0; i < 512; i++) {
    uint8_t value;
    assert(bridge_tx_pop(&f.b, &value));
    assert(value == (uint8_t)i);
    bridge_tx_complete(&f.b);
  }
  assert(f.b.stats.tx_bytes == 512);
  bridge_tick(&f.b, 1000011);
  assert(!f.tx && f.b.stats.lease_expirations == 1);
  assert(command(&f, BR_KEEPALIVE, NULL, 0, 1000020) == BR_NOT_ARMED);
  assert(command(&f, BR_ARM, BRIDGE_CONFIRM, sizeof(BRIDGE_CONFIRM) - 1,
                 2000000) == BR_OK);
  bridge_uart_timeout(&f.b);
  assert(!f.tx && f.b.stats.tx_timeouts == 1);
  bridge_line_level(&f.b, true, 2000010);
  bridge_line_level(&f.b, true, 2050010);
  assert(f.b.stats.rx_timeouts == 1);
  bridge_line_level(&f.b, true, 2100010);
  assert(f.b.stats.rx_timeouts == 1);
  bridge_line_level(&f.b, false, 2100011);
  bridge_rx(&f.b, 0x55, BR_FRAMING, 2100020);
  assert(f.b.stats.framing_errors == 1);
  f.writable = false;
  for (unsigned i = 0; i < 600; i++)
    bridge_rx(&f.b, (uint8_t)i, 0, 2200000 + i);
  assert(f.b.rx_len == 512 && f.b.stats.rx_overflows > 0 &&
         !bridge_flush_rx(&f.b));
  bridge_connected(&f.b, false);
  assert(!f.tx && !f.rx && f.b.rx_len == 0 &&
         f.b.stats.usb_dropped_events == 512);
  bridge_connected(&f.b, true);
  assert(!f.tx && !f.rx && f.b.tx_len == 0);
  f.writable = true;
  assert(command(&f, BR_INVERT, "\0", 1, 2300000) == BR_OK && !f.b.inverted);
  assert(command(&f, BR_RX_START, NULL, 0, 2300000) == BR_OK);
  assert(command(&f, BR_INVERT, "\1", 1, 2300000) == BR_BUSY);
  assert(command(&f, BR_ARM, BRIDGE_CONFIRM, sizeof(BRIDGE_CONFIRM) - 1,
                 2400000) == BR_OK);
  uint8_t frame[BRIDGE_FRAME_MAX];
  size_t n = bridge_encode(frame, BR_INFO, 1, NULL, 0);
  frame[n - 1] ^= 1;
  for (size_t i = 0; i < n; i++)
    bridge_feed(&f.b, frame[i], 2400010);
  assert(!f.tx && f.b.stats.protocol_errors == 1);
  const uint8_t oversized[] = {0x5a, 0x38, 1, 7, 0, 0, 1, 1};
  for (size_t i = 0; i < sizeof(oversized); i++)
    bridge_feed(&f.b, oversized[i], 2400020);
  assert(f.b.used == 0 && f.b.stats.protocol_errors == 2);
  assert(command(&f, 0x3f, NULL, 0, 2400030) == BR_BAD_COMMAND);
  assert(command(&f, BR_INFO, "x", 1, 2400040) == BR_BAD_LENGTH);
  bridge_feed(&f.b, 0x5a, 2500000);
  bridge_tick(&f.b, 3000001);
  assert(f.b.used == 0);
  puts("C bridge: framing/CRC, limits, all bytes, leases, Hi-Z requests, USB "
       "disconnect/reconnect, overflow, UART timeout passed");
  return 0;
}
