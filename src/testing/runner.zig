const Machine = @import("../machine/machine.zig").Machine;
pub fn runUntilHalt(machine: *Machine, max_instructions: usize) !usize {
    var count: usize = 0;
    while (!machine.cpu.halted and count < max_instructions) : (count += 1) _ = try machine.step();
    if (!machine.cpu.halted) return error.InstructionLimitReached;
    return count;
}
