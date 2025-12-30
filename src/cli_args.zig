const std = @import("std");
const argsParser = @import("args");

const DisplayNumber = @import("display.zig").DisplayNumber;

const EXE_NAME: []const u8 = "displayctl";

// **=======================================**
// ||          <<<<< OPTIONS >>>>>          ||
// **=======================================**

const Options = struct {
    action: ?enum { set, increase, decrease, save, restore } = null,
    value: ?i32 = null,
    @"display-number": ?DisplayNumber = null,
    @"display-bus": ?u32 = null,
    @"display-set": ?enum { oled, all } = null,
    @"clear-queue": bool = false,
    verbose: bool = false,
    help: bool = false,

    pub const shorthands = .{
        .V = "verbose",
        .a = "action",
        .b = "display-bus",
        .c = "clear-queue",
        .h = "help",
        .n = "display-number",
        .s = "display-set",
        .v = "value",
    };

    pub const meta = .{
        .option_docs = .{
            .@"clear-queue" = "Clear the action queue.",
            .@"display-bus" = "Perform the action only on the display at this I2C bus.",
            .@"display-number" = "Perform the action only on the display identified by this number.",
            .@"display-set" = "Perform the action on this set of displays.",
            .action = "The action to perform on the display(s). [set, increase, decrease, save, restore]",
            .help = "help help",
            .value = "The value to provide to the action. Only has an effect on the `set`, `increase`, and `decrease` actions.",
            .verbose = "Print additional runtime info.",
        },
    };
};

// **============================================**
// ||          <<<<< ARGS PARSING >>>>>          ||
// **============================================**

fn printHelp(name: ?[]const u8, exit_code: u8, comptime err_msg: ?[]const u8, err_msg_args: anytype) noreturn {
    // Get the printer for output (either stderr or stdout).
    var writer_buf: [128]u8 = undefined;
    var stderr_writer_buf: [128]u8 = undefined;
    var stderr = std.fs.File.stderr().writer(&stderr_writer_buf);
    var output = (if (exit_code == 0) std.fs.File.stdout() else std.fs.File.stderr()).writer(&writer_buf);

    // Print the error message if provided.
    if (err_msg) |em| {
        stderr.interface.print(em, err_msg_args) catch unreachable;
        stderr.interface.flush() catch unreachable;
    }

    // If we are not exiting gracefully, there is probably an error message
    // above this so give a line of space to separate it from the help/usage
    // message.
    if (exit_code != 0)
        output.interface.print("\n", .{}) catch unreachable;

    // Print the help message.
    argsParser.printHelp(Options, name orelse EXE_NAME, &output.interface) catch (stderr.interface.print("There was an error printing help.\n", .{}) catch {});

    // Flush the output before we exit.
    output.interface.flush() catch unreachable;

    // Exit.
    std.process.exit(exit_code);
}

pub fn parseArgs() argsParser.ParseArgsResult(Options, null) {
    const options = argsParser.parseForCurrentProcess(
        Options,
        std.heap.page_allocator,
        .print,
    ) catch printHelp(null, 1, null, .{});

    std.debug.print("Parsed options:\n", .{});
    inline for (std.meta.fields(@TypeOf(options.options))) |fld| {
        std.debug.print("\t{s} = {any}\n", .{
            fld.name,
            @field(options.options, fld.name),
        });
    }

    // --- Args Validation ---
    if (options.options.action) |action| {
        switch (action) {
            // Ensure "value" is set.
            .set, .increase, .decrease => {
                if (options.options.value == null) {
                    printHelp(
                        options.executable_name,
                        1,
                        "The \"{?s}\" action requires that a value is set.\n",
                        .{std.enums.tagName(@TypeOf(action), action)},
                    );
                }
            },
            else => {},
        }
    }

    // --- Print Help ---
    if (options.options.help) {
        printHelp(options.executable_name, 0, null, .{});
    }

    return options;
}
