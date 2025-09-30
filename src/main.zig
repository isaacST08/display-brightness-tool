const std = @import("std");

const BRIGHNESS_VCP_CODE = 10;
const LAST_CHANGE_LIFE_SPAN = 20;

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
const allocator = gpa.allocator();

pub fn main() !void {
    std.debug.print("Hello world\n", .{});

    // // const argv = [_][]const u8{ "echo", "Hello", "World" };
    // const argv = [_][]const u8{ "ddcutil", "setvcp", "10", "50", "--display=2" };
    // var child = std.process.Child.init(&argv, allocator);
    // try child.spawn();
    // std.debug.print("Child pid: {d}\n", .{child.id});
    // const exit_code = try child.wait();
    // // _ = try exit_code;
    //
    // std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});

    try setDisplayBrightness(2, 40);
}

fn setDisplayBrightness(display_number: u8, brightness: u7) !u7 {
    var buf: [3]u8 = undefined; // Used to convert ints (<=u8) to strings.

    // Cap the brightness to a safe range.
    const capped_brightness: u7 = if (brightness <= 100) brightness else 100;

    // Create the args to change the brightness using ddcutil.
    const argv = [_][]const u8{
        "ddcutil",

        // VCP Brightness Code
        "setvcp",
        std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),

        // Brightness
        try std.fmt.bufPrint(&buf, "{d}", .{capped_brightness}),

        // Display number
        "-d",
        try std.fmt.bufPrint(&buf, "{d}", .{display_number}),
    };

    // Execute the process.
    var child = std.process.Child.init(&argv, allocator);
    try child.spawn();
    std.debug.print("Child pid: {d}\n", .{child.id});
    const exit_code = try child.wait();

    std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});

    // Return what the brightness was set to.
    return capped_brightness;
}
