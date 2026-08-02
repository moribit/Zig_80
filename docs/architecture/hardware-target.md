# Future Hardware-target Boundary

[Index](README.md) | [日本語](hardware-target.ja.md)

A future target should implement a versioned Machine contract behind CPU-visible memory and I/O behavior. Emulator devices and Zig firmware may have different internals but must pass shared conformance vectors. Transfer and USB-debug protocols belong outside CPU semantics. Electrical schematics, level compatibility, and measured timing require their own review.

No physical target, firmware, protocol, or PCB is implemented today. See the [Hardware Guide](../guides/hardware-basics.md).

