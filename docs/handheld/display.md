# Abstract VFD / 抽象VFD

Logical framebuffer: 256×64, 1bpp, 2,048 bytes. Page byte index=(y/8)×256+x,
bit=y%8 (top pixel is LSB). Pixel read/write, clear, changed-pixel bounding region,
byte-level conservative dirty regions and immutable byte-array snapshot are
available in `display.Framebuffer`. Identical writes do not dirty or increment
updates. Out-of-bounds pixel reads are false; writes are ignored.

Controller address is 11 bits and wraps 2047→0 on data access. Low/high address
ports precede data reads/writes; clear zeros the framebuffer and address. Controller
and layout are virtual conventions, not inferred Noritake commands. Brightness,
phosphor persistence, busy timing and hardware interface are not implemented.

TUI reuses the existing Display pane, scales, grid, cursor, dirty highlighting and
viewport for 128- or 256-wide output. Handheld cursor shows a VRAM offset rather
than a CPU memory address. `--export-frame FILE` produces portable text PBM;
`--snapshot FILE` stores page bytes plus dimensions/layout. No graphics library.

日本語: 論理Framebuffer、Controller、Port接続、TUI描画を分離しています。画面は2048byteで、
Classicの1024byte画面と共存します。実機型番に依存する命令・輝度・残光は実装していません。
SnapshotはByte値の配列、PBMは行順のPixel値で出力します。
