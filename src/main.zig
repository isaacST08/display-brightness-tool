const std = @import("std");
const shared_memory = @import("shared_memory.zig");
const display = @import("display.zig");

const CheckingSemaphore = @import("CheckingSemaphore.zig");
const Display = display.Display;
const MemoryDisplay = display.MemoryDisplay;
const ProcQueue = @import("ProcQueue.zig");
const Semaphore = std.Thread.Semaphore;
const SharedMemoryObject = shared_memory.SharedMemoryObject;
const cli_args = @import("cli_args.zig");
const DisplayNumber = display.DisplayNumber;

/// The time in seconds until the state of the display(s) is assumed to still
/// be valid.
const USE_OLD_DATA_CUTOFF = 60;

const allocator = std.heap.c_allocator;

pub fn main() !u8 {
    // Parse the CLI args.
    const options = cli_args.parseArgs();
    defer options.deinit();

    const self_pid: i32 = std.c.getpid();

    // --- Get/Create the shared memory queue ---
    const shm_queue = try SharedMemoryObject(ProcQueue).init(shared_memory.SHARED_MEMORY_PATH_PREFIX ++ "queue", true);
    defer shm_queue.deinit();
    if (shm_queue.created_new)
        shm_queue.obj_ptr.* = ProcQueue{};
    const queue_ptr: *ProcQueue = shm_queue.obj_ptr;

    // Get the list of displays to act on.
    const display_numbers = try display.getDisplayNumbers(options.options.display, allocator);
    defer allocator.free(display_numbers);

    // Wait for access to the monitor CS.
    queue_ptr.wait();
    std.debug.print("Pid {d} doing CS stuff.\n", .{self_pid});

    // Perform the action on all the monitors.
    if (options.options.action) |action| {
        for (display_numbers) |display_number| {
            // Get/Create the shared memory display to act on.
            var shm_display = try MemoryDisplay.init(display_number);
            defer shm_display.deinit();
            const display_ptr = shm_display.shm_display.obj_ptr;

            // std.Thread.sleep(2_000_000_000);

            if (std.time.timestamp() - display_ptr.last_updated > USE_OLD_DATA_CUTOFF) {
                try display_ptr.updateBrightness();
            }
            // try display_ptr.updateInfo();

            const value = switch (action) {
                .set, .increase, .decrease => options.options.value orelse 0,
                else => 0,
            };
            switch (action) {
                .set => try display_ptr.setBrightness(@intCast(value)),
                .increase => try display_ptr.increaseBrightness(value),
                .decrease => try display_ptr.decreaseBrightness(value),
                .save => display_ptr.saveBrightness(),
                .restore => try display_ptr.restoreBrightness(),
            }
        }
    }

    // Leave the CS.
    queue_ptr.signal();
    std.debug.print("Pid {d} done.\n", .{self_pid});

    return 0;
}
