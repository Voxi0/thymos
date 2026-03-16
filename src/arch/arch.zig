// Import architecture specific stuff depending on build target
const builtin = @import("builtin");
const arch = switch (builtin.cpu.arch) {
    .x86_64 => @import("x86_64/index.zig"),
    else => @compileError("Unsupported target architecture"),
};

// Export architecture specific functions
pub const initCPU = arch.initCPU;
pub const io = arch.io;
pub const irqRegisterHandler = arch.irqRegisterHandler;
pub const irqDeregisterHandler = arch.irqDeregisterHandler;
pub const halt = arch.halt;
pub const idleHalt = arch.idleHalt;
