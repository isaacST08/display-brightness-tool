const std = @import("std");
const shared_memory = @import("shared_memory.zig");

const Allocator = std.mem.Allocator;
const SharedMemoryObject = shared_memory.SharedMemoryObject;

const pow = std.math.pow;
const ceil = std.math.ceil;
const log10 = std.math.log10;

pub const DisplayNumber = u16;
pub const I2CBusNumber = u10;

pub const DisplayTag = union((enum { set, number })) {
    set: enum { all, oled },
    number: DisplayNumber,

    pub fn parse(x: []const u8) !@This() {
        return if (std.mem.eql(u8, x, "all"))
            .{ .set = .all }
        else if (std.mem.eql(u8, x, "oled"))
            .{ .set = .oled }
        else if (std.fmt.parseInt(DisplayNumber, x, 10)) |num|
            .{ .number = num }
        else |err|
            err;
    }
};

pub const DisplayInfo = struct {
    i2c_bus: ?I2CBusNumber = null,
    drm_connector: [256]u8 = .{0} ** 256,
    drm_connector_id: ?u32 = null,
    monitor: [256]u8 = .{0} ** 256,
};

pub const Display = struct {
    /// The display number in the system.
    display_number: DisplayNumber,

    /// Information related to the display.
    display_info: DisplayInfo = .{},

    /// The current brightness of the display.
    brigtness: u32 = 0,

    /// The maximum brightness the display can be set to.
    max_brightness: u32 = 100,

    /// The time in seconds relative to the epoch when the brightness of the
    /// display was last updated.
    last_updated: i64 = 0,

    /// A saved brightness value that can be restored to later.
    saved_brightness: u32 = 0,

    const BRIGHNESS_VCP_CODE = 10;
    const LAST_CHANGE_LIFE_SPAN = 20;

    const allocator = std.heap.c_allocator;

    pub fn init(display_number: DisplayNumber) !Display {
        var self = Display{
            .display_number = display_number,
        };
        try self.updateInfo();
        try self.updateBrightness();
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
        var brightness_buf: [intDisplayLen(u32)]u8 = undefined;
        var display_comm_buf: [@max(intDisplayLen(DisplayNumber), intDisplayLen(I2CBusNumber))]u8 = undefined;

        // Cap the brightness to a safe range for the display.
        const capped_brightness: u32 = @min(brightness, self.max_brightness);

        // std.debug.print("Capped brightness: {d}\n", .{capped_brightness});
        // std.debug.print("I2CBusNumber: {?d}\n", .{self.display_info.i2c_bus});
        // std.debug.print("Display number: {d}\n", .{self.display_number});

        // Create the args to change the brightness using ddcutil.
        const argv = [_][]const u8{
            "ddcutil",

            // Set command to the VCP brightness code.
            "setvcp",
            std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),

            // Brightness
            try std.fmt.bufPrint(&brightness_buf, "{d}", .{capped_brightness}),
        }
            // Display number or I2C bus.
            ++ ddcutilCommArgs(self, &display_comm_buf);

        // std.debug.print("ddcutil Args:", .{});
        // for (argv) |arg| {
        //     std.debug.print(" {s}", .{arg});
        // }
        // std.debug.print("\n", .{});

        // Execute the process.
        var child = std.process.Child.init(&argv, allocator);
        try child.spawn();
        _ = try child.wait();

        // Update the brightness of this display object.
        // Assumes the brightness of the physical display was set successfully.
        self.brigtness = capped_brightness;
    }

    /// Increases the brightness of the display by the amount of
    /// `brightness_change`.
    pub fn increaseBrightness(self: *Display, brightness_change: i32) !void {
        const brightness_absolute: u32 = @intCast(@as(i64, self.brigtness) + @as(i64, brightness_change));

        try self.setBrightness(brightness_absolute);
    }

    /// Decreases the brightness of the display by the amount of
    /// `brightness_change`.
    pub fn decreaseBrightness(self: *Display, brightness_change: i32) !void {
        try self.increaseBrightness(-1 * brightness_change);
    }

    /// Saves the current brightness of the display.
    pub fn saveBrightness(self: *Display) void {
        self.saved_brightness = self.brigtness;
    }

    /// Restores the brightness of the display to the currently saved
    /// brightness value.
    pub fn restoreBrightness(self: *Display) !void {
        try self.setBrightness(self.saved_brightness);
    }

    /// Query the display for it's current brightness stats and update the
    /// local values to match.
    pub fn updateBrightness(self: *Display) !void {
        var buf: [@max(intDisplayLen(DisplayNumber), intDisplayLen(I2CBusNumber))]u8 = undefined; // Used to convert ints (<=u32) to strings.

        // Create array lists to record stdout and stderr from the child
        // process.
        var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
        defer child_stdout.deinit(allocator);
        var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
        defer child_stderr.deinit(allocator);

        std.debug.print("I2CBusNumber: {?d}\n", .{self.display_info.i2c_bus});
        std.debug.print("Display number: {d}\n", .{self.display_number});

        // Create command args to get the brightness info from the display.
        const argv = [_][]const u8{
            "ddcutil",

            // Get from the VCP brightness code.
            "getvcp",
            std.fmt.comptimePrint("{d}", .{BRIGHNESS_VCP_CODE}),
        }
            // Display number or I2C bus (if available).
            ++ ddcutilCommArgs(self, &buf);

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

        // Record the update time stamp.
        self.last_updated = std.time.timestamp();
    }

    pub fn updateInfo(self: *Display) !void {
        // ----- CHILD PROCESS -----

        // Create array lists to record stdout and stderr from the child
        // process.
        var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
        defer child_stdout.deinit(allocator);
        var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
        defer child_stderr.deinit(allocator);

        // Args to detect displays.
        const argv = [_][]const u8{ "ddcutil", "detect", "--brief" };

        // Set up the child process.
        var child = std.process.Child.init(&argv, allocator);

        // Collect child output.
        child.stdout_behavior = .Pipe; // Record stdout
        child.stderr_behavior = .Pipe; // Ignore stderr

        // Exec the child.
        try child.spawn();
        try child.collectOutput(allocator, &child_stdout, &child_stderr, 16384);

        // Wait for the child to complete.
        _ = try child.wait();

        // ----- RESULT PARSING -----

        // Convert the stdout array list to a slice.
        const child_stdout_slice = try child_stdout.toOwnedSlice(allocator);
        defer allocator.free(child_stdout_slice);

        // Loop over each block of information corresponding to each different
        // display.
        var display_info_block_it = std.mem.splitSequence(u8, child_stdout_slice, "\n\n");
        display_info_blocks_loop: while (display_info_block_it.next()) |display_info_block_str| {

            // Create an iterator to loop over each line in the display
            // information block.
            var display_info_block_line_it = std.mem.splitScalar(u8, display_info_block_str, '\n');

            // The first line of the info block should be of the form "Display
            // N" where N is the number of the display the info block is for.
            const block_display_number: DisplayNumber = blk: {
                // First, get the first line of the block.
                // If the line doesn't exist, move onto the next block.
                if (display_info_block_line_it.next()) |display_number_line_str| {
                    // Second, get the words of the line in backwards order.
                    var it = std.mem.splitBackwardsScalar(u8, display_number_line_str, ' ');
                    // Third, try to parse the number from the last word
                    // (backwards order) of the line.
                    // If the parse fails, continue to the next block.
                    if (std.fmt.parseInt(DisplayNumber, it.first(), 10)) |display_num| {
                        break :blk display_num;
                    } else |_| {
                        continue :display_info_blocks_loop;
                    }
                }
                continue :display_info_blocks_loop;
            };

            // Parse the rest of the display information from this block if its
            // display number matches this display's number.
            if (block_display_number == self.display_number) {
                // Parse all the information for this display.
                key_value_lines_loop: while (display_info_block_line_it.next()) |display_info_line| {
                    // Each info line takes the form "key: value".
                    var kv_line_it = std.mem.splitScalar(u8, display_info_line, ':');

                    // Parse the key and value from the line.
                    var key = kv_line_it.next() orelse continue :key_value_lines_loop;
                    key = std.mem.trim(u8, key, " \n\t");
                    var value = kv_line_it.rest();
                    value = std.mem.trim(u8, value, " \n\t");

                    // --- Key = "I2C bus" ---
                    if (std.mem.eql(u8, key, "I2C bus")) {
                        var i2c_bus_it = std.mem.splitBackwardsScalar(u8, value, '-');

                        if (std.fmt.parseInt(u8, i2c_bus_it.first(), 10)) |i2c_bus| {
                            self.display_info.i2c_bus = i2c_bus;
                        } else |_| {}
                    }
                    // --- Key = "DRM connector" ---
                    else if (std.mem.eql(u8, key, "DRM connector")) {
                        strCpyTrunc(&self.display_info.drm_connector, value);
                    }
                    // --- Key = "drm_connector_id" ---
                    else if (std.mem.eql(u8, key, "drm_connector_id")) {
                        if (std.fmt.parseInt(u8, value, 10)) |drm_con_id| {
                            self.display_info.drm_connector_id = drm_con_id;
                        } else |_| {}
                    }
                    // --- Key = "Monitor" ---
                    else if (std.mem.eql(u8, key, "Monitor")) {
                        strCpyTrunc(&self.display_info.monitor, value);
                    }
                }

                // There is no need to parse any remaining blocks.
                break :display_info_blocks_loop;
            }
        }
    }

    inline fn ddcutilCommArgs(self: *Display, buf: []u8) [2][]const u8 {
        return .{
            if (self.display_info.i2c_bus == null) "-d" else "-b",
            std.fmt.bufPrint(buf, "{d}", .{self.display_info.i2c_bus orelse self.display_number}) catch unreachable,
        };
    }
};

pub const MemoryDisplay = struct {
    display_number: DisplayNumber,
    shm_display: SharedMemoryObject(Display),

    const SHM_DISPLAY_PATH_PREFIX: []const u8 = shared_memory.SHARED_MEMORY_PATH_PREFIX ++ "display-";
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
        const shm_display = try SharedMemoryObject(Display).init(shm_path, true);
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

pub fn getDisplayNumbers(tag: DisplayTag, allocator: Allocator) ![]DisplayNumber {
    switch (tag) {
        .number => {
            const display_numbers = try allocator.alloc(DisplayNumber, 1);
            display_numbers[0] = tag.number;
            return display_numbers;
        },
        .set => switch (tag.set) {
            .all => {
                const display_count = try SharedMemoryObject(DisplayNumber).init(shared_memory.SHARED_MEMORY_PATH_PREFIX ++ "display-count", true);
                if (display_count.created_new) {
                    // ----- CHILD PROCESS -----

                    // Create array lists to record stdout and stderr from the child
                    // process.
                    var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
                    defer child_stdout.deinit(allocator);
                    var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
                    defer child_stderr.deinit(allocator);

                    // Args to detect displays.
                    const argv = [_][]const u8{ "ddcutil", "detect", "--brief" };

                    // Set up the child process.
                    var child = std.process.Child.init(&argv, allocator);

                    // Collect child output.
                    child.stdout_behavior = .Pipe; // Record stdout
                    child.stderr_behavior = .Pipe; // Ignore stderr

                    // Exec the child.
                    try child.spawn();
                    try child.collectOutput(allocator, &child_stdout, &child_stderr, 16384);

                    // Wait for the child to complete.
                    _ = try child.wait();

                    // ----- PARSE RESULT -----

                    // Count the number of displays detected.
                    display_count.obj_ptr.* = @intCast(std.mem.count(u8, child_stdout.items, "Display "));
                }

                var display_numbers = try allocator.alloc(DisplayNumber, display_count.obj_ptr.*);
                for (0..display_count.obj_ptr.*) |i| {
                    display_numbers[i] = @intCast(i + 1);
                }

                return display_numbers;
            },
            .oled => {
                // Start with the list of all displays.
                var all_displays = try getDisplayNumbers(.{ .set = .all }, allocator);
                defer allocator.free(all_displays);

                var oled_index: usize = 0;
                for (all_displays) |d| {
                    var shm_display = try MemoryDisplay.init(d);
                    defer shm_display.deinit();

                    const lower_monitor_name = try std.ascii.allocLowerString(allocator, &shm_display.shm_display.obj_ptr.display_info.monitor);
                    defer allocator.free(lower_monitor_name);

                    if (std.mem.containsAtLeast(u8, lower_monitor_name, 1, "oled")) {
                        all_displays[oled_index] = d;
                        oled_index += 1;
                    }
                }

                // Resize the displays list to only contain the OLED displays.
                return try allocator.dupe(DisplayNumber, all_displays[0..oled_index]);
            },
        },
    }
}

// **=======================================**
// ||          <<<<< HELPERS >>>>>          ||
// **=======================================**

inline fn intDisplayLen(int_type: type) u64 {
    return std.math.ceil(log10(@as(f64, pow(usize, 2, @bitSizeOf(int_type)))));
}

inline fn strCpyTrunc(dest: []u8, source: []const u8) void {
    _ = std.fmt.bufPrint(dest, "{s}", .{source[0..@min(source.len, dest.len)]}) catch unreachable;
}
