#ifndef ZIG80_BRIDGE_H
#define ZIG80_BRIDGE_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define BRIDGE_VERSION "0.1.3"
#define BRIDGE_PAYLOAD 256u
#define BRIDGE_FRAME_MAX 266u
#define BRIDGE_QUEUE 512u
#define BRIDGE_LEASE_US 1000000ull
#define BRIDGE_CONFIRM "VOLTAGES_CHECKED"
enum bridge_command {
  BR_INFO = 1,
  BR_CONFIG = 2,
  BR_RX_START = 3,
  BR_RX_STOP = 4,
  BR_ARM = 5,
  BR_DISARM = 6,
  BR_SEND = 7,
  BR_STATS = 8,
  BR_KEEPALIVE = 9,
  BR_INVERT = 10,
  BR_HEALTH = 11
};
enum bridge_status {
  BR_OK = 0,
  BR_BAD_COMMAND = 1,
  BR_BAD_LENGTH = 2,
  BR_NOT_ARMED = 3,
  BR_BUSY = 4,
  BR_CONFIRM_REQUIRED = 5
};
enum { BR_EVENT = 0x40, BR_FRAMING = 1, BR_RX_GAP = 2 };
typedef struct {
  uint64_t timestamp_us;
  uint8_t flags, data;
} bridge_event;
typedef struct {
  uint64_t rx_bytes, tx_bytes, framing_errors, rx_overflows, pio_overruns,
      tx_timeouts, protocol_errors, usb_dropped_events, lease_expirations,
      tx_aborted, rx_timeouts;
} bridge_stats;
typedef struct {
  void *context;
  bool (*emit)(void *, const uint8_t *, size_t);
  void (*safety)(void *, bool, bool); /* tx allowed, rx enabled */
  void (*configure)(void *, bool);
  const char *identity;
  uint32_t system_hz;
} bridge_io;
typedef struct {
  bridge_io io;
  bool connected, rx_enabled, tx_armed, inverted;
  uint64_t lease_until, parser_last_us;
  uint8_t frame[BRIDGE_FRAME_MAX];
  size_t used;
  uint8_t tx[BRIDGE_QUEUE];
  uint16_t tx_head, tx_len;
  bridge_event rx[BRIDGE_QUEUE];
  uint16_t rx_head, rx_len, tx_inflight;
  bridge_stats stats;
  /* Diagnostic observations only; never alter the lease or GPIO policy. */
  bool boot_watchdog, boot_watchdog_timeout;
  uint32_t boot_phase;
  uint64_t loop_count, max_loop_us;
  bool line_active, line_timeout_reported;
  uint64_t active_since;
} bridge;
uint16_t bridge_crc(const uint8_t *, size_t);
size_t bridge_encode(uint8_t *, uint8_t, uint16_t, const uint8_t *, size_t);
void bridge_init(bridge *, bridge_io);
void bridge_connected(bridge *, bool);
void bridge_feed(bridge *, uint8_t, uint64_t);
void bridge_tick(bridge *, uint64_t);
void bridge_disarm(bridge *);
bool bridge_tx_pop(bridge *, uint8_t *);
void bridge_tx_complete(bridge *);
void bridge_rx(bridge *, uint8_t, uint8_t, uint64_t);
bool bridge_flush_rx(bridge *);
void bridge_uart_timeout(bridge *);
void bridge_line_level(bridge *, bool, uint64_t);
#endif
