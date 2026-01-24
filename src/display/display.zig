const std = @import("std");
const lib = @import("lib.zig");
const semaphore = @import("semaphore/semaphore.zig");
const shared_memory = @import("shared_memory.zig");

const enums = std.enums;
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;

const Allocator = mem.Allocator;
const Atomic = std.atomic.Value;
const QueueingSemaphore = semaphore.QueueingSemaphore;
const SharedMemoryObject = shared_memory.SharedMemoryObject;

const pow = math.pow;
const ceil = math.ceil;
const log10 = math.log10;
const runCommand = lib.runCommand;

pub const DisplayNumber = u8;
pub const I2CBusNumber = u10;

/// An unique identifier or set identifier for a display.
/// Can either be a number representing a single display, or a enum that
/// corresponds to a set of displays.
pub const DisplayTag = union((enum { set, number, special })) {
    set: enum { all, oled, non_oled },
    number: DisplayNumber,
    special: enum { hypr_active },

    pub fn parse(x: []const u8) !@This() {
        return if (mem.eql(u8, x, "all"))
            .{ .set = .all }
        else if (mem.eql(u8, x, "oled"))
            .{ .set = .oled }
        else if (mem.eql(u8, x, "non-oled") or mem.eql(u8, x, "non_oled"))
            .{ .set = .non_oled }
        else if (mem.eql(u8, x, "hypr-active") or mem.eql(u8, x, "hypr_active"))
            .{ .special = .hypr_active }
        else if (fmt.parseInt(DisplayNumber, x, 10)) |num|
            .{ .number = num }
        else |err|
            err;
    }
};

pub const DisplayTechnologyType = enum(u8) {
    CRT_shadow_mast = 0x01,
    CRT_aperture_grill = 0x02,
    LCD = 0x03,
    LCos = 0x04,
    Plasma = 0x05,
    OLED = 0x06,
    EL = 0x07,
    MEM = 0x08,
};

pub const DisplayInfo = struct {
    i2c_bus: ?I2CBusNumber = null,
    drm_connector: [256]u8 = .{0} ** 256,
    drm_connector_id: ?u32 = null,
    monitor: [256]u8 = .{0} ** 256,
    display_technology: ?DisplayTechnologyType = null,
};

pub const Display = struct {
    /// The display number in the system.
    display_number: Atomic(DisplayNumber),

    /// Information related to the display.
    display_info: DisplayInfo = .{},

    /// The current brightness of the display.
    brightness: Atomic(u32) = .init(0),

    /// The working brightness used for brightness calculations before it is
    /// sent to the display.
    working_brightness: u32 = 0,
    working_brightness_sem: QueueingSemaphore,

    /// The maximum brightness the display can be set to.
    max_brightness: Atomic(u32) = .init(100),

    /// The time in seconds relative to the epoch when the brightness of the
    /// display was last updated.
    last_updated: Atomic(i64) = .init(0),

    /// A saved brightness value that can be restored to later.
    saved_brightness: Atomic(u32) = .init(0),

    /// A saved brightness value that records the brightness of the display
    /// before being dimmed.
    /// If null, then the display is not currently dimmed.
    pre_dim_brightness: ?u32 = null,
    pre_dim_brightness_sem: QueueingSemaphore,

    /// Semaphore to protect access to the physical display.
    display_sem: QueueingSemaphore,

    /// Semaphore used when syncing combined commands with the physical
    /// display.
    /// Used to ensure that all commands are actually sent to the display.
    sync_sem: QueueingSemaphore,

    allocator: Allocator,

    const BRIGHNESS_VCP_CODE = 0x10;

    pub fn init(display_number: DisplayNumber, display_detect_info: ?[]const u8, allocator: Allocator) !Display {
        var self = Display{
            .display_number = .init(display_number),
            .display_sem = try .init(1),
            .sync_sem = try .init(1),
            .working_brightness_sem = try .init(1),
            .pre_dim_brightness_sem = try .init(1),
            .allocator = allocator,
        };
        try self.updateInfo(display_detect_info);
        try self.updateBrightness();
        return self;
    }

    /// Send the current brightness stored in `working_brightness` to the display.
    ///
    /// Will not exceed setting the brightness above the max brightness of the
    /// display.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    fn sendBrightness(self: *Display) !void {
        // Used to convert ints (<=u32) to strings.
        var brightness_buf: [lib.typeDisplayLen(u32)]u8 = undefined;
        var display_comm_buf: [@max(lib.typeDisplayLen(DisplayNumber), lib.typeDisplayLen(I2CBusNumber))]u8 = undefined;

        // Cap the brightness to a safe range for the display.
        const capped_brightness: u32 = blk: {
            try self.working_brightness_sem.wait();
            defer self.working_brightness_sem.post();

            break :blk @min(self.working_brightness, self.max_brightness.load(.seq_cst));
        };

        // Create the args to change the brightness using ddcutil.
        const argv = [_][]const u8{
            "ddcutil",

            // Set command to the VCP brightness code.
            "setvcp",
            std.fmt.comptimePrint("{x}", .{BRIGHNESS_VCP_CODE}),

            // Brightness
            try std.fmt.bufPrint(&brightness_buf, "{d}", .{capped_brightness}),
        }
            // Display number or I2C bus.
            ++ ddcutilCommArgs(self, &display_comm_buf);

        // Execute the process.
        var child = std.process.Child.init(&argv, self.allocator);
        try child.spawn();
        _ = try child.wait();

        // Update the brightness of this display object.
        // Assumes the brightness of the physical display was set successfully.
        self.brightness.store(capped_brightness, .seq_cst);
    }

    /// Sets the brightness of the display to `brightness`.
    ///
    /// Batches brightness commands together so that only one representative
    /// thread communicates with the physical display on behalf of the other
    /// threads and their "requests".
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    /// `brightness` : u32 | The brightness to set the display to.
    pub fn setBrightness(self: *Display, brightness: u32) !void {
        {
            try self.working_brightness_sem.wait();
            defer self.working_brightness_sem.post();

            self.working_brightness = @min(brightness, self.max_brightness.load(.seq_cst));
        }

        try self._setBrightness();
    }

    /// Sets the brightness of the display to the current value of `working_brightness`.
    ///
    /// Will not exceed setting the brightness above the max brightness of the
    /// display.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    fn _setBrightness(self: *Display) !void {
        // Try and acquire the lock for the physical display.
        const display_sem_result: bool = blk: {
            self.sync_sem.wait() catch break :blk false;
            defer self.sync_sem.post();
            break :blk self.display_sem.tryWait();
        };

        // If the lock was acquired, it is now this owning thread's
        // responsibility converse with the physical display.
        //
        // Otherwise, the thread should have already modified the
        // `working_brightness` variable and passes of responsibility to the
        // display representative thread .
        if (display_sem_result) {

            // Send working brightness to display.
            try self.sendBrightness();

            // Acquire the sync lock so that no more threads can modify the
            // `working_brightness` while the sync is occurring.
            // This informs those threads that they (one of them) will need
            // to become the new representative thread.
            self.sync_sem.wait() catch try self.sync_sem.wait();
            defer self.sync_sem.post();

            // Release the lock on the display at the end of the sync but
            // before release the sync lock.
            // This allows for the next command thread to also become the
            // next representative thread.
            defer self.display_sem.post();

            // If there are no more pending brightness commands, perform
            // one last send (this is the sync).
            if (self.sync_sem.count()) |e| {
                if (e == 0) try self.sendBrightness();
            } else |_| {}
        }
    }

    /// Increases the brightness of the display by the amount of
    /// `brightness_change`.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    /// `brightness_change` : u32 | The relative brightness to increase the display brightness by.
    pub fn increaseBrightness(self: *Display, brightness_change: i32) !void {
        {
            try self.working_brightness_sem.wait();
            defer self.working_brightness_sem.post();

            self.working_brightness = @min(
                @as(u32, @intCast(@max(
                    @as(i64, self.working_brightness) + @as(i64, brightness_change),
                    0,
                ))),
                self.max_brightness.load(.seq_cst),
            );
        }

        try self._setBrightness();
    }

    /// Decreases the brightness of the display by the amount of
    /// `brightness_change`.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    /// `brightness_change` : u32 | The relative brightness to decrease the display brightness by.
    pub fn decreaseBrightness(self: *Display, brightness_change: i32) !void {
        try self.increaseBrightness(-1 * brightness_change);
    }

    /// Saves the current brightness of the display.
    pub fn saveBrightness(self: *Display) !void {
        self.saved_brightness.store(self.brightness.load(.seq_cst), .seq_cst);
    }

    /// Restores the brightness of the display to the currently saved
    /// brightness value.
    pub fn restoreBrightness(self: *Display) !void {
        {
            try self.working_brightness_sem.wait();
            defer self.working_brightness_sem.post();

            self.working_brightness = self.saved_brightness.load(.seq_cst);
        }

        try self._setBrightness();
    }

    /// Saves the current brightness and dims the display by the requested
    /// amount.
    ///
    /// If the display is currently dimmed, then the display will be dimmed
    /// further but the save value will not be altered.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to set the brightness of.
    /// `dim_value` : u32 | The amount to dim the display by.
    pub fn dimBrightness(self: *Display, dim_value: u32) !void {
        {
            try self.pre_dim_brightness_sem.wait();
            defer self.pre_dim_brightness_sem.post();

            if (self.pre_dim_brightness == null)
                self.pre_dim_brightness = self.brightness.load(.seq_cst);
        }

        try self.decreaseBrightness(@intCast(dim_value));
    }

    /// Restores the brightness of the display to the brightness it was at
    /// before it was dimmed.
    pub fn undimBrightness(self: *Display) !void {
        const pdb = blk: {
            try self.pre_dim_brightness_sem.wait();
            defer self.pre_dim_brightness_sem.post();

            if (self.pre_dim_brightness) |b| {
                try self.working_brightness_sem.wait();
                defer self.working_brightness_sem.post();

                self.working_brightness = b;
            }

            break :blk self.pre_dim_brightness;
        };

        // Set the brightness only if the display was actually dimmed.
        if (pdb) |_| {
            try self._setBrightness();
        }
    }

    /// Query the display for it's current brightness stats and returns the
    /// retrieved `brightness` and `max_brightness` values.
    pub fn queryDisplayBrightness(self: *Display) !struct { brightness: u32, max_brightness: u32 } {
        // Perform a `getvcp` command.
        const child_stdout_slice = try self.getvcp(BRIGHNESS_VCP_CODE, .{}, 512);
        defer self.allocator.free(child_stdout_slice);

        // Variables to store the parsed values from the return value.
        var parsed_brightness: u32 = 0;
        var parsed_max_brightness: u32 = 0;

        // Parse display state information stdout from the child.
        var it = mem.splitScalar(u8, child_stdout_slice, ':');
        _ = it.next(); // Discard the header.
        it = mem.splitScalar(u8, it.rest(), ',');
        while (it.next()) |x| {
            var param_it = mem.splitScalar(u8, x, '=');

            // Parse the name and value for this param.
            const param_name = mem.trim(u8, param_it.next() orelse continue, " \t\n");
            const param_value =
                fmt.parseInt(u32, mem.trim(u8, param_it.next() orelse continue, " \t\n"), 10) catch continue;

            // Set the appropriate values.
            if (mem.eql(u8, param_name, "current value"))
                parsed_brightness = param_value
            else if (mem.eql(u8, param_name, "max value"))
                parsed_max_brightness = param_value;
        }

        return .{
            .brightness = parsed_brightness,
            .max_brightness = parsed_max_brightness,
        };
    }

    /// Query the display for it's current brightness stats and update the
    /// local values to match.
    pub fn updateBrightness(self: *Display) !void {
        const query_result = try self.queryDisplayBrightness();

        self.brightness.store(query_result.brightness, .seq_cst);
        self.max_brightness.store(query_result.max_brightness, .seq_cst);

        // Match the working brightness to the queried brightness.
        {
            try self.working_brightness_sem.wait();
            defer self.working_brightness_sem.post();

            self.working_brightness = query_result.brightness;
        }

        // Record the update time stamp.
        self.last_updated.store(std.time.timestamp(), .seq_cst);
    }

    /// Updates the info for this display.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to update the information of.
    /// `detect_info` : ?[]const u8 | If not null, will be used as the slice in
    ///     which the info is parsed from. If null, then will run a display
    ///     detection on its own.
    pub fn updateInfo(self: *Display, detect_info: ?[]const u8) !void {
        // Detect displays and get the info.
        const child_stdout_slice = detect_info orelse try getDisplayDetectionSlice(self.allocator);
        defer if (detect_info == null) self.allocator.free(child_stdout_slice);

        // Loop over each block of information corresponding to each different
        // display.
        var display_info_block_it = mem.splitSequence(u8, child_stdout_slice, "\n\n");
        display_info_blocks_loop: while (display_info_block_it.next()) |display_info_block_str| {

            // Create an iterator to loop over each line in the display
            // information block.
            var display_info_block_line_it = mem.splitScalar(u8, display_info_block_str, '\n');

            // The first line of the info block should be of the form "Display
            // N" where N is the number of the display the info block is for.
            const block_display_number: DisplayNumber = blk: {

                // First, get the first line of the block.
                // If the line doesn't exist, move onto the next block.
                if (display_info_block_line_it.next()) |display_number_line_str| {

                    // Second, get the words of the line in backwards order.
                    var it = mem.splitBackwardsScalar(u8, display_number_line_str, ' ');

                    // Third, try to parse the number from the last word
                    // (backwards order) of the line.
                    // If the parse fails, continue to the next block.
                    if (fmt.parseInt(DisplayNumber, it.first(), 10)) |display_num| {
                        break :blk display_num;
                    } else |_| {
                        continue :display_info_blocks_loop;
                    }
                }

                continue :display_info_blocks_loop;
            };

            // Parse the rest of the display information from this block if its
            // display number matches this display's number.
            if (block_display_number == self.display_number.load(.seq_cst)) {
                // Parse all the information for this display.
                key_value_lines_loop: while (display_info_block_line_it.next()) |display_info_line| {
                    // Each info line takes the form "key: value".
                    var kv_line_it = mem.splitScalar(u8, display_info_line, ':');

                    // Parse the key and value from the line.
                    const key = mem.trim(u8, kv_line_it.next() orelse continue :key_value_lines_loop, " \n\t");
                    const value = mem.trim(u8, kv_line_it.rest(), " \n\t");

                    // --- Key = "I2C bus" ---
                    if (mem.eql(u8, key, "I2C bus")) {
                        var i2c_bus_it = mem.splitBackwardsScalar(u8, value, '-');

                        if (fmt.parseInt(u8, i2c_bus_it.first(), 10)) |i2c_bus| {
                            self.display_info.i2c_bus = i2c_bus;
                        } else |_| {}
                    }
                    // --- Key = "DRM connector" ---
                    else if (mem.eql(u8, key, "DRM connector")) {
                        strCpyTrunc(&self.display_info.drm_connector, value);
                    }
                    // --- Key = "drm_connector_id" ---
                    else if (mem.eql(u8, key, "drm_connector_id")) {
                        if (fmt.parseInt(u8, value, 10)) |drm_con_id| {
                            self.display_info.drm_connector_id = drm_con_id;
                        } else |_| {}
                    }
                    // --- Key = "Monitor" ---
                    else if (mem.eql(u8, key, "Monitor")) {
                        strCpyTrunc(&self.display_info.monitor, value);
                    }
                }

                // There is no need to parse any remaining blocks.
                break :display_info_blocks_loop;
            }
        }

        // ----- Parse Display Type -----
        const lower_monitor_name = try std.ascii.allocLowerString(self.allocator, &self.display_info.monitor);
        defer self.allocator.free(lower_monitor_name);

        // If the monitor title contains the term "OLED" assume it is an OLED
        // display.
        // (Some manufacturers forget to set the display technology type but do
        // put OLED in the name.)
        if (mem.containsAtLeast(u8, lower_monitor_name, 1, "oled")) {
            self.display_info.display_technology = .OLED;
        }
        // Otherwise, query the display for it's type.
        else {
            // // Query the display for it's technology type.
            const display_type_raw = try self.getvcp(0xb6, [_][]const u8{"--brief"}, 128);
            defer self.allocator.free(display_type_raw);

            // Parse the result and apply it if it is an accepted value.
            var display_type_raw_it = mem.splitBackwardsScalar(u8, mem.trim(u8, display_type_raw, "\n"), ' ');
            const display_type_parsed_int = try fmt.parseInt(usize, mem.trimStart(u8, display_type_raw_it.first(), "x"), 16);
            if (enums.fromInt(DisplayTechnologyType, display_type_parsed_int)) |display_type_parsed| {
                self.display_info.display_technology = display_type_parsed;
            }
        }
    }

    /// Constructs the flags for a ddcutil command that are used to determine
    /// which display to operate on and how.
    ///
    /// If an I2C bus is available for the given display, that is used,
    /// otherwise, the display number is use.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to query.
    /// `buf` : []u8 | The buffer used to print the string form of the display
    ///     number or the I2C bus number into.
    ///
    /// Returns
    /// -------
    /// An array of 2 strings, the first is the flag, the second is the
    /// appropriate value.
    inline fn ddcutilCommArgs(self: *Display, buf: []u8) [2][]const u8 {
        return .{
            if (self.display_info.i2c_bus == null) "-d" else "-b",
            fmt.bufPrint(buf, "{d}", .{self.display_info.i2c_bus orelse self.display_number.load(.seq_cst)}) catch unreachable,
        };
    }

    /// Queries a display with a given VCP code and returns the result as a
    /// char array.
    ///
    /// The returned char array is owned by the display object allocator and
    /// must be freed.
    ///
    /// Parameters
    /// ----------
    /// `self` : *Display | The display to query.
    /// `vcp_code` : comptime usize | The VCP code to use for the query.
    /// `extra_argv` : comptime [][]const u8 | A comptime array of extra
    ///     arguments to pass to the VCP get command.
    /// `max_output_bytes` : usize | The maximum number of bytes (chars) that
    ///     can be collected from the output of the getvcp command.
    ///
    /// Returns
    /// -------
    /// The output string from running the getvcp command.
    fn getvcp(self: *Display, comptime vcp_code: usize, extra_argv: anytype, max_output_bytes: usize) ![]const u8 {
        var display_id_buf: [@max(lib.typeDisplayLen(DisplayNumber), lib.typeDisplayLen(I2CBusNumber))]u8 = undefined;

        const result: []const u8 = try runCommand(
            self.allocator,
            .{ "ddcutil", "getvcp", fmt.comptimePrint("{x}", .{vcp_code}) } ++
                self.ddcutilCommArgs(&display_id_buf) ++
                extra_argv,
            max_output_bytes,
        );

        return result;
    }
};

pub const MemoryDisplay = struct {
    display_number: DisplayNumber,
    shm_display: SharedMemoryObject(Display),

    const SHM_DISPLAY_PATH_PREFIX: []const u8 = shared_memory.SHARED_MEMORY_PATH_PREFIX ++ "display-";
    const SHM_DISPLAY_NUM_STR_MAX_LEN: usize = lib.typeDisplayLen(DisplayNumber);
    const SHM_DISPLAY_PATH_LEN: usize = (SHM_DISPLAY_PATH_PREFIX.len + SHM_DISPLAY_NUM_STR_MAX_LEN + 1);

    pub fn init(display_number: DisplayNumber, display_detect_info: ?[]const u8, allocator: Allocator) !MemoryDisplay {

        // ----- Shared Memory Path -----

        // Create a buffer for the shared memory path.
        var shm_path_buf: [SHM_DISPLAY_PATH_LEN]u8 = undefined;

        // Construct the shared memory path for this display.
        const shm_path = (fmt.bufPrint(
            &shm_path_buf,
            fmt.comptimePrint("{{s}}{{d:0>{d}}}", .{SHM_DISPLAY_NUM_STR_MAX_LEN}),
            .{ SHM_DISPLAY_PATH_PREFIX, display_number },
        ) catch unreachable);

        // ----- Shared Memory Display -----

        // Get/Create the shared memory of the display.
        const shm_display = try SharedMemoryObject(Display).init(shm_path, true);
        if (shm_display.created_new) {
            shm_display.obj_ptr.* = try Display.init(display_number, display_detect_info, allocator);
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

pub const DisplaySet = struct {
    tag: DisplayTag,
    allocator: Allocator,
    display_count: DisplayNumber,
    shm_display_numbers: ?SharedMemoryObject([math.maxInt(DisplayNumber)]?DisplayNumber) = null,
    shm_displays: []MemoryDisplay,

    pub fn init(tag: DisplayTag, allocator: Allocator) !DisplaySet {
        tag_sw: switch (tag) {
            .set => |value| {

                // ----- Get/Create Shared Memory -----

                // --- Shared Memory Path ---

                const shm_path_prefix: []const u8 =
                    comptime shared_memory.SHARED_MEMORY_PATH_PREFIX ++
                    "display-set-";

                // Create a buffer for the shared memory path.
                // This buffer has room for the prefix and room for a suffix as
                // the longest tag name of a display set enum.
                var shm_path_buf: [shm_path_prefix.len + lib.typeDisplayLen(@TypeOf(value)) + 1]u8 = undefined;

                // Construct the shared memory path for this display.
                const shm_path = (fmt.bufPrint(
                    &shm_path_buf,
                    "{s}{s}",
                    .{ shm_path_prefix, enums.tagName(@TypeOf(tag.set), tag.set) orelse "" },
                ) catch unreachable);

                // --- Shared Memory ---

                // Get/Create the shared memory of the display.
                var self = DisplaySet{
                    .tag = tag,
                    .allocator = allocator,
                    .display_count = 0,
                    .shm_display_numbers = try .init(shm_path, true),
                    .shm_displays = undefined,
                };

                // Create an array list to store the memory displays that
                // belong to the displays in the set.
                var shm_displays_arr_list = blk: {
                    var al = std.ArrayList(MemoryDisplay).empty;
                    break :blk al.toManaged(allocator);
                };
                defer shm_displays_arr_list.deinit();

                // If the shared memory was newly created, it must have it's
                // contents initialized.
                if (self.shm_display_numbers) |*shm_display_numbers| {
                    if (shm_display_numbers.created_new) {

                        // Detect what displays are available.
                        const display_detect_info = try getDisplayDetectionSlice(allocator);
                        defer allocator.free(display_detect_info);

                        // Count the number of displays detected.
                        const total_display_count = std.mem.count(u8, display_detect_info, "Display ");

                        // Get the members of the display set.
                        for (0..total_display_count) |i| {
                            var shm_display = try MemoryDisplay.init(@intCast(i + 1), display_detect_info, allocator);

                            switch (value) {
                                // Add all displays to the set.
                                .all => {
                                    try shm_displays_arr_list.append(shm_display);
                                    self.display_count += 1;
                                },
                                // Add only OLED displays to the set.
                                .oled => {
                                    if (shm_display.shm_display.obj_ptr.display_info.display_technology == .OLED) {
                                        try shm_displays_arr_list.append(shm_display);
                                        self.display_count += 1;
                                    } else {
                                        shm_display.deinit();
                                    }
                                },
                                .non_oled => {
                                    if (shm_display.shm_display.obj_ptr.display_info.display_technology != .OLED) {
                                        try shm_displays_arr_list.append(shm_display);
                                        self.display_count += 1;
                                    } else {
                                        shm_display.deinit();
                                    }
                                },
                            }
                        }

                        // Move the array list contents to an owned slice.
                        self.shm_displays = try shm_displays_arr_list.toOwnedSlice();

                        // Save the set of display numbers.
                        shm_display_numbers.obj_ptr.* = .{null} ** std.math.maxInt(DisplayNumber);
                        for (self.shm_displays, 0..) |shm_dis, i| {
                            shm_display_numbers.obj_ptr[i] = shm_dis.display_number;
                        }
                    } else {

                        // Count the number of displays that will be in the set and
                        // initialize those displays.
                        var i: usize = 0;
                        while (shm_display_numbers.obj_ptr[i]) |display_num| : (i += 1) {
                            self.display_count += 1;
                            try shm_displays_arr_list.append(try MemoryDisplay.init(@intCast(display_num), null, allocator));
                        }

                        // Convert the array list of memory displays to an array.
                        self.shm_displays = try shm_displays_arr_list.toOwnedSlice();
                    }
                } else {
                    unreachable;
                }

                return self;
            },
            .number => |display_number| {
                var shm_displays = try allocator.alloc(MemoryDisplay, 1);
                shm_displays[0] = try MemoryDisplay.init(display_number, null, allocator);

                return .{
                    .tag = tag,
                    .allocator = allocator,
                    .display_count = 1,
                    .shm_displays = shm_displays,
                };
            },
            .special => |special_display_option| {
                switch (special_display_option) {
                    .hypr_active => {
                        // Try to run the command to detect the active display
                        // on hyprland.
                        if (runCommand(allocator, [_][]const u8{ "hyprctl", "activeworkspace" }, 16384)) |aw_raw| {
                            var lines_it = std.mem.splitScalar(u8, aw_raw, '\n');

                            // Go through each line of the result looking for
                            // "monitorID: N".
                            while (lines_it.next()) |line| {
                                var kv_it = std.mem.splitScalar(u8, line, ':');
                                const key: []const u8 = std.mem.trim(u8, kv_it.next() orelse continue, " \t\n");
                                const val: []const u8 = std.mem.trim(u8, kv_it.rest(), " \t\n");

                                // If/when the monitor ID is found, create a
                                // single-display display set using it.
                                // Note: hyprland displays are 0 indexed
                                // whereas ddcutil displays are 1 indexed, so
                                // we increment by 1.
                                if (std.mem.eql(u8, key, "monitorID")) {
                                    if (std.fmt.parseInt(DisplayNumber, val, 10)) |display_num| {
                                        continue :tag_sw .{ .number = display_num + 1 };
                                    } else |_| {}
                                }
                            }
                        }
                        // If the hyprctl command fails, print the failure
                        // message and return an empty display set.
                        else |_| {}

                        var stderr_buf: [128]u8 = undefined;
                        var stderr = std.fs.File.stderr().writer(&stderr_buf).interface;
                        stderr.print("Failed to detect hyprland active workspace.\n", .{}) catch {};

                        return .{
                            .tag = tag,
                            .allocator = allocator,
                            .display_count = 0,
                            .shm_displays = try allocator.alloc(MemoryDisplay, 0),
                        };
                    },
                }
            },
        }
    }

    pub fn deinit(self: *DisplaySet) void {
        if (self.shm_display_numbers) |*sdn|
            sdn.deinit();
        for (0..self.display_count) |i| {
            self.shm_displays[i].deinit();
        }
        self.allocator.free(self.shm_displays);
    }
};

// **=======================================**
// ||          <<<<< HELPERS >>>>>          ||
// **=======================================**

inline fn strCpyTrunc(dest: []u8, source: []const u8) void {
    _ = std.fmt.bufPrint(dest, "{s}", .{source[0..@min(source.len, dest.len)]}) catch unreachable;
}

fn getDisplayDetectionSlice(allocator: Allocator) ![]const u8 {
    return runCommand(allocator, [_][]const u8{ "ddcutil", "detect", "--brief" }, 16384);
}
