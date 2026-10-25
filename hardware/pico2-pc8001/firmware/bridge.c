#include "bridge.h"
#include <string.h>

static void put16(uint8_t *p, uint16_t v) {
  p[0] = (uint8_t)v;
  p[1] = (uint8_t)(v >> 8);
}
static uint16_t get16(const uint8_t *p) {
  return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}
static void put32(uint8_t *p, uint32_t v) {
  for (unsigned i = 0; i < 4; i++)
    p[i] = (uint8_t)(v >> (8 * i));
}
static void put64(uint8_t *p, uint64_t v) {
  for (unsigned i = 0; i < 8; i++)
    p[i] = (uint8_t)(v >> (8 * i));
}

uint16_t bridge_crc(const uint8_t *p, size_t n) {
  uint16_t crc = 0xffff;
  for (size_t i = 0; i < n; i++) {
    crc ^= (uint16_t)p[i] << 8;
    for (unsigned j = 0; j < 8; j++)
      crc = (uint16_t)((crc & 0x8000) ? (crc << 1) ^ 0x1021 : crc << 1);
  }
  return crc;
}
size_t bridge_encode(uint8_t *out, uint8_t type, uint16_t sequence,
                     const uint8_t *data, size_t len) {
  if (len > BRIDGE_PAYLOAD)
    return 0;
  out[0] = 0x5a;
  out[1] = 0x38;
  out[2] = 1;
  out[3] = type;
  put16(out + 4, sequence);
  put16(out + 6, (uint16_t)len);
  if (len)
    memcpy(out + 8, data, len);
  put16(out + 8 + len, bridge_crc(out + 2, 6 + len));
  return len + 10;
}
static void apply_safety(bridge *b) {
  if (b->io.safety)
    b->io.safety(b->io.context, b->tx_armed, b->rx_enabled);
}
void bridge_disarm(bridge *b) {
  b->stats.tx_aborted += b->tx_len + b->tx_inflight;
  b->tx_len = 0;
  b->tx_head = 0;
  b->tx_inflight = 0;
  b->tx_armed = false;
  b->lease_until = 0;
  apply_safety(b);
}
void bridge_init(bridge *b, bridge_io io) {
  memset(b, 0, sizeof(*b));
  b->io = io;
  b->inverted = true;
  apply_safety(b);
}
void bridge_connected(bridge *b, bool connected) {
  if (b->connected == connected)
    return;
  b->connected = connected;
  b->rx_enabled = false;
  b->line_active = false;
  b->line_timeout_reported = false;
  bridge_disarm(b);
  b->stats.usb_dropped_events += b->rx_len;
  b->rx_len = 0;
  b->rx_head = 0;
  b->used = 0;
}
static void reply(bridge *b, uint8_t cmd, uint16_t seq, uint8_t status,
                  const uint8_t *data, size_t len) {
  uint8_t payload[BRIDGE_PAYLOAD], frame[BRIDGE_FRAME_MAX];
  if (len > BRIDGE_PAYLOAD - 1)
    len = BRIDGE_PAYLOAD - 1;
  payload[0] = status;
  if (len)
    memcpy(payload + 1, data, len);
  size_t n = bridge_encode(frame, (uint8_t)(cmd | 0x80), seq, payload, len + 1);
  if (!b->connected || !b->io.emit || !b->io.emit(b->io.context, frame, n))
    bridge_disarm(b);
}
static void command(bridge *b, uint8_t cmd, uint16_t seq, const uint8_t *data,
                    size_t len, uint64_t now) {
  uint8_t result[128];
  size_t result_len = 0;
  uint8_t status = BR_OK;
  if (cmd != BR_ARM && cmd != BR_SEND && cmd != BR_INVERT && len != 0)
    status = BR_BAD_LENGTH;
  else
    switch (cmd) {
    case BR_INFO: {
      const char *id =
          b->io.identity ? b->io.identity : "pico2-pc8001/" BRIDGE_VERSION;
      result_len = strlen(id);
      if (result_len > sizeof(result))
        result_len = sizeof(result);
      memcpy(result, id, result_len);
      break;
    }
    case BR_CONFIG: {
      put32(result, 300);
      result[4] = 8;
      result[5] = 0;
      result[6] = 1;
      result[7] = b->inverted;
      result[8] = 1;
      result[9] = 0;
      result[10] = (uint8_t)(b->rx_enabled | ((unsigned)b->tx_armed << 1));
      result[11] = 0;
      put32(result + 12, b->io.system_hz);
      put32(result + 16,
            (uint32_t)(((uint64_t)b->io.system_hz * 256 + 1200) / 2400));
      result_len = 20;
      break;
    }
    case BR_RX_START:
      b->rx_enabled = true;
      b->line_active = false;
      b->line_timeout_reported = false;
      apply_safety(b);
      break;
    case BR_RX_STOP:
      b->rx_enabled = false;
      b->line_active = false;
      b->line_timeout_reported = false;
      apply_safety(b);
      break;
    case BR_ARM:
      if (len != sizeof(BRIDGE_CONFIRM) - 1 ||
          memcmp(data, BRIDGE_CONFIRM, len))
        status = BR_CONFIRM_REQUIRED;
      else if (!b->connected)
        status = BR_NOT_ARMED;
      else {
        b->tx_armed = true;
        b->lease_until = now + BRIDGE_LEASE_US;
        apply_safety(b);
      }
      break;
    case BR_DISARM:
      bridge_disarm(b);
      break;
    case BR_KEEPALIVE:
      if (!b->tx_armed)
        status = BR_NOT_ARMED;
      else
        b->lease_until = now + BRIDGE_LEASE_US;
      break;
    case BR_INVERT:
      if (len != 1 || data[0] > 1)
        status = BR_BAD_LENGTH;
      else if (b->tx_armed || b->rx_enabled)
        status = BR_BUSY;
      else {
        b->inverted = data[0] != 0;
        if (b->io.configure)
          b->io.configure(b->io.context, b->inverted);
      }
      break;
    case BR_SEND:
      if (!b->tx_armed || !b->connected)
        status = BR_NOT_ARMED;
      else if (!len || len > BRIDGE_PAYLOAD)
        status = BR_BAD_LENGTH;
      else if (len > BRIDGE_QUEUE - b->tx_len)
        status = BR_BUSY;
      else
        for (size_t i = 0; i < len; i++)
          b->tx[(b->tx_head + b->tx_len++) % BRIDGE_QUEUE] = data[i];
      break;
    case BR_STATS: {
      const uint64_t values[] = {
          b->stats.rx_bytes,          b->stats.tx_bytes,
          b->stats.framing_errors,    b->stats.rx_overflows,
          b->stats.pio_overruns,      b->stats.tx_timeouts,
          b->stats.protocol_errors,   b->stats.usb_dropped_events,
          b->stats.lease_expirations, b->stats.tx_aborted,
          b->stats.rx_timeouts};
      for (unsigned i = 0; i < 11; i++)
        put64(result + 8 * i, values[i]);
      put16(result + 88, (uint16_t)(b->tx_len + b->tx_inflight));
      put16(result + 90, b->rx_len);
      result_len = 92;
      break;
    }
    default:
      status = BR_BAD_COMMAND;
      break;
    }
  if (status == BR_BAD_LENGTH || status == BR_BAD_COMMAND ||
      status == BR_CONFIRM_REQUIRED)
    bridge_disarm(b);
  reply(b, cmd, seq, status, result, result_len);
}
void bridge_feed(bridge *b, uint8_t byte, uint64_t now) {
  if (!b->connected)
    return;
  if (b->used && now - b->parser_last_us > 500000) {
    b->used = 0;
    b->stats.protocol_errors++;
    bridge_disarm(b);
  }
  b->parser_last_us = now;
  if (b->used == 0 && byte != 0x5a)
    return;
  if (b->used == 1 && byte != 0x38) {
    b->used = (byte == 0x5a);
    return;
  }
  b->frame[b->used++] = byte;
  if (b->used == 3 && byte != 1) {
    b->used = 0;
    b->stats.protocol_errors++;
    bridge_disarm(b);
    return;
  }
  if (b->used < 8)
    return;
  size_t len = get16(b->frame + 6);
  if (len > BRIDGE_PAYLOAD) {
    b->used = 0;
    b->stats.protocol_errors++;
    bridge_disarm(b);
    return;
  }
  if (b->used == len + 10) {
    b->used = 0;
    if (get16(b->frame + 8 + len) != bridge_crc(b->frame + 2, len + 6)) {
      b->stats.protocol_errors++;
      bridge_disarm(b);
      return;
    }
    command(b, b->frame[3], get16(b->frame + 4), b->frame + 8, len, now);
  }
}
void bridge_tick(bridge *b, uint64_t now) {
  if (b->tx_armed && (!b->connected || now >= b->lease_until)) {
    b->stats.lease_expirations++;
    bridge_disarm(b);
  }
  if (b->used && now - b->parser_last_us > 500000) {
    b->used = 0;
    b->stats.protocol_errors++;
    bridge_disarm(b);
  }
}
bool bridge_tx_pop(bridge *b, uint8_t *value) {
  if (!b->tx_armed || !b->connected || !b->tx_len)
    return false;
  *value = b->tx[b->tx_head];
  b->tx_head = (uint16_t)((b->tx_head + 1) % BRIDGE_QUEUE);
  b->tx_len--;
  b->tx_inflight++;
  return true;
}
void bridge_tx_complete(bridge *b) {
  if (b->tx_inflight) {
    b->tx_inflight--;
    b->stats.tx_bytes++;
  }
}
void bridge_uart_timeout(bridge *b) {
  b->stats.tx_timeouts++;
  bridge_disarm(b);
}
void bridge_rx(bridge *b, uint8_t data, uint8_t flags, uint64_t now) {
  if (!b->rx_enabled)
    return;
  if (!(flags & BR_RX_GAP))
    b->stats.rx_bytes++;
  if (flags & BR_FRAMING)
    b->stats.framing_errors++;
  if (b->rx_len == BRIDGE_QUEUE) {
    b->stats.rx_overflows++;
    return;
  }
  b->rx[(b->rx_head + b->rx_len++) % BRIDGE_QUEUE] =
      (bridge_event){now, flags, data};
}
void bridge_line_level(bridge *b, bool active, uint64_t now) {
  if (!b->rx_enabled || !active) {
    b->line_active = false;
    b->line_timeout_reported = false;
    return;
  }
  if (!b->line_active) {
    b->line_active = true;
    b->active_since = now;
  }
  if (!b->line_timeout_reported && now - b->active_since >= 50000) {
    b->line_timeout_reported = true;
    b->stats.rx_timeouts++;
    bridge_rx(b, 0, BR_RX_GAP, now);
  }
}
bool bridge_flush_rx(bridge *b) {
  if (!b->connected || !b->rx_len)
    return false;
  uint8_t payload[250], frame[BRIDGE_FRAME_MAX];
  unsigned count = b->rx_len > 25 ? 25 : b->rx_len;
  for (unsigned i = 0; i < count; i++) {
    bridge_event event = b->rx[(b->rx_head + i) % BRIDGE_QUEUE];
    put64(payload + i * 10, event.timestamp_us);
    payload[i * 10 + 8] = event.flags;
    payload[i * 10 + 9] = event.data;
  }
  size_t n = bridge_encode(frame, BR_EVENT, 0, payload, count * 10);
  if (!b->io.emit || !b->io.emit(b->io.context, frame, n))
    return false;
  b->rx_head = (uint16_t)((b->rx_head + count) % BRIDGE_QUEUE);
  b->rx_len = (uint16_t)(b->rx_len - count);
  return true;
}
