const instruction = @import("instruction.zig");
pub fn fixedDefinition(opcode: u8) ?instruction.Definition {
    for (instruction.fixed) |definition| if (definition.opcode == opcode) return definition;
    return null;
}
