const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");

    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    vk_generate_cmd.addFileArg(registry);

    const vulkan_zig = b.addModule("vulkan-zig", .{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
    });

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
        .x11 = false,
        .wayland = true,
    });

    const zglfw_mod = zglfw.module("root");
    zglfw_mod.addImport("vulkan", vulkan_zig);

    const mod = b.addModule("vulkan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("vulkan", vulkan_zig);
    mod.addImport("zglfw", zglfw_mod);
    if (target.result.os.tag != .emscripten) {
        mod.linkLibrary(zglfw.artifact("glfw"));
    }

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
    });

    b.installArtifact(exe);

    const exe_c = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
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
