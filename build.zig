const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // ----- Main Executable -----
    const exe = b.addExecutable(.{
        .name = "display-brightness-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    exe.linkLibC();

    // ----- Dependencies -----
    exe.root_module.addImport("args", b.dependency("args", .{ .target = target, .optimize = optimize }).module("args"));

    // ----- Install -----
    b.default_step.dependOn(&exe.step);
    b.installArtifact(exe);

    // ----- Run Step -----
    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}
