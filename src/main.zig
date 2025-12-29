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

pub fn main() !u8 {
    const options = cli_args.parseArgs();
    defer options.deinit();

    // #######################################################

    var shm_display = try MemoryDisplay.init(1);
    defer shm_display.deinit();

    // Get/Create the shared memory queue.
    const shm_queue = try SharedMemoryObject(ProcQueue).init(shared_memory.SHARED_MEMORY_PATH_PREFIX ++ "queue", false);
    defer shm_queue.deinit();
    if (shm_queue.created_new) {
        shm_queue.obj_ptr.* = ProcQueue{};
    }
    // shm_queue.obj_ptr.* = ProcQueue{};

    const queue_ptr: *ProcQueue = shm_queue.obj_ptr;

    const self_pid: i32 = std.c.getpid();

    queue_ptr.wait();

    std.debug.print("Pid {d} doing CS stuff.\n", .{self_pid});

    std.Thread.sleep(2_000_000_000);

    queue_ptr.signal();
    std.debug.print("Pid {d} done.\n", .{self_pid});

    return 0;
}
