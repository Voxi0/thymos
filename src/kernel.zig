const root = @import("common");
const arch = @import("arch");
const colors = @import("colors");

// Drivers
const video = @import("drivers/video.zig");

// Aliases
const std = root.std;
const c = root.c;
const printf = root.printf;

/// The kernel's entry point.
export fn _start() callconv(.c) noreturn {
    // Ensure Limine base revision is supported
    if (!c.LIMINE_BASE_REVISION_SUPPORTED(root.limineBaseRev)) arch.halt();

    // Initialize the video driver
    video.init(colors.BG_COLOR, colors.TEXT_COLOR);
    video.clearScreen() catch |e| video.handleErr(e);

    // Initialize architecture specific stuff
    arch.initCPU();

    printf("Alright, we're ready\n");
    asm volatile ("sti");
    arch.irqRegisterHandler(1, &testHandler);

    // Halt CPU indefinitely
    arch.idleHalt();
}

const scancodeTable = [_]u8{
    0, 0, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\x08', // backspace
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[',  ']', '\n', // enter
    0,    'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0,
    '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0,    '*', 0,
    ' ',
};
fn testHandler(_: u8) void {
    const scancode: u8 = arch.io.inb(0x60);
    if (scancode < scancodeTable.len and scancodeTable[scancode] != 0) {
        printf("%c", scancodeTable[scancode]);
    }
}

// Panic handler
pub const panic = std.debug.FullPanic(panicHandler);
fn panicHandler(msg: []const u8, firstTraceAddr: ?usize) noreturn {
    _ = firstTraceAddr;

    // Display error message
    c.ssfn_dst.fg = colors.ERR_TEXT_COLOR;
    printf("\n[PANIC] %s", msg.ptr);

    // Halt CPU indefinitely
    arch.halt();
}
