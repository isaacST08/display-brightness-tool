const std = @import("std");
const argsParser = @import("args");
const display = @import("display");

const DisplayNumber = display.DisplayNumber;
const DisplayTag = display.DisplayTag;

const EXE_NAME: []const u8 = "displayctl";

// **=======================================**
// ||          <<<<< OPTIONS >>>>>          ||
// **=======================================**

pub const ActionOptions = enum {
    set,
    increase,
    decrease,
    save,
    restore,
    dim,
    undim,

    pub fn parse(x: []const u8) !@This() {
        return if (std.mem.eql(u8, x, "set"))
            .set
        else if (std.mem.eql(u8, x, "increase"))
            .increase
        else if (std.mem.eql(u8, x, "decrease"))
            .decrease
        else if (std.mem.eql(u8, x, "save"))
            .save
        else if (std.mem.eql(u8, x, "restore"))
            .restore
        else if (std.mem.eql(u8, x, "dim"))
            .dim
        else if (std.mem.eql(u8, x, "undim"))
            .undim
        else
            return error.InvalidInput;
    }
};

const Options = struct {
    display: DisplayTag = .{ .set = .all },
    @"clear-cache": bool = false,
    action: ?ActionOptions = null,
    value: ?i32 = null,
    verbose: bool = false,
    help: bool = false,

    pub const shorthands = .{
        .V = "verbose",
        .a = "action",
        .c = "clear-cache",
        .d = "display",
        .h = "help",
        .v = "value",
    };

    pub const wrap_len = 50;
    pub const meta = .{
        .usage_summary = "[options] [<action> [<value>]]",
        .full_text =
        \\Actions:
        \\  set <value>
        \\  increase <value>
        \\  decrease <value>
        \\  save
        \\  restore
        \\  dim <value>
        \\  undim
        ,
        .option_docs = .{
            .@"clear-cache" = "Clears the cache of display information.",
            .display = "Perform the action on this display or set of " ++
                "displays. Can either be one of [all, oled, non-oled] for " ++
                "that set of displays, or a display number. In addition, " ++
                "special displays are also supported, should program be run" ++
                " on the hyprland desktop environment, the display can also" ++
                " be `hypr-active` to only control the brightness of the " ++
                "currently active display. Default = all.",
            // .action = "The action to perform on the display(s). [set, increase, decrease, save, restore]",
            .action = "A secondary way to set the action. Will override the positional value.",
            .help = "Show this help.",
            // .value = "The value to provide to the action. Only has an effect on the `set`, `increase`, and `decrease` actions.",
            .value = "A secondary way to set the value for an action. Will override the positional value.",
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
    var options = argsParser.parseForCurrentProcess(
        Options,
        std.heap.page_allocator,
        .print,
    ) catch printHelp(null, 1, null, .{});

    // std.debug.print("Parsed options:\n", .{});
    // inline for (std.meta.fields(@TypeOf(options.options))) |fld| {
    //     std.debug.print("\t{s} = {any}\n", .{
    //         fld.name,
    //         @field(options.options, fld.name),
    //     });
    // }
    // std.debug.print("\nAll Parsed:\n{any}\n", .{options});

    // --- Args Validation ---

    // Parse the positional `action` arg if not set by a flag.
    if (options.positionals.len >= 1 and options.options.action == null) {
        if (ActionOptions.parse(options.positionals[0])) |action| {
            options.options.action = action;
        } else |_| {}
    }

    // Parse the positional `value` arg if not set by a flag.
    if (options.positionals.len >= 2 and options.options.value == null) {
        if (std.fmt.parseInt(@typeInfo(@FieldType(Options, "value")).optional.child, options.positionals[1], 10)) |val| {
            options.options.value = val;
        } else |_| {
            printHelp(
                options.executable_name,
                1,
                "Could not parse value: \"{s}\" is not a valid number.\n",
                .{options.positionals[1]},
            );
        }
    }
    // std.debug.print("\nModified All Parsed:\n{any}\n", .{options});

    // Some actions require a value be set, ensure it for those actions.
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
            // By default, dim by 40 marks.
            .dim => {
                if (options.options.value == null)
                    options.options.value = 40;
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
