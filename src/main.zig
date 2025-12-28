const std = @import("std");
const shared_memory = @import("shared_memory.zig");

const CheckingSemaphore = @import("CheckingSemaphore.zig");
const Display = @import("Display.zig");
const ProcQueue = @import("ProcQueue.zig");
const Semaphore = std.Thread.Semaphore;
const SharedMemoryObject = shared_memory.SharedMemoryObject;

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
const allocator = gpa.allocator();

pub fn main() !void {

    // Get/Create the shared memory queue.
    const shm_queue = try SharedMemoryObject(ProcQueue).init("/display-brightness-tool-queue", true);
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
}
