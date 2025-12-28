const std = @import("std");

pub fn build(b: *std.Build) void {
    // const optimize = b.standardOptimizeOption(.{});
    const optimize = .ReleaseSafe;
    const exe = b.addExecutable(.{
        .name = "display-brightness-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = b.graph.host,
        }),
    });

    exe.linkLibC();

    b.default_step.dependOn(&exe.step);

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
