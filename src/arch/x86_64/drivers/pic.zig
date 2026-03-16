//! This is the driver for the legacy 8259 PIC (Programmable Interrupt Controller) chip for handling hardware interrupts.
//! APIC (Advanced Programmable Interrupt Controller) is modern and absolutely preferable but that is more complicated
//! to use compared to the PIC so sticking with the 8259 PIC for the time being is an easier way to go.

const io = @import("../cpu/io.zig");

// Ports
const PIC1_COMMAND: u8 = 0x20;
const PIC1_DATA: u8 = PIC1_COMMAND + 1;
const PIC2_COMMAND: u8 = 0xA0;
const PIC2_DATA: u8 = PIC2_COMMAND + 1;

// Commands
const PIC_EOI: u8 = 0x20;
const CASCADE_IRQ: u8 = 2;
const PIC_READ_IRR: u8 = 0x0A;
const PIC_READ_ISR: u8 = 0x0B;

// Initialization command words
const ICW1_ICW4: u8 = 0x01;
const ICW1_SINGLE: u8 = 0x02;
const ICW1_INTERVAL4: u8 = 0x04;
const ICW1_LEVEL: u8 = 0x08;
const ICW1_INIT: u8 = 0x10;

const ICW4_8086: u8 = 0x01;
const ICW4_AUTO: u8 = 0x02;
const ICW4_BUF_SLAVE: u8 = 0x08;
const ICW4_BUF_MASTER: u8 = 0x0C;
const ICW4_SFNM: u8 = 0x10;

/// Initialize the PICs by remapping them so they don't conflict with software interrupts
pub fn remap(offset1: comptime_int, offset2: comptime_int) void {
    // Start initialization sequence in cascade mode
    io.outb(PIC1_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.wait();
    io.outb(PIC2_COMMAND, ICW1_INIT | ICW1_ICW4);
    io.wait();

    // ICW2 - Set vector offets
    io.outb(PIC1_DATA, offset1);
    io.wait();
    io.outb(PIC2_DATA, offset2);
    io.wait();

    // ICW3 - Tell master PIC that there's a slave PIC at IRQ2 and tell slave PIC it's cascade identity
    io.outb(PIC1_DATA, 0x4);
    io.wait();
    io.outb(PIC2_DATA, 0x2);
    io.wait();

    // ICW4 - Make the PICs use 8086 mode instead of 8080
    io.outb(PIC1_DATA, ICW4_8086);
    io.wait();
    io.outb(PIC2_DATA, ICW4_8086);
    io.wait();

    // Mask all interrupts initially
    io.outb(PIC1_DATA, 0xFF);
    io.outb(PIC2_DATA, 0xFF);
}

/// Mask/Unmask a hardware interrupt
/// This allows us to control which hardware interrupts to ignore and which ones to not ignore
pub fn maskIrq(irq: comptime_int) void {
    const port: u16 = if (irq < 8) PIC1_DATA else PIC2_DATA;
    const value: u8 = if (irq < 8) irq else irq - 8;
    io.outb(port, io.inb(port) | (@as(u8, 1) << @intCast(value)));
}
pub fn unmaskIrq(irq: comptime_int) void {
    const port: u16 = if (irq < 8) PIC1_DATA else PIC2_DATA;
    const value: u8 = if (irq < 8) irq else irq - 8;
    io.outb(port, io.inb(port) & ~(@as(u8, 1) << @intCast(value)));
}

// Helper function
fn getIrqReg(ocw3: u32) u16 {
    io.outb(PIC1_COMMAND, @intCast(ocw3));
    io.outb(PIC2_COMMAND, @intCast(ocw3));
    return (@as(u16, io.inb(PIC2_DATA)) << 8) | @as(u16, io.inb(PIC1_DATA));
}

/// Read the Interrupt Request Register (IRR)
pub fn getIrr() u16 {
    return getIrqReg(PIC_READ_IRR);
}

/// Read the In-Service Register (ISR)
pub fn getIsr() u16 {
    return getIrqReg(PIC_READ_ISR);
}

/// Tell the PICs that the hardware interrupt has been handled
pub fn sendEoi(irq: u64) void {
    if (irq >= 8) io.outb(PIC2_COMMAND, PIC_EOI);
    io.outb(PIC1_COMMAND, PIC_EOI);
}

/// Disable the PICs - Must be done before using the processor local APIC and the IOAPIC
pub fn disable() void {
    io.outb(PIC1_DATA, 0xFF);
    io.outb(PIC2_DATA, 0xFF);
}
