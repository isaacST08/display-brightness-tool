const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    // **=======================================**
    // ||          <<<<< MODULES >>>>>          ||
    // **=======================================**

    // ----- LIB -----
    const mod_lib = b.addModule("lib", .{
        .root_source_file = b.path("src/lib/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ----- SEMAPHORE -----
    const mod_semaphore = b.addModule("semaphore", .{
        .root_source_file = b.path("src/semaphore/semaphore.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ----- SHARED MEMORY -----
    const mod_shared_memory = b.addModule("shared_memory", .{
        .root_source_file = b.path("src/shared_memory/shared_memory.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ----- DISPLAY -----
    const mod_display = b.addModule("display", .{
        .root_source_file = b.path("src/display/display.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_display.addImport("lib", mod_lib);
    mod_display.addImport("semaphore", mod_semaphore);
    mod_display.addImport("shared_memory", mod_shared_memory);

    // **===============================================**
    // ||          <<<<< MAIN EXECUTABLE >>>>>          ||
    // **===============================================**

    const exe = b.addExecutable(.{
        .name = "display-brightness-tool",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    exe.linkLibC();
    exe.root_module.addImport("lib", mod_lib);
    exe.root_module.addImport("semaphore", mod_semaphore);
    exe.root_module.addImport("shared_memory", mod_shared_memory);
    exe.root_module.addImport("display", mod_display);

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
