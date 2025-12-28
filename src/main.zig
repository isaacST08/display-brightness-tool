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
    std.debug.print("Hello world\n", .{});

    // var display = try Display.init(2);
    // std.debug.print("Display Brightness: {d}\n", .{display.brigtness});
    // std.debug.print("Display Max Brightness: {d}\n", .{display.max_brightness});
    //
    // try display.setBrightness(50);
    // std.debug.print("Display Brightness: {d}\n", .{display.brigtness});
    // std.debug.print("Display Max Brightness: {d}\n", .{display.max_brightness});

    // // Attempt to create new shared memory.
    // var fd_queue: c_int = std.c.shm_open("/display-brightness-tool-queue", @bitCast(std.c.O{ .CREAT = true, .EXCL = true, .ACCMODE = .RDWR }), 0o666);
    // var fd_mutex: c_int = std.c.shm_open("/display-brightness-tool-mutex", @bitCast(std.c.O{ .CREAT = true, .EXCL = true, .ACCMODE = .RDWR }), 0o666);
    //
    // // If the shared memory failed to open because it already exists, simply
    // // open the already existing memory.
    // // Otherwise, truncate memory to the appropriate length.
    // if (fd_queue == -1) {
    //     const err_no: u32 = @bitCast(std.c._errno().*);
    //     const err: std.posix.E = @enumFromInt(err_no);
    //     switch (err) {
    //         .EXIST => {
    //             fd_queue = std.c.shm_open("/display-brightness-tool-queue", @bitCast(std.c.O{ .ACCMODE = .RDWR }), 0o666);
    //         },
    //         else => return std.posix.unexpectedErrno(err),
    //     }
    // } else {
    //     // QUEUE-HEAD: u8 -> 1 Byte
    //     // QUEUE-TAIL: u8 -> 1 Byte
    //     // QUEUE-SIZE: u32 * 256 -> 1024 Bytes
    //     // Total: 1026 Bytes
    //     try std.posix.ftruncate(fd_queue, @intCast(@sizeOf(ProcQueue)));
    // }
    // if (fd_mutex == -1) {
    //     const err_no: u32 = @bitCast(std.c._errno().*);
    //     const err: std.posix.E = @enumFromInt(err_no);
    //     switch (err) {
    //         .EXIST => {
    //             fd_mutex = std.c.shm_open("/display-brightness-tool-mutex", @bitCast(std.c.O{ .ACCMODE = .RDWR }), 0o666);
    //         },
    //         else => return std.posix.unexpectedErrno(err),
    //     }
    // } else {
    //     try std.posix.ftruncate(fd_mutex, @intCast(@sizeOf(std.Thread.Mutex)));
    //     const mutex_byte_arr = try std.posix.mmap(null, @intCast(@sizeOf(std.Thread.Mutex)), std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd_mutex, 0);
    //     const mutex_ptr: *std.Thread.Mutex = @ptrCast(@alignCast(@constCast(&mutex_byte_arr)));
    //     defer std.posix.munmap(@alignCast(mutex_byte_arr));
    //
    //     mutex_ptr.* = std.Thread.Mutex{};
    // }
    //
    // const queue_ptr = try std.posix.mmap(null, @intCast(@sizeOf(ProcQueue)), std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd_queue, 0);
    // defer std.posix.munmap(@alignCast(queue_ptr));
    //
    // const mutex_byte_arr = try std.posix.mmap(null, @intCast(@sizeOf(std.Thread.Mutex)), std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd_mutex, 0);
    // const mutex_ptr: *std.Thread.Mutex = @ptrCast(@alignCast(@constCast(&mutex_byte_arr)));
    // defer std.posix.munmap(@alignCast(mutex_byte_arr));

    const shm_queue = try SharedMemoryObject(ProcQueue).init("/display-brightness-tool-queue", true);
    defer shm_queue.deinit();
    if (shm_queue.created_new) {
        shm_queue.obj_ptr.* = ProcQueue{};
    }
    // shm_queue.obj_ptr.* = ProcQueue{};
    const shm_sem = try SharedMemoryObject(std.Thread.Semaphore).init("/display-brightness-tool-semaphore", true);
    defer shm_sem.deinit();
    const shm_int = try SharedMemoryObject(u32).init("/display-brightness-tool-int", true);
    defer shm_int.deinit();

    const queue_ptr: *ProcQueue = shm_queue.obj_ptr;

    const self_pid: i32 = std.c.getpid();

    if (shm_sem.created_new) {
        shm_sem.obj_ptr.* = std.Thread.Semaphore{ .permits = 1 };
    }
    // shm_sem.obj_ptr.* = std.Thread.Semaphore{ .permits = 1 };

    // queue_ptr.join();
    // std.debug.print("Pid {d} joined the queue.\n", .{self_pid});

    queue_ptr.wait();
    // std.debug.print("Pid {d} joined the queue.\n", .{self_pid});
    //
    std.debug.print("Pid {d} doing CS stuff.\n", .{self_pid});

    std.Thread.sleep(2_000_000_000);

    queue_ptr.signal();
    std.debug.print("Pid {d} done.\n", .{self_pid});

    // var waiting = true;
    // while (waiting) {
    //     if (shm_sem.obj_ptr.timedWait(10_000_000_000)) |_| {
    //         waiting = false;
    //     } else |_| {}
    // }
    //
    // for (0..10) |i| {
    //     std.debug.print("Pid: {d}, Index: {d}\n", .{ self_pid, i });
    //     std.Thread.sleep(200_000_000); // 200ms
    // }
    //
    // shm_sem.obj_ptr.post();
    // shm_sem.sync();
    // try std.Thread.yield();
    // shm_sem.obj_ptr
    //     .std.debug.print("Pid {d} done.\n", .{self_pid});

    // shm_sem.obj_ptr.wait();
    // std.debug.print("Pid {d} waiting again.\n", .{self_pid});
    // shm_sem.obj_ptr.post();
    // std.debug.print("Pid {d} released again.\n", .{self_pid});
}
