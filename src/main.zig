const std = @import("std");
// const c = @cImport({
//     @cInclude("sys/shm.h");
//     @cInclude("string.h");
// });

const BRIGHNESS_VCP_CODE = 10;
const LAST_CHANGE_LIFE_SPAN = 20;

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
const allocator = gpa.allocator();

const Display = struct {
    /// The display number in the system.
    display_number: u32,

    /// The current brightness of the display.
    brigtness: u32 = 0,

    /// The maximum brightness the display can be set to.
    max_brightness: u32 = 0,

    pub fn init(display_number: u32) !Display {
        var self = Display{ .display_number = display_number };
        try self.update();
        return self;
    }

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
        var child = std.process.Child.init(&argv, allocator);
        try child.spawn();
        // std.debug.print("Child pid: {d}\n", .{child.id});
        // const exit_code = try child.wait();
        _ = try child.wait();

        // Update the brightness of this display object.
        // Assumes the brightness of the physical display was set successfully.
        self.brigtness = capped_brightness;

        // std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});

        // Return what the brightness was set to.
        // return capped_brightness;
    }

    fn update(self: *Display) !void {
        var buf: [10]u8 = undefined; // Used to convert ints (<=u32) to strings.
        // var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);

        // Create array lists to record stdout and stderr from the child
        // process.
        var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
        defer child_stdout.deinit(allocator);
        var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
        defer child_stderr.deinit(allocator);

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
        var child = std.process.Child.init(&argv, allocator);

        // Collect child output.
        child.stdout_behavior = .Pipe; // Record stdout
        child.stderr_behavior = .Pipe; // Ignore stderr

        // Exec the child.
        try child.spawn();
        // std.debug.print("Child pid: {d}\n", .{child.id});
        try child.collectOutput(allocator, &child_stdout, &child_stderr, 512);
        // std.debug.print("Child stdout behaviour: {}\n", .{child.stdout_behavior});

        // Wait for the child to complete.
        // const exit_code = try child.wait();
        _ = try child.wait();

        // Convert the stdout array list to a slice.
        const child_stdout_slice = try child_stdout.toOwnedSlice(allocator);
        defer allocator.free(child_stdout_slice);
        // std.debug.print("Child stdout: {s}\n", .{child_stdout_slice});

        // Parse display state information stdout from the child.
        var it = std.mem.splitScalar(u8, child_stdout_slice, ':');
        _ = it.next(); // Discard the header.
        it = std.mem.splitScalar(u8, it.rest(), ',');
        while (it.next()) |x| {
            var param_it = std.mem.splitScalar(u8, x, '=');

            // Parse the name and value for this param.
            const param_name =
                if (param_it.next()) |y| std.mem.trim(u8, y, " \t\n") else continue;
            // std.debug.print("Param name: {s}\n", .{param_name});
            const param_value =
                std.fmt.parseInt(u32, if (param_it.next()) |y| std.mem.trim(u8, y, " \t\n") else continue, 10) catch continue;
            // std.debug.print("Param value: {d}\n", .{param_value});

            // Set the appropriate values.
            if (std.mem.eql(u8, param_name, "current value"))
                self.brigtness = param_value
            else if (std.mem.eql(u8, param_name, "max value"))
                self.max_brightness = param_value;

            // if (itt.next()) |y| {
            //     std.debug.print("param_name: {s}\n", .{y});
            //     const param_name = std.mem.trim(u8, y, " \t\n");
            //     std.debug.print("param_name: {s}\n", .{param_name});
            //     if (std.mem.eql(u8, "current value", param_name)) {
            //         if (itt.next()) |param_value_str| {
            //             if (std.fmt.parseInt(u32, param_value_str, 10)) |param_value| {
            //                 std.debug.print("hi\n", .{});
            //                 self.brigtness = param_value;
            //             } else |_| {
            //                 std.debug.print("sad\n", .{});
            //             }
            //         }
            //     }
            // }
            // std.debug.print("{s}\n", .{x});
        }

        // std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});

        // return 101;
    }
};

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

    //try setDisplayBrightness(2, 40);
    // _ = try getDisplayBrightness(2);

    // var display = Display{ .display_number = 2, .brigtness = 0, .max_brightness = 100 };
    // try display.update();
    var display = try Display.init(2);
    std.debug.print("Display Brightness: {d}\n", .{display.brigtness});
    std.debug.print("Display Max Brightness: {d}\n", .{display.max_brightness});

    try display.setBrightness(50);
    std.debug.print("Display Brightness: {d}\n", .{display.brigtness});
    std.debug.print("Display Max Brightness: {d}\n", .{display.max_brightness});
}

// fn setDisplayBrightness(display_number: u9, brightness: u7) !u7 {
//     var buf: [3]u8 = undefined; // Used to convert ints (<=u9) to strings.
//
//     // Cap the brightness to a safe range.
//     const capped_brightness: u7 = if (brightness <= 100) brightness else 100;
//
//     // Create the args to change the brightness using ddcutil.
//     const argv = [_][]const u8{
//         "ddcutil",
//
//         // Set to the VCP brightness code.
//         "setvcp",
//         std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),
//
//         // Brightness
//         try std.fmt.bufPrint(&buf, "{d}", .{capped_brightness}),
//
//         // Display number
//         "-d",
//         try std.fmt.bufPrint(&buf, "{d}", .{display_number}),
//     };
//
//     // Execute the process.
//     var child = std.process.Child.init(&argv, allocator);
//     try child.spawn();
//     std.debug.print("Child pid: {d}\n", .{child.id});
//     const exit_code = try child.wait();
//
//     std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});
//
//     // Return what the brightness was set to.
//     return capped_brightness;
// }
//
// fn getDisplayBrightness(display_number: u9) !u7 {
//     var buf: [3]u8 = undefined; // Used to convert ints (<=u9) to strings.
//     // var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
//     var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
//     var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
//     defer child_stdout.deinit(allocator);
//     defer child_stderr.deinit(allocator);
//
//     const argv = [_][]const u8{
//         "ddcutil",
//
//         // Get from the VCP brightness code.
//         "getvcp",
//         std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),
//
//         // Display number
//         "-d",
//         try std.fmt.bufPrint(&buf, "{d}", .{display_number}),
//     };
//
//     // Set up the child process.
//     var child = std.process.Child.init(&argv, allocator);
//
//     // Collect child output.
//     child.stdout_behavior = .Pipe; // Record stdout
//     child.stderr_behavior = .Pipe; // Ignore stderr
//
//     // Exec the child.
//     try child.spawn();
//     std.debug.print("Child pid: {d}\n", .{child.id});
//     try child.collectOutput(allocator, &child_stdout, &child_stderr, 512);
//     // std.debug.print("Child stdout behaviour: {}\n", .{child.stdout_behavior});
//
//     // Wait for the child to complete.
//     const exit_code = try child.wait();
//
//     const child_stdout_slice = try child_stdout.toOwnedSlice(allocator);
//     defer allocator.free(child_stdout_slice);
//     std.debug.print("Child stdout: {s}\n", .{child_stdout_slice});
//
//     // Parse the output.
//     var it = std.mem.splitScalar(u8, child_stdout_slice, ':');
//     while (it.next()) |x| {
//         std.debug.print("{s}\n", .{x});
//     }
//
//     std.debug.print("Exit code: {d}\n\n", .{exit_code.Exited});
//
//     return 101;
// }
