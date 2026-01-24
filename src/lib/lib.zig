const std = @import("std");

const math = std.math;

const pow = math.pow;
const ceil = math.ceil;
const log10 = math.log10;
const Allocator = std.mem.Allocator;

/// Calculate the maximum number of character bytes required to display a type.
pub fn typeDisplayLen(comptime T: type) u64 {
    switch (@typeInfo(T)) {
        .int => {
            return ceil(log10(@as(f64, pow(usize, 2, @bitSizeOf(T)))));
        },

        .@"enum" => {
            var longest_enum_len: usize = 0;
            for (std.enums.values(T)) |et| {
                if (std.enums.tagName(T, et)) |tag_name| {
                    if (tag_name.len > longest_enum_len)
                        longest_enum_len = tag_name.len;
                }
            }
            return longest_enum_len;
        },

        else => {
            @compileError("Type display length calculation not implemented yet.\n");
        },
    }
}

/// Run a command and receive the output from stdout as an owned slice.
///
/// Parameters
/// ----------
/// `allocator` : Allocator | The allocator that owns the returned slice.
/// `argv` : [][]const u8 | An array of strings that will be the arguments (and
///     the command itself) for the command.
/// `max_output_bytes` : usize | The maximum amount of bytes that stdout will
///     be allowed to produce.
pub fn runCommand(allocator: Allocator, argv: anytype, max_output_bytes: usize) ![]const u8 {
    // Create array lists to record stdout and stderr from the child process.
    var child_stdout = try std.ArrayList(u8).initCapacity(allocator, 512);
    defer child_stdout.deinit(allocator);
    var child_stderr = try std.ArrayList(u8).initCapacity(allocator, 8);
    defer child_stderr.deinit(allocator);

    // Set up the child process.
    var child = std.process.Child.init(&argv, allocator);

    // Collect child output.
    child.stdout_behavior = .Pipe; // Record stdout
    child.stderr_behavior = .Pipe; // Ignore stderr

    // Exec the child.
    try child.spawn();
    try child.collectOutput(
        allocator,
        &child_stdout,
        &child_stderr,
        max_output_bytes,
    );

    // Wait for the child to complete.
    _ = try child.wait();

    // Convert the stdout array list to a slice.
    const child_stdout_slice = try child_stdout.toOwnedSlice(allocator);
    return child_stdout_slice;
}
