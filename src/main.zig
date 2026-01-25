const std = @import("std");
const display = @import("display");
const cli_args = @import("cli_args.zig");

const Display = display.Display;
const Thread = std.Thread;

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

    // Allocate memory for the workers that will each perform on one display.
    var display_workers: []?Thread = try allocator.alloc(?Thread, display_set.display_count);
    defer allocator.free(display_workers);

    // Start a thread for each display to update its brightness value.
    for (display_set.shm_displays, 0..) |shm_display, i| {
        const display_ptr = shm_display.shm_display.obj_ptr;

        display_workers[i] = if (options.options.update or (options.options.@"update-threshold" != 0 and std.time.timestamp() - display_ptr.last_updated.load(.seq_cst) > options.options.@"update-threshold"))
            Thread.spawn(.{ .allocator = allocator }, Display.updateBrightness, .{display_ptr}) catch null
        else
            null;
    }

    // Perform the action on all the monitors.
    if (options.options.action) |action| {

        // Perform the action on each display.
        for (display_set.shm_displays, 0..) |shm_display, i| {
            const display_ptr = shm_display.shm_display.obj_ptr;

            // If a worker for this display was created to update its
            // brightness, join it before assuming the next action task.
            if (display_workers[i]) |worker|
                worker.join();

            const value = options.options.value orelse 0;
            display_workers[i] = switch (action) {
                .set => Thread.spawn(.{ .allocator = allocator }, Display.setBrightness, .{ display_ptr, @as(u32, @intCast(value)) }) catch null,
                .increase => Thread.spawn(.{ .allocator = allocator }, Display.increaseBrightness, .{ display_ptr, value }) catch null,
                .decrease => Thread.spawn(.{ .allocator = allocator }, Display.decreaseBrightness, .{ display_ptr, value }) catch null,
                .save => Thread.spawn(.{ .allocator = allocator }, Display.saveBrightness, .{display_ptr}) catch null,
                .restore => Thread.spawn(.{ .allocator = allocator }, Display.restoreBrightness, .{display_ptr}) catch null,
                .dim => Thread.spawn(.{ .allocator = allocator }, Display.dimBrightness, .{ display_ptr, @as(u32, @intCast(value)) }) catch null,
                .undim => Thread.spawn(.{ .allocator = allocator }, Display.undimBrightness, .{display_ptr}) catch null,
            };
        }
    }

    // Wait for all the workers to finish their tasks.
    for (0..display_workers.len) |i| {
        if (display_workers[i]) |worker|
            worker.join();
    }

    return 0;
}
