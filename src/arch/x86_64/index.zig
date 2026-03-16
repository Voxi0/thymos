const gdt = @import("cpu/gdt.zig");
const idt = @import("cpu/idt.zig");
pub const io = @import("cpu/io.zig");

/// Register/Deregister a hardware interrupt handler
pub const irqRegisterHandler = idt.irqRegisterHandler;
pub const irqDeregisterHandler = idt.irqDeregisterHandler;

/// Initialize the CPU
pub inline fn initCPU() void {
    asm volatile ("cli");
    gdt.init();
    idt.init();
    asm volatile ("sti");
}

/// Halts the CPU indefinitely after stopping all interrupts
pub inline fn halt() noreturn {
    asm volatile ("cli");
    while (true) asm volatile ("hlt");
}

/// Halts the CPU until something has to be done e.g. handling an interrupt
pub inline fn idleHalt() noreturn {
    asm volatile ("sti");
    while (true) asm volatile ("hlt");
}
