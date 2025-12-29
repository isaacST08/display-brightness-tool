const std = @import("std");
const shared_memory = @import("shared_memory.zig");

const Allocator = std.mem.Allocator;
const SharedMemoryObject = shared_memory.SharedMemoryObject;

const pow = std.math.pow;
const ceil = std.math.ceil;
const log10 = std.math.log10;

pub const DisplayNumber = u16;

const allocator = std.heap.c_allocator;

pub const Display = struct {
    /// The display number in the system.
    display_number: DisplayNumber,

    /// The I2C bus number of the display.
    display_bus: ?u32 = null,

    /// The current brightness of the display.
    brigtness: u32 = 0,

    /// The maximum brightness the display can be set to.
    max_brightness: u32 = 100,

    /// The time in seconds relative to the epoch when the brightness of the
    /// display was last updated.
    last_updated: i64 = 0,

    const BRIGHNESS_VCP_CODE = 10;
    const LAST_CHANGE_LIFE_SPAN = 20;

    pub fn init(display_number: DisplayNumber) !Display {
        var self = Display{
            .display_number = display_number,
        };
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

pub const MemoryDisplay = struct {
    display_number: DisplayNumber,
    shm_display: SharedMemoryObject(Display),

    const SHM_DISPLAY_PATH_PREFIX: []const u8 = "/display-brightness-tool-display-";
    const SHM_DISPLAY_NUM_STR_MAX_LEN: usize = intDisplayLen(DisplayNumber);
    const SHM_DISPLAY_PATH_LEN: usize = (SHM_DISPLAY_PATH_PREFIX.len + SHM_DISPLAY_NUM_STR_MAX_LEN + 1);

    pub fn init(display_number: DisplayNumber) !MemoryDisplay {

        // ----- Shared Memory Path -----

        // Create a buffer for the shared memory path.
        var shm_path_buf: [SHM_DISPLAY_PATH_LEN]u8 = undefined;

        // Construct the shared memory path for this display.
        const shm_path = (std.fmt.bufPrint(
            &shm_path_buf,
            std.fmt.comptimePrint("{{s}}{{d:0>{d}}}", .{SHM_DISPLAY_NUM_STR_MAX_LEN}),
            .{ SHM_DISPLAY_PATH_PREFIX, display_number },
        ) catch unreachable);

        // ----- Shared Memory Display -----

        // Get/Create the shared memory of the display.
        const shm_display = try SharedMemoryObject(Display).init(shm_path, false);
        if (shm_display.created_new) {
            shm_display.obj_ptr.* = try Display.init(display_number);
        }

        return .{
            .display_number = display_number,
            .shm_display = shm_display,
        };
    }

    pub fn deinit(self: *MemoryDisplay) void {
        self.shm_display.deinit();
    }
};

// **=======================================**
// ||          <<<<< HELPERS >>>>>          ||
// **=======================================**

inline fn intDisplayLen(int_type: type) u64 {
    return std.math.ceil(log10(@as(f64, pow(usize, 2, @bitSizeOf(int_type)))));
}
