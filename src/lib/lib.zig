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
/// `io` : Io | The IO interface to use.
/// `argv` : [][]const u8 | An array of strings that will be the arguments (and
///     the command itself) for the command.
pub fn runCommand(allocator: Allocator, io: std.Io, argv: anytype) ![]const u8 {
    // Run the command and return the result.
    const results = try std.process.run(allocator, io, .{ .argv = &argv });
    allocator.free(results.stderr);

    return results.stdout;
}
