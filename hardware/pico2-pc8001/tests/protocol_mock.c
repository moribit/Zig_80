/* Host-only mock runs the exact portable firmware protocol core. No GPIO code.
 */
#include "../firmware/bridge.h"
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/select.h>
#include <time.h>
#include <unistd.h>
static volatile sig_atomic_t running = 1;
static void stop(int sig) {
  (void)sig;
  running = 0;
}
static uint64_t now_us(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (uint64_t)t.tv_sec * 1000000 + (uint64_t)t.tv_nsec / 1000;
}
static bool emit(void *unused, const uint8_t *data, size_t len) {
  (void)unused;
  while (len) {
    ssize_t n = write(STDOUT_FILENO, data, len);
    if (n < 0) {
      if (errno == EINTR)
        continue;
      return false;
    }
    data += n;
    len -= (size_t)n;
  }
  return true;
}
static void safety(void *unused, bool tx, bool rx) {
  (void)unused;
  const char *path = getenv("MOCK_STATE_LOG");
  if (!path)
    return;
  FILE *f = fopen(path, "a");
  if (f) {
    fprintf(f, "tx=%u rx=%u\n", tx, rx);
    fclose(f);
  }
}
int main(void) {
  signal(SIGTERM, stop);
  signal(SIGINT, stop);
  bridge b;
  bridge_init(&b, (bridge_io){.emit = emit,
                              .safety = safety,
                              .system_hz = 150000000,
                              .identity = "pico2-pc8001/mock"});
  bridge_connected(&b, true);
  while (running) {
    fd_set set;
    FD_ZERO(&set);
    FD_SET(STDIN_FILENO, &set);
    struct timeval timeout = {0, 10000};
    int ready = select(STDIN_FILENO + 1, &set, NULL, NULL, &timeout);
    if (ready < 0) {
      if (errno == EINTR)
        continue;
      break;
    }
    uint64_t now = now_us();
    if (ready) {
      uint8_t bytes[512];
      ssize_t n = read(STDIN_FILENO, bytes, sizeof(bytes));
      if (n <= 0)
        break;
      for (ssize_t i = 0; i < n; i++)
        bridge_feed(&b, bytes[i], now);
    }
    bridge_tick(&b, now);
    if (!getenv("MOCK_STALL_TX")) {
      uint8_t value;
      while (bridge_tx_pop(&b, &value)) {
        bridge_rx(&b, value, 0, now);
        bridge_tx_complete(&b);
      }
    }
    (void)bridge_flush_rx(&b);
  }
  bridge_connected(&b, false);
  return 0;
}
