const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const shaders_step = b.step("shaders", "Compile Slang shaders");

    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");

    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    vk_generate_cmd.addFileArg(registry);

    const vulkan_zig = b.addModule("vulkan-zig", .{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
        .target = target,
        .optimize = optimize,
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
    run_cmd.step.dependOn(shaders_step);
    run_cmd.step.dependOn(b.getInstallStep());

    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&exe_c.step);
    addShaderCompileSteps(b, shaders_step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn addShaderCompileSteps(b: *std.Build, shaders_step: *std.Build.Step) void {
    const dir = std.Io.Dir.cwd().openDir(b.graph.io, "resources/shaders", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => @panic("failed to open resources/shaders"),
    };
    defer dir.close(b.graph.io);

    var iterator = dir.iterate();
    while (iterator.next(b.graph.io) catch @panic("failed to iterate resources/shaders")) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".slang")) continue;

        const output_name = b.fmt("{s}.spv", .{entry.name[0 .. entry.name.len - ".slang".len]});

        const cmd = b.addSystemCommand(&.{"slangc"});
        cmd.addFileArg(b.path(b.pathJoin(&.{ "resources/shaders", entry.name })));
        cmd.addArgs(&.{
            "-target",
            "spirv",
            "-profile",
            "spirv_1_4",
            "-emit-spirv-directly",
            "-fvk-use-entrypoint-name",
            "-entry",
            "vertMain",
            "-entry",
            "fragMain",
            "-o",
        });

        const output = cmd.addOutputFileArg(output_name);
        const install = b.addInstallFileWithDir(
            output,
            .bin,
            b.pathJoin(&.{ "resources/shaders", output_name }),
        );
        shaders_step.dependOn(&install.step);
    }
}
