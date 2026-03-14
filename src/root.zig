//! This module imports a bunch of modules that are commonly used along with constants.

pub const c = @cImport({
    @cInclude("limine/limine.h");
    @cInclude("ssfn.h");
});

pub const std = @import("std");
pub const arch = @import("arch/arch.zig").arch;
const colors = @import("colors.zig");

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

// Link with all the functions that the tiny printf implementation offers
// I'm setting the return type to `void` so I don't have to manually ignore them every single time I use any of these functions
pub extern fn printf(fmt: [*:0]const u8, ...) void;
pub extern fn sprintf(buf: [*]u8, fmt: [*:0]const u8, ...) void;
pub extern fn snprintf(buf: [*]u8, count: usize, fmt: [*:0]const u8, ...) void;
pub extern fn vprintf(fmt: [*:0]const u8, va: @import("std").builtin.VaList) void;
pub extern fn vsnprintf(buf: [*]u8, count: usize, fmt: [*:0]const u8, va: @import("std").builtin.VaList) void;

// Limine base revision
pub export var limineBaseRev linksection(".limine_requests") = [3]u64{
    0xf9562b2d5c95a6c8, 0x6a7b384944536bdc, 5,
};

// Limine requests markers
export var requestsStartMarker linksection(".limine_requests_start") = [4]u64{
    0xf6b8f4b39de7d1ae, 0xfab91a6940fcb9cf,
    0x785c6ed015d3e316, 0x181e920a7852b9d9,
};
export var requestsEndMarker linksection(".limine_requests_end") = [2]u64{
    0xadc0e0531bb10d03, 0x9572709f31764c62,
};

// Limine constants
pub const LIMINE_COMMON_MAGIC = [2]u64{ 0xc7b1dd30df4c8b88, 0x0a82e883a194f07b };
pub const LIMINE_FRAMEBUFFER_REQUEST_ID = [4]u64{
    LIMINE_COMMON_MAGIC[0],
    LIMINE_COMMON_MAGIC[1],
    0x9d5827dcd881dd75,
    0xa3148604f6fab11b,
};
