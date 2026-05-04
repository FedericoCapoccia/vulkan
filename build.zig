const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("vulkan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
    });

    b.installArtifact(exe);

    const exe_c = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
    });

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&exe_c.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
