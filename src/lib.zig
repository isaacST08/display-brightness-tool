const std = @import("std");

const math = std.math;

const pow = math.pow;
const ceil = math.ceil;
const log10 = math.log10;

// inline fn intDisplayLen(T: type) u64 {
//     return std.math.ceil(log10(@as(f64, pow(usize, 2, @bitSizeOf(T)))));
// }

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
