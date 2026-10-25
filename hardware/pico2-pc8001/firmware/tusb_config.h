#ifndef ZIG80_TUSB_CONFIG_H
#define ZIG80_TUSB_CONFIG_H
#define CFG_TUSB_MCU                                                           \
  OPT_MCU_RP2040 /* Pico SDK TinyUSB port also supports RP2350. */
#define CFG_TUSB_OS OPT_OS_PICO
#define CFG_TUSB_RHPORT0_MODE (OPT_MODE_DEVICE | OPT_MODE_FULL_SPEED)
#define CFG_TUD_ENDPOINT0_SIZE 64
#define CFG_TUD_CDC 1
#define CFG_TUD_CDC_RX_BUFSIZE 512
#define CFG_TUD_CDC_TX_BUFSIZE 1024
#define CFG_TUD_CDC_EP_BUFSIZE 64
#endif
