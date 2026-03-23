//! The Interrupt Descriptor Table (IDT) is used to tell the CPU how to handle interrupts e.g. CPU exceptions and hardware interrupts.
//! Without this, CPU exceptions would cause a triple fault which would just be really frustrating. And of course if we want to handle
//! keyboard and mouse input and such, we need the IDT as well. The GDT must be implemented first of course. Note that while it IS somewhat
//! possible to handle keyboard and mouse and such without the IDT by polling those devices instead, interrupts are just far more efficient.

const root = @import("common");
const colors = @import("colors");
const io = @import("io.zig");
const pic = @import("../drivers/pic.zig");

// Aliases
const c = root.c;
const printf = root.printf;

// Structures
const idtr_t = packed struct {
    limit: u16,
    base: u64,
};
const idtEntry_t = packed struct {
    isrLow: u16,
    kernelCS: u16,
    ist: u8,
    attributes: u8,
    isrMid: u16,
    isrHigh: u32,
    reserved: u32,
};

/// CPU exception messages
const cpuExceptionMsg: [32][]const u8 = .{
    "Division by Zero",
    "Debug",
    "Non-Maskable Interrupt",
    "Breakpoint",
    "Overflow",
    "Bound Range Exceeded",
    "Invalid Opcode",
    "Device Not Available",
    "Double Fault",
    "Coprocessor Segment Overrun",
    "Invalid TSS",
    "Segment Not Present",
    "Stack-Segment Fault",
    "General Protection Fault",
    "Page Fault",
    "Reserved",
    "x87 Floating-Point Exception",
    "Alignment Check",
    "Machine Check",
    "SIMD Floating-Point Exception",
    "Virtualization Exception",
    "Control Protection Exception",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Reserved",
    "Hypervisor Injection Exception",
    "VMM Communication Exception",
    "Security Exception",
    "Reserved",
};

// Assembly
extern fn loadIDT(idtr: *const idtr_t) void;

/// This is a table of Interrupt Service Routines (ISRs) which are basically just Assembly functions that the CPU executes
/// depending on what interrupt takes place to handle said interrupt. For example, interrupt 0 would call the very first ISR.
/// Since I'm not really good at Assembly, all ISRs just simply calls an external function instead which actually handles the interrupt.
extern const isrStubTable: [48]usize;

// IDT
var idtr: idtr_t = undefined;
var idt: [48]idtEntry_t align(0x10) = undefined;

// Hardware interrupt handlers
const irqHandler_t = *const fn (irqNum: u8) void;
var handlers: [16]?irqHandler_t = .{null} ** 16;

/// Create and load the IDT so CPU exceptions and hardware interrupts can be handled
pub fn init() void {
    // Initialize IDTR
    idtr.base = @intFromPtr(&idt[0]);
    idtr.limit = @sizeOf(idtEntry_t) * idt.len - 1;

    // Disable the APICs - We'll use the legacy PICs for now since I don't understand ACPI and stuff just yet
    const APIC_BASE_MSR = 0x1B;
    const msr = io.rdmsr(APIC_BASE_MSR);
    io.wrmsr(APIC_BASE_MSR, msr & ~@as(u64, 0x800));

    // Initialize the PICs by remapping them so that they don't cause conflicts with the software interrupts
    // Software interrupts being the CPU exceptions from interrupt 0 to 31
    pic.remap(32, 40);

    // The 32 CPU exceptions and 16 hardware interrupts
    for (0..48) |i|
        setIdtEntry(&idt[i], isrStubTable[i], 0x8E);

    // Load the IDT
    loadIDT(&idtr);
}

// Set an entry in the IDT
fn setIdtEntry(entry: *idtEntry_t, isr: usize, flags: u8) void {
    entry.isrLow = @intCast(isr & 0xFFFF);
    entry.kernelCS = 0x08;
    entry.ist = 0;
    entry.attributes = flags;
    entry.isrMid = @intCast((isr >> 16) & 0xFFFF);
    entry.isrHigh = @intCast((isr >> 32) & 0xFFFFFFFF);
    entry.reserved = 0;
}

/// Register/Deregister a hardware interrupt handler
pub fn irqRegisterHandler(irqNum: comptime_int, handler: irqHandler_t) void {
    if (irqNum >= handlers.len) @compileError("Invalid hardware interrupt number. Must be between 0-16");
    handlers[irqNum] = handler;
    pic.unmaskIrq(irqNum);
}
pub fn irqDeregisterHandler(irqNum: comptime_int) void {
    if (irqNum >= handlers.len) @compileError("Invalid hardware interrupt number. Must be between 0-16");
    handlers[irqNum] = null;
    pic.maskIrq(irqNum);
}

/// Handle interrupts e.g. CPU exceptions
export fn interruptHandler(irqNum: usize, errCode: usize) void {
    // Handle CPU exceptions
    if (irqNum < 32) {
        c.ssfn_dst.fg = colors.ERR_TEXT_COLOR;
        printf("\n[CPU EXCEPTION %d] %s\n", irqNum, cpuExceptionMsg[irqNum].ptr);
        if (errCode != 0) printf("[ERROR CODE] %d\n", errCode);
    }

    // Hardware interrupts
    else if (irqNum < 48) {
        const intNum: u64 = irqNum - 32;
        if (handlers[intNum]) |handler| {
            handler(@intCast(intNum));
            pic.sendEoi(intNum);
            return;
        } else {
            c.ssfn_dst.fg = colors.ERR_TEXT_COLOR;
            printf("\n[HARDWARE INTERRUPT %d] Handler not found\n", intNum);
        }
    }

    // Unknown interrupt
    else printf("\n[INTERRUPT] Invalid interrupt %d", irqNum);

    // Halt CPU indefinitely
    asm volatile ("cli");
    while (true) asm volatile ("hlt");
}
