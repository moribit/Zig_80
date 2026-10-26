#include "bridge.h"
#include "hardware/clocks.h"
#include "hardware/pio.h"
#include "hardware/watchdog.h"
#include "hardware/structs/watchdog.h"
#include "pico/stdlib.h"
#include "tusb.h"
#include "uart.pio.h"

#define TX_PIN 0u
#define RX_PIN 1u
#define RX_SM 0u
#define TX_SM 1u
static bridge device;
static PIO uart_pio = pio0;
static bool tx_on, rx_on, configured;
static const pio_program_t *rx_program, *tx_program;
static uint rx_offset, tx_offset;
static uint64_t last_completion;
// SDK boot-vector/timeout markers use scratch[4..7]. Our scratch[0] records
// the last main-loop phase across a watchdog reset, without changing policy.
#define PHASE_MAGIC 0x5a380100u
static inline void phase(uint32_t value) {
  watchdog_hw->scratch[0] = PHASE_MAGIC | value;
}

static void hi_z(uint pin) {
  gpio_set_oeover(pin, GPIO_OVERRIDE_LOW);
  gpio_set_function(pin, GPIO_FUNC_NULL);
  gpio_set_oeover(pin, GPIO_OVERRIDE_LOW);
  gpio_disable_pulls(pin);
  gpio_set_input_enabled(pin, false); // Also avoid RP2350 A2 E9 input leakage.
}
static pio_sm_config rx_config, tx_config;
static void safety_configured(void *unused, bool tx, bool rx) {
  (void)unused;
  if (!tx) {
    hi_z(TX_PIN); // Revoke pad output before stopping/clearing PIO.
    pio_sm_set_enabled(uart_pio, TX_SM, false);
    pio_sm_clear_fifos(uart_pio, TX_SM);
    tx_on = false;
  }
  if (!rx) {
    pio_sm_set_enabled(uart_pio, RX_SM, false);
    pio_sm_clear_fifos(uart_pio, RX_SM);
    hi_z(RX_PIN);
    rx_on = false;
  }
  // The portable core is the only code that can request an enabled output.
  if (tx && !tx_on) {
    pio_sm_init(uart_pio, TX_SM, tx_offset, &tx_config);
    pio_sm_set_pins_with_mask(uart_pio, TX_SM, device.inverted ? 0u : 1u,
                              1u << TX_PIN);
    pio_gpio_init(uart_pio, TX_PIN);
    gpio_disable_pulls(TX_PIN);
    gpio_set_input_enabled(TX_PIN, false);
    pio_sm_set_consecutive_pindirs(uart_pio, TX_SM, TX_PIN, 1, true);
    gpio_set_oeover(TX_PIN, GPIO_OVERRIDE_NORMAL);
    tx_on = true;
    last_completion = time_us_64();
    pio_sm_set_enabled(uart_pio, TX_SM, true);
  }
  if (rx && !rx_on) {
    pio_sm_init(uart_pio, RX_SM, rx_offset, &rx_config);
    pio_sm_set_consecutive_pindirs(uart_pio, RX_SM, RX_PIN, 1, false);
    pio_gpio_init(uart_pio, RX_PIN);
    gpio_disable_pulls(RX_PIN);
    gpio_set_input_enabled(RX_PIN, true);
    gpio_set_oeover(RX_PIN, GPIO_OVERRIDE_LOW);
    rx_on = true;
    pio_sm_set_enabled(uart_pio, RX_SM, true);
  }
}
static void configure(void *unused, bool inverted) {
  (void)unused;
  safety_configured(NULL, false, false);
  if (configured) {
    pio_remove_program(uart_pio, rx_program, rx_offset);
    pio_remove_program(uart_pio, tx_program, tx_offset);
  }
  rx_program = inverted ? &s10_rx_inverted_program : &s10_rx_normal_program;
  tx_program = inverted ? &s10_tx_inverted_program : &s10_tx_normal_program;
  rx_offset = pio_add_program(uart_pio, rx_program);
  tx_offset = pio_add_program(uart_pio, tx_program);
  rx_config = inverted ? s10_rx_inverted_program_get_default_config(rx_offset)
                       : s10_rx_normal_program_get_default_config(rx_offset);
  tx_config = inverted ? s10_tx_inverted_program_get_default_config(tx_offset)
                       : s10_tx_normal_program_get_default_config(tx_offset);
  const uint32_t hz = clock_get_hz(clk_sys);
  const uint32_t divisor = (uint32_t)(((uint64_t)hz * 256 + 1200) / 2400);
  hard_assert(divisor >= 256 && divisor <= 0xffffff);
  sm_config_set_clkdiv_int_frac(&rx_config, (uint16_t)(divisor >> 8),
                                (uint8_t)divisor);
  sm_config_set_clkdiv_int_frac(&tx_config, (uint16_t)(divisor >> 8),
                                (uint8_t)divisor);
  sm_config_set_in_pins(&rx_config, RX_PIN);
  sm_config_set_jmp_pin(&rx_config, RX_PIN);
  sm_config_set_in_shift(&rx_config, true, false, 32);
  sm_config_set_out_pins(&tx_config, TX_PIN, 1);
  sm_config_set_sideset_pins(&tx_config, TX_PIN);
  sm_config_set_out_shift(&tx_config, true, false, 32);
  pio_sm_init(uart_pio, RX_SM, rx_offset, &rx_config);
  pio_sm_init(uart_pio, TX_SM, tx_offset, &tx_config);
  configured = true;
}
static bool usb_emit(void *unused, const uint8_t *data, size_t len) {
  (void)unused;
  if (!tud_cdc_connected() || tud_cdc_write_available() < len)
    return false;
  return tud_cdc_write(data, (uint32_t)len) == len;
}
void tud_cdc_line_state_cb(uint8_t instance, bool dtr, bool rts) {
  (void)instance;
  (void)rts;
  bridge_connected(&device, dtr && tud_mounted());
}
void tud_umount_cb(void) { bridge_connected(&device, false); }
void tud_suspend_cb(bool remote_wakeup) {
  (void)remote_wakeup;
  bridge_connected(&device, false);
}

int main(void) {
  hi_z(TX_PIN);
  hi_z(RX_PIN);
  pio_sm_claim(uart_pio, RX_SM);
  pio_sm_claim(uart_pio, TX_SM);
  configure(NULL, true);
  bridge_init(&device, (bridge_io){.emit = usb_emit,
                                   .safety = safety_configured,
                                   .configure = configure,
                                   .identity = "pico2-pc8001/" BRIDGE_VERSION,
                                   .system_hz = clock_get_hz(clk_sys)});
  device.boot_watchdog = watchdog_caused_reboot();
  device.boot_watchdog_timeout = watchdog_enable_caused_reboot();
  uint32_t previous_phase = watchdog_hw->scratch[0];
  if (device.boot_watchdog && (previous_phase & 0xffffff00u) == PHASE_MAGIC)
    device.boot_phase = previous_phase & 0xffu;
  phase(0);
  watchdog_enable(250, false);
  tusb_init();
  uint64_t previous_loop = time_us_64();
  for (;;) {
    uint64_t current_loop = time_us_64();
    uint64_t elapsed_loop = current_loop - previous_loop;
    if (elapsed_loop > device.max_loop_us)
      device.max_loop_us = elapsed_loop;
    previous_loop = current_loop;
    device.loop_count++;
    watchdog_update();
    phase(1);
    tud_task();
    phase(2);
    bridge_connected(&device, tud_cdc_connected());
    uint64_t now = time_us_64();
    bridge_tick(&device, now);
    unsigned budget = 512;
    phase(3);
    while (tud_cdc_available() && budget--) {
      uint8_t byte;
      if (tud_cdc_read(&byte, 1) == 1)
        bridge_feed(&device, byte, now);
    }
    phase(4);
    if (rx_on) {
      const uint32_t overrun = 1u << (PIO_FDEBUG_RXSTALL_LSB + RX_SM);
      if (uart_pio->fdebug & overrun) {
        uart_pio->fdebug = overrun;
        device.stats.pio_overruns++;
        bridge_rx(&device, 0, BR_RX_GAP, now);
      }
      while (!pio_sm_is_rx_fifo_empty(uart_pio, RX_SM)) {
        uint32_t sample = pio_sm_get(uart_pio, RX_SM);
        bridge_rx(&device, (uint8_t)(sample >> 23),
                  (sample & 0x80000000u) ? 0 : BR_FRAMING, now);
      }
      bool active = gpio_get(RX_PIN) == device.inverted;
      bridge_line_level(&device, active, now);
    }
    phase(5);
    if (tx_on) {
      while (!pio_sm_is_rx_fifo_empty(uart_pio, TX_SM)) {
        (void)pio_sm_get(uart_pio, TX_SM);
        bridge_tx_complete(&device);
        last_completion = now;
      }
      uint8_t value;
      while (!pio_sm_is_tx_fifo_full(uart_pio, TX_SM) &&
             bridge_tx_pop(&device, &value)) {
        if (device.tx_inflight == 1)
          last_completion = now;
        pio_sm_put(uart_pio, TX_SM, value);
      }
      if (device.tx_inflight && now - last_completion > 250000)
        bridge_uart_timeout(&device);
    }
    phase(6);
    (void)bridge_flush_rx(&device);
    tud_cdc_write_flush();
    phase(7);
    // Physical 0.1.2 repro: watchdog timeout with the retained phase == 7.
    // Do not enter the SDK alarm/WFE sleep path in this short safety loop.
    // IRQs remain enabled; the timer bounds the wait without a wakeup alarm.
    busy_wait_us_32(50);
  }
}
