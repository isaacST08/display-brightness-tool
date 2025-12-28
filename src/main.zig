const std = @import("std");
const shared_memory = @import("shared_memory.zig");

const CheckingSemaphore = @import("CheckingSemaphore.zig");
const ProcQueue = @import("ProcQueue.zig");
const Semaphore = std.Thread.Semaphore;
const SharedMemoryObject = shared_memory.SharedMemoryObject;

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
        var child = std.process.Child.init(&argv, allocator);
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
        try child.collectOutput(allocator, &child_stdout, &child_stderr, 512);

        // Wait for the child to complete.
        _ = try child.wait();

        // Convert the stdout array list to a slice.
        const child_stdout_slice = try child_stdout.toOwnedSlice(allocator);
        defer allocator.free(child_stdout_slice);

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
};

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
