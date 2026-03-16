//! This is a basic framebuffer driver that allows us to draw some primitive shapes and text on the screen
//! Until a proper GPU driver is loaded, the framebuffer is all there is for rendering anything.

const root = @import("common");
const arch = @import("arch");
const colors = @import("colors");
const c = root.c;
const printf = root.printf;

// Request a linear framebuffer
export var fbRequest: c.limine_framebuffer_request linksection(".limine_requests") = .{
    .id = root.LIMINE_FRAMEBUFFER_REQUEST_ID,
    .revision = 0,
};

// Errors
pub const VideoError = error{
    OutOfBounds,
};

// Framebuffer
pub var fb: *c.limine_framebuffer = undefined;
var pixelsPerRow: usize = 0;
pub var fbWidth: usize = 0;
pub var fbHeight: usize = 0;

// Font
const FONT = @embedFile("../fonts/unifont.sfn");
pub const FONT_WIDTH: u8 = 8;
pub const FONT_HEIGHT: u8 = 16;

// Cursor
const CURSOR_WIDTH: u8 = 1;
var cursorLastX: c_int = 0;
var cursorLastY: c_int = 0;

/// Initialize the framebuffer by fetching the first one available. If there are none available then the OS is halted indefinitely.
/// This function also initializes SSFN which is a library for rendering text on the screen. It uses `.sfn` font files.
pub fn init(bgColor: u32, fgColor: u32) void {
    // Fetch the first available framebuffer
    const fbResponse: *c.limine_framebuffer_response = @ptrCast(fbRequest.response orelse arch.halt());
    fb = @ptrCast(fbResponse.framebuffers[0]);
    pixelsPerRow = fb.pitch / (fb.bpp / 8);
    fbWidth = @intCast(fb.width - 1);
    fbHeight = @intCast(fb.height - 1);

    // Initialize SSFN - Text renderer
    c.ssfn_src = @ptrCast(@constCast(FONT));
    c.ssfn_dst.ptr = @ptrCast(fb.address);
    c.ssfn_dst.w = @intCast(fb.width);
    c.ssfn_dst.h = @intCast(fb.height);
    c.ssfn_dst.p = @intCast(fb.pitch);
    c.ssfn_dst.x = 0;
    c.ssfn_dst.y = 0;
    c.ssfn_dst.bg = bgColor;
    c.ssfn_dst.fg = fgColor;
}

// Drawing
pub fn drawPixel(xpos: usize, ypos: usize, color: u32) VideoError!void {
    // Bounds checking
    if (xpos > fb.width or ypos > fb.height) return VideoError.OutOfBounds;

    const fbPtr: [*]u32 = @ptrCast(@alignCast(fb.address));
    fbPtr[ypos * pixelsPerRow + xpos] = color;
}
pub fn drawRect(xpos: usize, ypos: usize, width: usize, height: usize, color: u32) VideoError!void {
    // Bounds checking
    if (xpos > fb.width or ypos > fb.height) return VideoError.OutOfBounds;

    var fbPtr: [*]u32 = @ptrCast(@alignCast(fb.address));
    fbPtr += ypos * pixelsPerRow;
    for (ypos..ypos + height) |_| {
        @memset(fbPtr[xpos .. xpos + width], color);
        fbPtr += pixelsPerRow;
    }
}
pub fn drawLine(xpos1: isize, ypos1: isize, xpos2: isize, ypos2: isize, color: u32) VideoError!void {
    // Calculate change between X and Y position of the two points
    const dx: isize = @intCast(@abs(xpos2 - xpos1));
    const dy: isize = -@as(isize, @intCast(@abs(ypos2 - ypos1)));
    const sx: isize = if (xpos1 < xpos2) 1 else -1;
    const sy: isize = if (ypos1 < ypos2) 1 else -1;
    var err: isize = dx + dy;

    // Check if the line is above or below the ideal mathematical line
    var x: isize = xpos1;
    var y: isize = ypos1;
    while (true) {
        try drawPixel(@intCast(x), @intCast(y), color);
        const e2 = 2 * err;
        if (e2 >= dy) {
            if (x == xpos2) break;
            err += dy;
            x += sx;
        } else if (e2 <= dx) {
            if (y == ypos2) break;
            err += dx;
            y += sy;
        }
    }
}

/// Handle all possible errors
pub fn handleErr(err: VideoError) void {
    c.ssfn_dst.fg = colors.ERR_TEXT_COLOR;
    switch (err) {
        VideoError.OutOfBounds => {
            printf("[VIDEO DRIVER ERROR] Draw call out of bounds\n");
        },
    }
}

// Handy functions
/// Resets the text cursor position and clears the screen by drawing a rectangle that has the same color as the background over everything
pub fn clearScreen() VideoError!void {
    c.ssfn_dst.x = 0;
    c.ssfn_dst.y = 0;
    try drawRect(0, 0, fb.width, fb.height, c.ssfn_dst.bg);
}

/// Putchar implementation which is required for printf.
/// This function is responsible for handling all special characters and drawing each character to the screen.
export fn putchar_(char: u8) callconv(.c) void {
    // Force cursor to correct pixel cell
    c.ssfn_dst.x = @divTrunc(c.ssfn_dst.x, FONT_WIDTH) * FONT_WIDTH;
    c.ssfn_dst.y = @divTrunc(c.ssfn_dst.y, FONT_HEIGHT) * FONT_HEIGHT;

    // Figure out the next cursor position
    const isXOffScreen: bool = (c.ssfn_dst.x + FONT_WIDTH) > fb.width;
    const isYOffScreen: bool = (c.ssfn_dst.y + FONT_HEIGHT) > fb.height;

    // Draw over last cursor to 'delete' it
    drawRect(@intCast(cursorLastX), @intCast(cursorLastY), CURSOR_WIDTH, FONT_HEIGHT, c.ssfn_dst.bg) catch |e| handleErr(e);

    // Handle special characters
    switch (char) {
        // Newline
        '\n' => {
            // Go to the beginning of the next line
            c.ssfn_dst.x = 0;
            if (isYOffScreen) {
                clearScreen() catch |e| handleErr(e);
            } else c.ssfn_dst.y += FONT_HEIGHT;
        },

        // Backspace
        '\x08' => {
            if (c.ssfn_dst.x > 0) c.ssfn_dst.x -= FONT_WIDTH;
            drawRect(@intCast(c.ssfn_dst.x), @intCast(c.ssfn_dst.y), FONT_WIDTH, FONT_HEIGHT, c.ssfn_dst.bg) catch |e| handleErr(e);
        },

        // Normal character
        else => {
            // Ensure character stays inside the screen/framebuffer
            if (isYOffScreen) clearScreen() catch |e| handleErr(e);
            if (isXOffScreen) _ = c.ssfn_putc('\n');

            // Render the character
            _ = c.ssfn_putc(char);
        },
    }

    // Draw new cursor and save it's position
    drawRect(@intCast(c.ssfn_dst.x), @intCast(c.ssfn_dst.y), CURSOR_WIDTH, FONT_HEIGHT, c.ssfn_dst.fg) catch |e| handleErr(e);
    cursorLastX = c.ssfn_dst.x;
    cursorLastY = c.ssfn_dst.y;
}
