const std = @import("std");
const display = @import("display");

const Display = display.Display;
const cli_args = @import("cli_args.zig");

/// The time in seconds until the state of the display(s) is assumed to still
/// be valid.
const USE_OLD_DATA_CUTOFF = 60;

const allocator = std.heap.c_allocator;

pub fn main() !u8 {
    // Parse the CLI args.
    const options = cli_args.parseArgs();
    defer options.deinit();

    // Get the set of displays to perform the action on.
    var display_set = try display.DisplaySet.init(options.options.display, allocator);
    defer display_set.deinit();

    // Clear the cache if requested.
    if (options.options.@"clear-cache") {
        // Flag the current shared memory used by the display set as non
        // persistent.
        if (display_set.shm_display_numbers) |*sdn|
            sdn.persistent = false;
        for (display_set.shm_displays) |*shm_display| {
            shm_display.shm_display.persistent = false;
        }

        // Deinit the now non-persistent display set and re-init it.
        display_set.deinit();
        display_set = try display.DisplaySet.init(options.options.display, allocator);
    }

    // Perform the action on all the monitors.
    if (options.options.action) |action| {

        // Allocate memory for the workers that will each perform the action on one display.
        var display_workers: []std.Thread = try allocator.alloc(std.Thread, display_set.display_count);
        defer allocator.free(display_workers);

        // Perform the action on each display.
        for (display_set.shm_displays, 0..) |shm_display, i| {
            const display_ptr = shm_display.shm_display.obj_ptr;

            if (std.time.timestamp() - display_ptr.last_updated.load(.seq_cst) > USE_OLD_DATA_CUTOFF) {
                try display_ptr.updateBrightness();
            }

            const value = options.options.value orelse 0;
            display_workers[i] = switch (action) {
                .set => try std.Thread.spawn(.{ .allocator = allocator }, Display.setBrightness, .{ display_ptr, @as(u32, @intCast(value)) }),
                .increase => try std.Thread.spawn(.{ .allocator = allocator }, Display.increaseBrightness, .{ display_ptr, value }),
                .decrease => try std.Thread.spawn(.{ .allocator = allocator }, Display.decreaseBrightness, .{ display_ptr, value }),
                .save => try std.Thread.spawn(.{ .allocator = allocator }, Display.saveBrightness, .{display_ptr}),
                .restore => try std.Thread.spawn(.{ .allocator = allocator }, Display.restoreBrightness, .{display_ptr}),
                .dim => try std.Thread.spawn(.{ .allocator = allocator }, Display.dimBrightness, .{ display_ptr, @as(u32, @intCast(value)) }),
                .undim => try std.Thread.spawn(.{ .allocator = allocator }, Display.undimBrightness, .{display_ptr}),
            };
        }

        // Wait for all the workers to finish their display actions.
        for (0..display_workers.len) |i| {
            display_workers[i].join();
        }
    }

    return 0;
}
