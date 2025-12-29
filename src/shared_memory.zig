const std = @import("std");

const SharedMemoryPath = struct {
    buf: [std.c.NAME_MAX + 1]u8 = .{0} ** (std.c.NAME_MAX + 1),
    len: u8,

    /// Creates a shared memory path at the `source` path.
    pub fn init(source: []const u8) SharedMemoryPath {
        var self = SharedMemoryPath{
            .len = @truncate(source.len),
        };

        // Copy the source path to the buffer, null terminated.
        _ = std.fmt.bufPrintZ(&self.buf, "{s}", .{source[0..@min(self.len, std.c.NAME_MAX)]}) catch unreachable;

        return self;
    }

    /// Gets the string form of the shared memory path.
    pub inline fn getPath(self: SharedMemoryPath) []const u8 {
        return self.buf[0..@min(self.len, std.c.NAME_MAX)];
    }

    /// Gets the null-terminated string form of the shared memory path.
    pub inline fn getPathZ(self: SharedMemoryPath) [:0]const u8 {
        return self.buf[0..@min(self.len, std.c.NAME_MAX) :0];
    }
};

/// Creates, stores, and references an object of type `T` in shared memory so
/// that it can be accessed by completely separate processes.
pub fn SharedMemoryObject(comptime T: type) type {
    return struct {
        const Self = @This();

        shm_path: SharedMemoryPath,
        fd: c_int,
        obj_byte_arr: []align(std.heap.page_size_min) u8,
        obj_ptr: *T,
        persistent: bool,
        created_new: bool,

        pub fn init(shm_path_str: []const u8, persistent: bool) !Self {
            // Create a shared memory path object from the source path.
            var shm_path = SharedMemoryPath.init(shm_path_str);

            // Attempt to create new shared memory.
            var fd: c_int = std.c.shm_open(shm_path.getPathZ(), @bitCast(std.c.O{ .CREAT = true, .EXCL = true, .ACCMODE = .RDWR }), 0o666);

            // Variable to record whether the shared memory was created or simply opened.
            var created_new: bool = false;

            // If the shared memory failed to open because it already exists, simply
            // open the already existing memory.
            if (fd == -1) {
                const err_no: u32 = @bitCast(std.c._errno().*);
                const err: std.posix.E = @enumFromInt(err_no);
                switch (err) {
                    .EXIST => {
                        fd = std.c.shm_open(shm_path.getPathZ(), @bitCast(std.c.O{ .ACCMODE = .RDWR }), 0o666);
                    },
                    else => return std.posix.unexpectedErrno(err),
                }
            }
            // Otherwise, truncate memory to the appropriate length.
            else {
                try std.posix.ftruncate(fd, @intCast(@sizeOf(T)));
                created_new = true;
            }

            // Get the pointer to the object.
            const obj_byte_arr = try std.posix.mmap(null, @intCast(@sizeOf(T)), std.posix.PROT.READ | std.posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
            const obj_ptr: *T = std.mem.bytesAsValue(T, obj_byte_arr);

            // Construct self and return.
            return Self{
                .shm_path = shm_path,
                .fd = fd,
                .obj_byte_arr = obj_byte_arr,
                .obj_ptr = obj_ptr,
                .persistent = persistent,
                .created_new = created_new,
            };
        }

        pub fn deinit(self: Self) void {
            std.posix.munmap(@alignCast(self.obj_byte_arr));

            // If the shared memory is not flagged to be persistent, flag it
            // for removal when all users are done with it.
            if (!self.persistent) {
                _ = std.c.shm_unlink(self.shm_path.getPathZ());
            }
        }

        pub fn sync(self: Self) void {
            _ = std.c.msync(@ptrCast(@alignCast(self.obj_byte_arr)), @intCast(@sizeOf(T)), std.c.MSF.SYNC);
        }
    };
}
