const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_headers = b.dependency("vulkan_headers", .{});
    const registry = vulkan_headers.path("registry/vk.xml");
    const generated_vk_zig_path = "src/vulkan.zig";

    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    vk_generate_cmd.addFileArg(registry);

    const generate_step = b.step("generate", "Generate vk.zig bindings");
    const update_vk = b.addUpdateSourceFiles();
    update_vk.addCopyFileToSource(vk_generate_cmd.addOutputFileArg("vk.zig"), generated_vk_zig_path);
    generate_step.dependOn(&update_vk.step);

    const vulkan_zig = b.addModule("vulkan-zig", .{
        .root_source_file = b.path(generated_vk_zig_path),
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

    const profiles = addVulkanProfiles(.{
        .b = b,
        .target = target,
        .optimize = optimize,
        .registry = registry,
        .vulkan_include = vulkan_headers.path("include"),
    });

    const mod = b.addModule("vulkan", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("vulkan", vulkan_zig);
    mod.addImport("zglfw", zglfw_mod);
    mod.addImport("vulkan-profiles", profiles.module);
    mod.linkLibrary(profiles.library);
    if (target.result.os.tag != .emscripten) {
        mod.linkSystemLibrary("vulkan", .{});
        mod.linkLibrary(zglfw.artifact("glfw"));
    }

    const exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
    });
    if (!pathExists(b, generated_vk_zig_path)) {
        exe.step.dependOn(generate_step);
    }
    b.installArtifact(exe);

    const check_exe = b.addExecutable(.{
        .name = "vulkan",
        .root_module = mod,
        .use_llvm = true,
    });
    if (!pathExists(b, generated_vk_zig_path)) {
        check_exe.step.dependOn(generate_step);
    }

    const shaders_step = b.step("shaders", "Compile Slang shaders");
    addShaderCompileSteps(b, shaders_step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(shaders_step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const check = b.step("check", "Check if exe compiles");
    check.dependOn(&check_exe.step);
}

const VulkanProfiles = struct {
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
};

const VulkanProfilesOptions = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    registry: std.Build.LazyPath,
    vulkan_include: std.Build.LazyPath,
};

fn addVulkanProfiles(options: VulkanProfilesOptions) VulkanProfiles {
    const b = options.b;
    const generated = generateVulkanProfiles(b, options.registry);
    const include_path = generated.path(b, "include");
    const header = generated.path(b, "include/vulkan/vulkan_profiles.h");

    const lib_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .link_libcpp = true,
    });
    lib_mod.addIncludePath(include_path);
    lib_mod.addIncludePath(options.vulkan_include);
    lib_mod.addCSourceFile(.{
        .file = generated.path(b, "src/vulkan_profiles.cpp"),
        .flags = &.{ "-std=c++17", "-fno-exceptions", "-fno-rtti" },
    });

    const library = b.addLibrary(.{
        .name = "vulkan_profiles",
        .root_module = lib_mod,
        .linkage = .static,
    });

    const translate_c = b.addTranslateC(.{
        .root_source_file = header,
        .target = options.target,
        .optimize = options.optimize,
    });
    translate_c.addIncludePath(include_path);
    translate_c.addIncludePath(options.vulkan_include);

    return .{
        .module = translate_c.createModule(),
        .library = library,
    };
}

fn generateVulkanProfiles(b: *std.Build, registry: std.Build.LazyPath) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\
        \\set -eu
        \\mkdir -p "$1/include/vulkan" "$1/src"
        \\python3 -W ignore::DeprecationWarning "$4" \
        \\  --registry "$2" \
        \\  --input "$3" \
        \\  --output-library-inc "$1/include/vulkan" \
        \\  --output-library-src "$1/src"
        ,
        "sh",
    });

    const output = cmd.addOutputDirectoryArg("vulkan_profiles");
    cmd.addFileArg(registry);
    cmd.addDirectoryArg(b.path("vendor/vulkan_profiles/profiles"));
    cmd.addFileArg(b.path("vendor/vulkan_profiles/gen_profiles_solution.py"));

    return output;
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

fn pathExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return false;
    return true;
}
