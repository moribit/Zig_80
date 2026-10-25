/// Frontends may feed elapsed wall-clock durations; headless execution instead
/// supplies instruction/T-state budgets directly. CPU/devices never read a clock.
pub const Pacer = struct {
    remainder: u64 = 0,
    pub fn budget(self: *Pacer, elapsed_ns: u64, clock_hz: u32) u64 {
        const scaled = @as(u128, elapsed_ns) * clock_hz + self.remainder;
        self.remainder = @intCast(scaled % 1_000_000_000);
        return @intCast(scaled / 1_000_000_000);
    }
};
