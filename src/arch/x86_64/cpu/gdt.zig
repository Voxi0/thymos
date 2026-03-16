//! The first thing that an operating system needs to implement is a Global Descriptor Table (GDT)
//! The GDT was previously used to manage memory using segmentation before 64-bit replaced segmentation with paging instead
//! This means that the GDT is largely useless now since paging is used instead anyways but it's still required for backwards
//! compatibility reasons or whatever which is just annoying. And even more annoying that we can't even implement the Interrupt
//! Descriptor Table (IDT) without first implementing the GDT.

// Structures
const gdtr_t = packed struct {
    size: u16,
    offset: u64,
};
const gdtEntry_t = packed struct {
    limitLow: u16,
    baseLow: u16,
    baseMid: u8,
    access: u8,
    granularity: u8,
    baseHigh: u8,
};
const tssEntry_t = packed struct {
    limitLow: u16,
    baseLow: u16,
    baseMid: u8,
    access: u8,
    granularity: u8,
    baseHigh: u8,
    baseUpper: u32,
    reserved: u32,
};

// Assembly
extern fn loadGDT(gdtr: *const gdtr_t) void;

// GDT
var gdtr: gdtr_t = undefined;
var gdt: [5]gdtEntry_t = undefined;

// Create and load the GDT
pub fn init() void {
    // Initialize GDTR
    gdtr.offset = @intFromPtr(&gdt[0]);
    gdtr.size = @sizeOf(gdtEntry_t) * gdt.len - 1;

    // Set GDT entries
    setGdtEntry(&gdt[0], 0, 0);

    // Kernel code and data segment
    setGdtEntry(&gdt[1], 0x9A, 0xA);
    setGdtEntry(&gdt[2], 0x92, 0xC);

    // User code and data segment
    setGdtEntry(&gdt[3], 0xFA, 0x20);
    setGdtEntry(&gdt[4], 0xF2, 0);

    // Load the GDT
    loadGDT(&gdtr);
}

// Set one entry in the GDT
// Long mode ignores base and limit values so we only care about the access byte and flags
fn setGdtEntry(entry: *gdtEntry_t, access: u8, granularity: u8) void {
    entry.granularity = granularity << 4;
    entry.access = access;
}
