/// The display number in the system.
display_number: u32,

/// The current brightness of the display.
brigtness: u32 = 0,

/// The maximum brightness the display can be set to.
max_brightness: u32 = 0,

allocator: Allocator,

const Display = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const BRIGHNESS_VCP_CODE = 10;
const LAST_CHANGE_LIFE_SPAN = 20;

pub fn init(display_number: u32, allocator: Allocator) !Display {
    var self = Display{
        .display_number = display_number,
        .allocator = allocator,
    };
    try self.update();
    return self;
}

/// Sets the brightness of the display to `brightness`.
///
/// Will not exceed setting the brightness above the max brightness of the
/// display.
///
/// Parameters
/// ----------
/// `self` : *Display | The display to set the brightness of.
/// `brightness` : u32 | The brightness to set the display to.
pub fn setBrightness(self: *Display, brightness: u32) !void {
    // Used to convert ints (<=u32) to strings.
    var buf: [10]u8 = undefined;

    // Cap the brightness to a safe range for the display.
    const capped_brightness: u32 =
        if (brightness <= self.max_brightness) brightness else self.max_brightness;

    // Create the args to change the brightness using ddcutil.
    const argv = [_][]const u8{
        "ddcutil",

        // Set command to the VCP brightness code.
        "setvcp",
        std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),

        // Brightness
        try std.fmt.bufPrint(&buf, "{d}", .{capped_brightness}),

        // Display number
        "-d",
        try std.fmt.bufPrint(&buf, "{d}", .{self.display_number}),
    };

    // Execute the process.
    var child = std.process.Child.init(&argv, self.allocator);
    try child.spawn();
    _ = try child.wait();

    // Update the brightness of this display object.
    // Assumes the brightness of the physical display was set successfully.
    self.brigtness = capped_brightness;
}

/// Query the display for it's current brightness stats and update the
/// local values to match.
fn update(self: *Display) !void {
    var buf: [10]u8 = undefined; // Used to convert ints (<=u32) to strings.

    // Create array lists to record stdout and stderr from the child
    // process.
    var child_stdout = try std.ArrayList(u8).initCapacity(self.allocator, 512);
    defer child_stdout.deinit(self.allocator);
    var child_stderr = try std.ArrayList(u8).initCapacity(self.allocator, 8);
    defer child_stderr.deinit(self.allocator);

    // Create command args to get the brightness info from the display.
    const argv = [_][]const u8{
        "ddcutil",

        // Get from the VCP brightness code.
        "getvcp",
        std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),

        // Display number
        "-d",
        try std.fmt.bufPrint(&buf, "{d}", .{self.display_number}),
    };

    // Set up the child process.
    var child = std.process.Child.init(&argv, self.allocator);

    // Collect child output.
    child.stdout_behavior = .Pipe; // Record stdout
    child.stderr_behavior = .Pipe; // Ignore stderr

    // Exec the child.
    try child.spawn();
    try child.collectOutput(self.allocator, &child_stdout, &child_stderr, 512);

    // Wait for the child to complete.
    _ = try child.wait();

    // Convert the stdout array list to a slice.
    const child_stdout_slice = try child_stdout.toOwnedSlice(self.allocator);
    defer self.allocator.free(child_stdout_slice);

    // Parse display state information stdout from the child.
    var it = std.mem.splitScalar(u8, child_stdout_slice, ':');
    _ = it.next(); // Discard the header.
    it = std.mem.splitScalar(u8, it.rest(), ',');
    while (it.next()) |x| {
        var param_it = std.mem.splitScalar(u8, x, '=');

        // Parse the name and value for this param.
        const param_name =
            if (param_it.next()) |y| std.mem.trim(u8, y, " \t\n") else continue;
        const param_value =
            std.fmt.parseInt(u32, if (param_it.next()) |y| std.mem.trim(u8, y, " \t\n") else continue, 10) catch continue;

        // Set the appropriate values.
        if (std.mem.eql(u8, param_name, "current value"))
            self.brigtness = param_value
        else if (std.mem.eql(u8, param_name, "max value"))
            self.max_brightness = param_value;
    }
}
